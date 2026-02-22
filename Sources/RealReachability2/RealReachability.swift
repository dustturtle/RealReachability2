//
//  RealReachability.swift
//  RealReachability2
//
//  Created by RealReachability2 on 2026.
//

import Foundation
import Network

/// Probe mode for network reachability checks
@available(iOS 13.0, *)
public enum ProbeMode: Sendable {
    /// Use both HTTP and ICMP probes in parallel (default, most reliable)
    case parallel

    /// Use only HTTP HEAD probe
    case httpOnly

    /// Use only ICMP ping probe
    case icmpOnly
}

/// Configuration for RealReachability
@available(iOS 13.0, *)
public struct ReachabilityConfiguration: Sendable {
    /// Probe mode to use for checking connectivity
    public var probeMode: ProbeMode

    /// Timeout for probe requests
    public var timeout: TimeInterval

    /// HTTP probe URL
    public var httpProbeURL: URL

    /// ICMP ping host
    public var icmpHost: String

    /// ICMP ping port
    public var icmpPort: UInt16

    /// Enables periodic probing while notifier is running.
    public var periodicProbeEnabled: Bool

    /// Enables cellular fallback when primary Wi-Fi probe fails.
    /// Requires HTTP participation (.parallel or .httpOnly). Invalid with .icmpOnly.
    public var allowCellularFallback: Bool

    /// Default configuration
    public static let `default` = ReachabilityConfiguration(
        probeMode: .parallel,
        timeout: 5.0,
        httpProbeURL: HTTPProber.defaultURL,
        icmpHost: ICMPPinger.defaultHost,
        icmpPort: ICMPPinger.defaultPort,
        periodicProbeEnabled: true,
        allowCellularFallback: false
    )

    public init(
        probeMode: ProbeMode = .parallel,
        timeout: TimeInterval = 5.0,
        httpProbeURL: URL = HTTPProber.defaultURL,
        icmpHost: String = ICMPPinger.defaultHost,
        icmpPort: UInt16 = ICMPPinger.defaultPort,
        periodicProbeEnabled: Bool = true,
        allowCellularFallback: Bool = false
    ) {
        self.probeMode = probeMode
        self.timeout = timeout
        self.httpProbeURL = httpProbeURL
        self.icmpHost = icmpHost
        self.icmpPort = icmpPort
        self.periodicProbeEnabled = periodicProbeEnabled
        self.allowCellularFallback = allowCellularFallback
    }
}

/// Main class for checking real network reachability
@available(iOS 13.0, *)
public final class RealReachability: @unchecked Sendable {
    private struct ProbeOutcome {
        let reachable: Bool
        let secondaryReachable: Bool
    }

    private static let periodicProbeInterval: UInt64 = 5_000_000_000

    /// Shared singleton instance
    public static let shared = RealReachability()

    /// Configuration for reachability checks
    public var configuration: ReachabilityConfiguration {
        didSet {
            updateProbers()
            applyRuntimeConfigurationChange()
        }
    }

    /// Path monitor wrapper
    private let pathMonitor: PathMonitorWrapper

    /// HTTP prober
    private var httpProber: HTTPProber

    /// ICMP pinger
    private var icmpPinger: ICMPPinger

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Current reachability status
    private var currentStatus: ReachabilityStatus = .unknown

    /// Secondary-link reachability state (for example, cellular fallback while on Wi-Fi)
    private var currentSecondaryReachable = false

    /// Continuation for the status stream
    private var statusContinuation: AsyncStream<ReachabilityStatus>.Continuation?

    /// Whether the notifier is running
    private var isNotifierRunning = false

    /// Task consuming path monitor updates
    private var pathMonitorTask: Task<Void, Never>?

    /// Periodic probe task
    private var periodicProbeTask: Task<Void, Never>?

    /// Probe state to avoid overlapping probe runs
    private var probeInFlight = false

    /// Last pending path update while probe is in flight
    private var pendingProbePath: NWPath?

    /// Monotonic sequence for invalidating stale probe results
    private var probeSequence: UInt64 = 0

