//
//  ReachabilityStatus.swift
//  RealReachability2
//
//  Created by RealReachability2 on 2026.
//

import Foundation

/// Represents the network reachability status
@available(iOS 13.0, *)
public enum ReachabilityStatus: Equatable, Sendable {
    /// Network is reachable and can access the internet
    case reachable(ConnectionType)
    
    /// Network connection exists but cannot access the internet
    case notReachable
    
    /// Network status is unknown or being determined
    case unknown
    
    /// Returns true if the network is reachable
    public var isReachable: Bool {
        if case .reachable = self {
            return true
        }
        return false
    }
}

/// The type of network connection
@available(iOS 13.0, *)
public enum ConnectionType: Equatable, Sendable {
    /// WiFi connection
    case wifi
    
    /// Cellular connection
    case cellular
    
    /// Wired/Ethernet connection
    case wired
    
    /// Other or unknown connection type
    case other
}
