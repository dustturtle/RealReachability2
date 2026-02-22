//
//  PathMonitorWrapper.swift
//  RealReachability2
//
//  Created by RealReachability2 on 2026.
//

import Foundation
import Network

/// Wrapper for NWPathMonitor that provides async/await interface
@available(iOS 13.0, *)
final class PathMonitorWrapper: @unchecked Sendable {
    /// The underlying NWPathMonitor
    private var monitor: NWPathMonitor?

    /// The queue for path monitor callbacks
    private let queue: DispatchQueue

    /// Current path status
    private var currentPath: NWPath?

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Continuation for the async stream
    private var continuation: AsyncStream<NWPath>.Continuation?

    /// Whether the monitor is running
    private var isRunning = false

    /// Creates a new path monitor wrapper
    /// - Parameter queue: The queue for callbacks (default: a new background queue)
    init(queue: DispatchQueue = DispatchQueue(label: "com.realreachability2.pathmonitor")) {
        self.queue = queue
    }

    /// Starts monitoring network path changes
    func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }

        isRunning = true
        let monitor = NWPathMonitor()
        self.monitor = monitor
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        monitor.start(queue: queue)
    }

    /// Stops monitoring
    func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }

        isRunning = false
        let monitor = self.monitor
        self.monitor = nil
        continuation?.finish()
        continuation = nil
        lock.unlock()

        monitor?.cancel()
    }

    /// Gets the current network path
    var path: NWPath? {
        lock.lock()
        defer { lock.unlock() }
        return currentPath
    }

    /// Returns whether the network is currently satisfied
    var isSatisfied: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.status == .satisfied
    }

    /// Returns the current connection type
    var connectionType: ConnectionType {
        lock.lock()
        defer { lock.unlock() }
        return getConnectionType(from: currentPath)
    }

    /// Creates an async stream of path updates
    var pathStream: AsyncStream<NWPath> {
        AsyncStream { continuation in
            self.lock.lock()
            self.continuation = continuation
            if let currentPath = self.currentPath {
                continuation.yield(currentPath)
            }
            self.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuation = nil
                self?.lock.unlock()
            }
        }
    }

    /// Handles path updates
    private func handlePathUpdate(_ path: NWPath) {
        lock.lock()
        currentPath = path
        let cont = continuation
        lock.unlock()

        cont?.yield(path)
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
