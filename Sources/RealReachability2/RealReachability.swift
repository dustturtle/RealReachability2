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
    
    /// Default configuration
    public static let `default` = ReachabilityConfiguration(
        probeMode: .parallel,
        timeout: 5.0,
        httpProbeURL: HTTPProber.defaultURL,
        icmpHost: ICMPPinger.defaultHost,
        icmpPort: ICMPPinger.defaultPort
    )
    
    public init(
        probeMode: ProbeMode = .parallel,
        timeout: TimeInterval = 5.0,
        httpProbeURL: URL = HTTPProber.defaultURL,
        icmpHost: String = ICMPPinger.defaultHost,
        icmpPort: UInt16 = ICMPPinger.defaultPort
    ) {
        self.probeMode = probeMode
        self.timeout = timeout
        self.httpProbeURL = httpProbeURL
        self.icmpHost = icmpHost
        self.icmpPort = icmpPort
    }
}

/// Main class for checking real network reachability
@available(iOS 13.0, *)
public final class RealReachability: @unchecked Sendable {
    /// Shared singleton instance
    public static let shared = RealReachability()
    
    /// Configuration for reachability checks
    public var configuration: ReachabilityConfiguration {
        didSet {
            updateProbers()
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
    
    /// Continuation for the status stream
    private var statusContinuation: AsyncStream<ReachabilityStatus>.Continuation?
    
    /// Whether the notifier is running
    private var isNotifierRunning = false
    
    /// Creates a new RealReachability instance
    /// - Parameter configuration: Configuration for reachability checks
    public init(configuration: ReachabilityConfiguration = .default) {
        self.configuration = configuration
        self.pathMonitor = PathMonitorWrapper()
        self.httpProber = HTTPProber(url: configuration.httpProbeURL, timeout: configuration.timeout)
        self.icmpPinger = ICMPPinger(host: configuration.icmpHost, port: configuration.icmpPort, timeout: configuration.timeout)
    }
    
    /// Updates probers based on current configuration
    private func updateProbers() {
        lock.lock()
        httpProber = HTTPProber(url: configuration.httpProbeURL, timeout: configuration.timeout)
        icmpPinger = ICMPPinger(host: configuration.icmpHost, port: configuration.icmpPort, timeout: configuration.timeout)
        lock.unlock()
    }
    
    // MARK: - One-time Check
    
    /// Performs a one-time network reachability check
    /// - Returns: The current reachability status
    public func check() async -> ReachabilityStatus {
        // First, check if we have a network path
        let path: NWPath?
        if let existingPath = pathMonitor.path {
            path = existingPath
        } else {
            path = await getCurrentPath()
        }
        
        guard path?.status == .satisfied else {
            return .notReachable
        }
        
        let connectionType = getConnectionType(from: path)
        
        // Probe based on configuration
        let isReachable = await performProbe()
        
        if isReachable {
            return .reachable(connectionType)
        } else {
            return .notReachable
        }
    }
    
    /// Gets the current network path asynchronously
    private func getCurrentPath() async -> NWPath? {
        return await withCheckedContinuation { continuation in
            let tempMonitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.realreachability2.tempmonitor")
            
            tempMonitor.pathUpdateHandler = { path in
                tempMonitor.cancel()
                continuation.resume(returning: path)
            }
            tempMonitor.start(queue: queue)
        }
    }
    
    /// Performs the probe based on configuration
    private func performProbe() async -> Bool {
        lock.lock()
        let mode = configuration.probeMode
        let http = httpProber
        let icmp = icmpPinger
        lock.unlock()
        
        switch mode {
        case .parallel:
            return await probeParallel(http: http, icmp: icmp)
        case .httpOnly:
            return await http.probe()
        case .icmpOnly:
            return await icmp.probe()
        }
    }
    
    /// Performs parallel HTTP and ICMP probes
    /// - Returns: `true` if either probe succeeds
    private func probeParallel(http: HTTPProber, icmp: ICMPPinger) async -> Bool {
        // Use TaskGroup to run both probes in parallel
        // Return true as soon as either succeeds
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await http.probe()
            }
            
            group.addTask {
                await icmp.probe()
            }
            
            // Return as soon as we get a successful result
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
    
    /// Async stream of reachability status changes
    public var statusStream: AsyncStream<ReachabilityStatus> {
        AsyncStream { continuation in
            // Start the path monitor if not running
            self.startNotifier()
            
            self.lock.lock()
            self.statusContinuation = continuation
            
            // Emit current status immediately
            let status = self.currentStatus
            self.lock.unlock()
            
            continuation.yield(status)
            
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.statusContinuation = nil
                self?.lock.unlock()
            }
            
            // Start monitoring path changes
            Task { [weak self] in
                guard let self = self else { return }
                
                for await path in self.pathMonitor.pathStream {
                    await self.handlePathChange(path)
                }
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
    }
    
    /// Stops the notifier
    public func stopNotifier() {
        lock.lock()
        guard isNotifierRunning else {
            lock.unlock()
            return
        }
        isNotifierRunning = false
        lock.unlock()
        
        pathMonitor.stop()
        
        lock.lock()
        statusContinuation?.finish()
        statusContinuation = nil
        lock.unlock()
    }
    
    /// Handles path changes from the monitor
    private func handlePathChange(_ path: NWPath) async {
        let newStatus: ReachabilityStatus
        
        if path.status == .satisfied {
            let connectionType = getConnectionType(from: path)
            let isReachable = await performProbe()
            
            if isReachable {
                newStatus = .reachable(connectionType)
            } else {
                newStatus = .notReachable
            }
        } else {
            newStatus = .notReachable
        }
        
        lock.lock()
        let shouldNotify = currentStatus != newStatus
        currentStatus = newStatus
        let continuation = statusContinuation
        lock.unlock()
        
        if shouldNotify {
            continuation?.yield(newStatus)
        }
    }
    #endif
    
    /// Gets the connection type from a path
    #if canImport(Network)
    private func getConnectionType(from path: NWPath?) -> ConnectionType {
        guard let path = path else { return .other }
        
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
