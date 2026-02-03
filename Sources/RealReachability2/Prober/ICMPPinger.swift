//
//  ICMPPinger.swift
//  RealReachability2
//
//  Created by RealReachability2 on 2026.
//

import Foundation
import Network

/// ICMP Ping prober for verifying internet connectivity
/// Note: On iOS, true ICMP requires special entitlements.
/// This implementation uses a TCP connection check as a fallback.
@available(iOS 13.0, *)
public final class ICMPPinger: Prober, @unchecked Sendable {
    /// Default host for ping (Google DNS)
    public static let defaultHost = "8.8.8.8"
    
    /// Default port for TCP check
    public static let defaultPort: UInt16 = 53
    
    /// The host to ping
    private let host: String
    
    /// The port for TCP check
    private let port: UInt16
    
    /// Timeout interval
    private let timeout: TimeInterval
    
    /// Creates a new ICMP pinger
    /// - Parameters:
    ///   - host: The host to ping (default: 8.8.8.8)
    ///   - port: The port for TCP check (default: 53)
    ///   - timeout: Timeout interval in seconds (default: 5)
    public init(host: String = ICMPPinger.defaultHost,
                port: UInt16 = ICMPPinger.defaultPort,
                timeout: TimeInterval = 5.0) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }
    
    /// Probes the network using TCP connection
    /// - Returns: `true` if the probe was successful
    public func probe() async -> Bool {
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            
            var isResumed = false
            let lock = NSLock()
            
            // Set up timeout
            let timeoutWorkItem = DispatchWorkItem { [weak connection] in
                lock.lock()
                if !isResumed {
                    isResumed = true
                    lock.unlock()
                    connection?.cancel()
                    continuation.resume(returning: false)
                } else {
                    lock.unlock()
                }
            }
            
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWorkItem
            )
            
            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    lock.lock()
                    if !isResumed {
                        isResumed = true
                        lock.unlock()
                        timeoutWorkItem.cancel()
                        connection?.cancel()
                        continuation.resume(returning: true)
                    } else {
                        lock.unlock()
                    }
                    
                case .failed, .cancelled:
                    lock.lock()
                    if !isResumed {
                        isResumed = true
                        lock.unlock()
                        timeoutWorkItem.cancel()
                        connection?.cancel()
                        continuation.resume(returning: false)
                    } else {
                        lock.unlock()
                    }
                    
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
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
