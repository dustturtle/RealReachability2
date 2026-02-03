//
//  ProberProtocol.swift
//  RealReachability2
//
//  Created by RealReachability2 on 2026.
//

import Foundation

/// Protocol for network probers that verify internet connectivity
@available(iOS 13.0, *)
public protocol Prober: Sendable {
    /// Probes the network to verify internet connectivity
    /// - Returns: `true` if the probe was successful and internet is reachable
    func probe() async -> Bool
}

/// Result of a probe operation
@available(iOS 13.0, *)
public struct ProbeResult: Sendable {
    /// Whether the probe was successful
    public let success: Bool
    
    /// The latency of the probe in milliseconds (if successful)
    public let latencyMs: Double?
    
    /// Any error that occurred during the probe
    public let error: Error?
    
    public init(success: Bool, latencyMs: Double? = nil, error: Error? = nil) {
        self.success = success
        self.latencyMs = latencyMs
        self.error = error
    }
}
