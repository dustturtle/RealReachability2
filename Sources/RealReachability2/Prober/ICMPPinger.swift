//
//  ICMPPinger.swift
//  RealReachability2
//
//  Created by RealReachability2 on 2026.
//

import Foundation

/// ICMP Ping prober for verifying internet connectivity
/// Uses real ICMP echo request/reply for accurate network reachability testing.
@available(iOS 13.0, *)
public final class ICMPPinger: Prober, @unchecked Sendable {
    /// Default host for ping (Google DNS)
    public static let defaultHost = "8.8.8.8"
    
    /// Default port (kept for API compatibility, not used for real ICMP)
    public static let defaultPort: UInt16 = 53
    
    /// The host to ping
    private let host: String
    
    /// The port (kept for API compatibility, not used for real ICMP)
    private let port: UInt16
    
    /// Timeout interval
    private let timeout: TimeInterval
    
    /// Creates a new ICMP pinger
    /// - Parameters:
    ///   - host: The host to ping (default: 8.8.8.8)
    ///   - port: Kept for API compatibility (not used for real ICMP ping)
    ///   - timeout: Timeout interval in seconds (default: 5)
    public init(host: String = ICMPPinger.defaultHost,
                port: UInt16 = ICMPPinger.defaultPort,
                timeout: TimeInterval = 5.0) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }
    
    /// Probes the network using real ICMP ping
    /// - Returns: `true` if the probe was successful
    public func probe() async -> Bool {
        await withCheckedContinuation { continuation in
            // Use a dedicated class to manage the ping operation
            let pingOperation = PingOperation(host: host, timeout: timeout)
            pingOperation.ping { success in
                continuation.resume(returning: success)
            }
        }
    }
    
    /// Probes with detailed result including latency
    /// - Returns: ProbeResult with success status and latency
    public func probeWithDetails() async -> ProbeResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let success = await probe()
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return ProbeResult(success: success, latencyMs: latency, error: nil)
    }
}

// MARK: - Ping Operation

/// Internal class to manage a single ping operation with RunLoop
@available(iOS 13.0, *)
private final class PingOperation: NSObject, PingFoundationDelegate {
    private let host: String
    private let timeout: TimeInterval
    private var pingFoundation: PingFoundation?
    private var completion: ((Bool) -> Void)?
    private var hasCompleted = false
    private var timeoutTimer: Timer?
    private let lock = NSLock()
    
    init(host: String, timeout: TimeInterval) {
        self.host = host
        self.timeout = timeout
        super.init()
    }
    
    func ping(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        
        // Run on main thread for RunLoop integration
        if Thread.isMainThread {
            startPing()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startPing()
            }
        }
    }
    
    private func startPing() {
        pingFoundation = PingFoundation(hostName: host)
        pingFoundation?.delegate = self
        pingFoundation?.start()
        
        // Setup timeout
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.finishWithResult(false)
        }
    }
    
    private func finishWithResult(_ success: Bool) {
        lock.lock()
        guard !hasCompleted else {
            lock.unlock()
            return
        }
        hasCompleted = true
        lock.unlock()
        
        DispatchQueue.main.async { [weak self] in
            self?.timeoutTimer?.invalidate()
            self?.timeoutTimer = nil
            self?.pingFoundation?.stop()
            self?.pingFoundation = nil
            self?.completion?(success)
            self?.completion = nil
        }
    }
    
    // MARK: - PingFoundationDelegate
    
    func pingFoundation(_ pinger: PingFoundation, didStartWithAddress address: Data) {
        // Send ping immediately when started
        pinger.sendPing(with: nil)
    }
    
    func pingFoundation(_ pinger: PingFoundation, didFailWithError error: Error) {
        finishWithResult(false)
    }
    
    func pingFoundation(_ pinger: PingFoundation, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {
        finishWithResult(false)
    }
    
    func pingFoundation(_ pinger: PingFoundation, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16) {
        finishWithResult(true)
    }
}