    /// Whether current status is reachable through secondary fallback link.
    public var isSecondaryReachable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentSecondaryReachable
    }

    /// Creates a new RealReachability instance
    /// - Parameter configuration: Configuration for reachability checks
    public init(configuration: ReachabilityConfiguration = .default) {
        self.configuration = configuration
        self.pathMonitor = PathMonitorWrapper()
        self.httpProber = HTTPProber(url: configuration.httpProbeURL, timeout: configuration.timeout)
        self.icmpPinger = ICMPPinger(host: configuration.icmpHost, port: configuration.icmpPort, timeout: configuration.timeout)
    }

    private func withLockedState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Updates probers based on current configuration
    private func updateProbers() {
        lock.lock()
        httpProber = HTTPProber(url: configuration.httpProbeURL, timeout: configuration.timeout)
        icmpPinger = ICMPPinger(host: configuration.icmpHost, port: configuration.icmpPort, timeout: configuration.timeout)
        lock.unlock()
    }

    private func applyRuntimeConfigurationChange() {
        lock.lock()
        let notifierRunning = isNotifierRunning
        let periodicEnabled = configuration.periodicProbeEnabled
        let config = configuration
        lock.unlock()

        _ = validateCellularFallbackConfiguration(config)

        guard notifierRunning else {
            return
        }

        if periodicEnabled {
            startPeriodicProbeIfNeeded()
            Task { [weak self] in
                await self?.handlePeriodicProbeTick()
            }
        } else {
            stopPeriodicProbeIfNeeded()
        }
    }

    // MARK: - One-time Check

    /// Performs a one-time network reachability check
    /// - Returns: The current reachability status
    public func check() async -> ReachabilityStatus {
        let path: NWPath?
        if let existingPath = pathMonitor.path {
            path = existingPath
        } else {
            path = await getCurrentPath()
        }

        guard path?.status == .satisfied else {
            setSecondaryReachableForCheck(false)
            return .notReachable
        }

        let connectionType = getConnectionType(from: path)
        let outcome = await performProbe(for: connectionType)
        setSecondaryReachableForCheck(outcome.secondaryReachable)

        if outcome.reachable {
            return .reachable(connectionType)
        }
        return .notReachable
    }

    private func setSecondaryReachableForCheck(_ reachable: Bool) {
        lock.lock()
        currentSecondaryReachable = reachable
        lock.unlock()
    }

    /// Gets the current network path asynchronously
    private func getCurrentPath() async -> NWPath? {
        await withCheckedContinuation { continuation in
            let tempMonitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.realreachability2.tempmonitor")

            tempMonitor.pathUpdateHandler = { path in
                tempMonitor.cancel()
                continuation.resume(returning: path)
            }
            tempMonitor.start(queue: queue)
        }
    }

    /// Performs the probe based on configuration and current connection type.
    private func performProbe(for connectionType: ConnectionType) async -> ProbeOutcome {
        let (config, http, icmp) = withLockedState { (configuration, httpProber, icmpPinger) }

        if shouldAttemptCellularFallback(for: connectionType, configuration: config) {
            guard validateCellularFallbackConfiguration(config) else {
                return ProbeOutcome(reachable: false, secondaryReachable: false)
            }

            let primaryReachable: Bool
            switch config.probeMode {
            case .parallel:
                primaryReachable = await probeParallel(http: http, icmp: icmp, httpAllowsCellular: false)
            case .httpOnly:
                primaryReachable = await http.probe(allowsCellularAccess: false)
            case .icmpOnly:
                primaryReachable = false
            }

            if primaryReachable {
                return ProbeOutcome(reachable: true, secondaryReachable: false)
            }

            let fallbackReachable = await http.probe(allowsCellularAccess: true)
            return ProbeOutcome(reachable: fallbackReachable, secondaryReachable: fallbackReachable)
        }

        // Wi-Fi primary probing should not silently route through cellular when fallback is disabled.
        if connectionType == .wifi && probeModeSupportsHTTP(config.probeMode) && !config.allowCellularFallback {
            switch config.probeMode {
            case .parallel:
                let reachable = await probeParallel(http: http, icmp: icmp, httpAllowsCellular: false)
                return ProbeOutcome(reachable: reachable, secondaryReachable: false)
            case .httpOnly:
                let reachable = await http.probe(allowsCellularAccess: false)
                return ProbeOutcome(reachable: reachable, secondaryReachable: false)
            case .icmpOnly:
                break
            }
        }

        switch config.probeMode {
        case .parallel:
            let reachable = await probeParallel(http: http, icmp: icmp, httpAllowsCellular: true)
            return ProbeOutcome(reachable: reachable, secondaryReachable: false)
        case .httpOnly:
            let reachable = await http.probe(allowsCellularAccess: true)
            return ProbeOutcome(reachable: reachable, secondaryReachable: false)
        case .icmpOnly:
            let reachable = await icmp.probe()
            return ProbeOutcome(reachable: reachable, secondaryReachable: false)
        }
    }

    private func shouldAttemptCellularFallback(for connectionType: ConnectionType,
                                               configuration: ReachabilityConfiguration) -> Bool {
        configuration.allowCellularFallback && connectionType == .wifi
    }

    private func probeModeSupportsHTTP(_ mode: ProbeMode) -> Bool {
        mode == .parallel || mode == .httpOnly
    }

    @discardableResult
    private func validateCellularFallbackConfiguration(_ config: ReachabilityConfiguration) -> Bool {
        guard config.allowCellularFallback else {
            return true
        }

        if probeModeSupportsHTTP(config.probeMode) {
            return true
        }

        let message = "[RealReachability] Configuration error: allowCellularFallback requires HTTP participation (.parallel or .httpOnly)."
#if DEBUG
        NSLog("%@", message)
#endif
        assertionFailure(message)
        return false
    }

    /// Performs parallel HTTP and ICMP probes.
    /// - Parameter httpAllowsCellular: Whether cellular is allowed for the HTTP branch.
    /// - Returns: `true` if either probe succeeds.
    private func probeParallel(http: HTTPProber, icmp: ICMPPinger, httpAllowsCellular: Bool) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await http.probe(allowsCellularAccess: httpAllowsCellular)
            }

            group.addTask {
                await icmp.probe()
            }

            for await result in group {
                if result {
                    group.cancelAll()
                    return true
                }
            }

            return false
        }
    }

    // MARK: - Continuous Monitoring

    /// Async stream of reachability status changes.
    /// Emits when status changes, or when secondary fallback state changes.
    public var statusStream: AsyncStream<ReachabilityStatus> {
        AsyncStream { continuation in
            self.startNotifier()

            self.lock.lock()
            self.statusContinuation = continuation
            let status = self.currentStatus
            self.lock.unlock()

            continuation.yield(status)

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.statusContinuation = nil
                self?.lock.unlock()
            }
        }
    }

    /// Starts the notifier
    public func startNotifier() {
        lock.lock()
        guard !isNotifierRunning else {
            lock.unlock()
            return
        }
        isNotifierRunning = true
        lock.unlock()

        pathMonitor.start()
        startPathMonitorTaskIfNeeded()
        startPeriodicProbeIfNeeded()
    }

    /// Stops the notifier
    public func stopNotifier() {
        lock.lock()
        guard isNotifierRunning else {
            lock.unlock()
            return
        }
        isNotifierRunning = false
        probeSequence &+= 1
        probeInFlight = false
        pendingProbePath = nil
        statusContinuation?.finish()
        statusContinuation = nil
        lock.unlock()

        stopPeriodicProbeIfNeeded()

        pathMonitor.stop()
        pathMonitorTask?.cancel()
        pathMonitorTask = nil
    }

    private func startPathMonitorTaskIfNeeded() {
        lock.lock()
        let shouldStart = isNotifierRunning && pathMonitorTask == nil
        lock.unlock()

        guard shouldStart else {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            for await path in self.pathMonitor.pathStream {
                if Task.isCancelled {
                    break
                }
                await self.handlePathChange(path)
            }
        }

        lock.lock()
        if isNotifierRunning && pathMonitorTask == nil {
            pathMonitorTask = task
            lock.unlock()
        } else {
            lock.unlock()
            task.cancel()
        }
    }

    private func startPeriodicProbeIfNeeded() {
        lock.lock()
        let shouldStart = isNotifierRunning && configuration.periodicProbeEnabled && periodicProbeTask == nil
        lock.unlock()

        guard shouldStart else {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.periodicProbeInterval)
                } catch {
                    break
                }

                if Task.isCancelled {
                    break
                }

                await self.handlePeriodicProbeTick()
            }
        }

        lock.lock()
        if isNotifierRunning && configuration.periodicProbeEnabled && periodicProbeTask == nil {
            periodicProbeTask = task
            lock.unlock()
        } else {
            lock.unlock()
            task.cancel()
        }
    }

    private func stopPeriodicProbeIfNeeded() {
        lock.lock()
        let task = periodicProbeTask
        periodicProbeTask = nil
        lock.unlock()
        task?.cancel()
    }

    private func handlePeriodicProbeTick() async {
        let shouldRun = withLockedState {
            isNotifierRunning && configuration.periodicProbeEnabled
        }

        guard shouldRun else {
            return
        }

        guard let path = pathMonitor.path, path.status == .satisfied else {
            await handleUnsatisfiedPath()
            return
        }

        await triggerProbe(for: path)
    }

    /// Handles path changes from the monitor.
    private func handlePathChange(_ path: NWPath) async {
        if path.status == .satisfied {
            await triggerProbe(for: path)
        } else {
            await handleUnsatisfiedPath()
        }
    }

    private func handleUnsatisfiedPath() async {
        withLockedState {
            probeSequence &+= 1
            probeInFlight = false
            pendingProbePath = nil
        }

        updateStatus(.notReachable, secondaryReachable: false)
    }

    private func triggerProbe(for path: NWPath) async {
        let type = getConnectionType(from: path)

        let token: UInt64? = withLockedState {
            guard isNotifierRunning else {
                return nil
            }

            if probeInFlight {
                pendingProbePath = path
                return nil
            }

            probeInFlight = true
            probeSequence &+= 1
            return probeSequence
        }

        guard let token else {
            return
        }

        await runProbe(connectionType: type, token: token)
    }

    private func runProbe(connectionType: ConnectionType, token: UInt64) async {
        let outcome = await performProbe(for: connectionType)

        var shouldApplyResult = false
        var shouldRunPendingProbe = false
        var nextType: ConnectionType = .other
        var nextToken: UInt64 = 0

        withLockedState {
            shouldApplyResult = isNotifierRunning && (token == probeSequence)

            if let pendingPath = pendingProbePath,
               isNotifierRunning,
               pendingPath.status == .satisfied {
                shouldRunPendingProbe = true
                nextType = getConnectionType(from: pendingPath)
                pendingProbePath = nil
                probeSequence &+= 1
                nextToken = probeSequence
                probeInFlight = true
            } else {
                pendingProbePath = nil
                probeInFlight = false
            }
        }

        if shouldApplyResult {
            let status: ReachabilityStatus = outcome.reachable ? .reachable(connectionType) : .notReachable
            updateStatus(status, secondaryReachable: outcome.secondaryReachable)
        }

        if shouldRunPendingProbe {
            await runProbe(connectionType: nextType, token: nextToken)
        }
    }

    private func updateStatus(_ status: ReachabilityStatus, secondaryReachable: Bool) {
        lock.lock()
        let statusChanged = currentStatus != status
        let secondaryChanged = currentSecondaryReachable != secondaryReachable
        let shouldNotify = statusChanged || secondaryChanged
        currentStatus = status
        currentSecondaryReachable = secondaryReachable
        let continuation = statusContinuation
        lock.unlock()

        if shouldNotify {
            continuation?.yield(status)
        }
    }

    /// Gets the connection type from a path
    private func getConnectionType(from path: NWPath?) -> ConnectionType {
        guard let path else { return .other }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wired
        } else {
            return .other
        }
    }
}
