//
//  HTTPProber.swift
//  RealReachability2
//
//  Created by RealReachability2 on 2026.
//

import Foundation

/// HTTP HEAD prober for verifying internet connectivity
/// Uses Apple's captive portal detection URL for reliable connectivity checks
@available(iOS 13.0, *)
public final class HTTPProber: Prober, @unchecked Sendable {
    /// Default URL for HTTP probe (Apple's captive portal detection)
    public static let defaultURL = URL(string: "https://captive.apple.com/hotspot-detect.html")!
    
    /// The URL to probe
    private let url: URL
    
    /// Timeout interval for the request
    private let timeout: TimeInterval
    
    /// URLSession for making requests
    private let session: URLSession
    
    /// Creates a new HTTP prober
    /// - Parameters:
    ///   - url: The URL to probe (default: Apple's captive portal URL)
    ///   - timeout: Timeout interval in seconds (default: 5)
    public init(url: URL = HTTPProber.defaultURL, timeout: TimeInterval = 5.0) {
        self.url = url
        self.timeout = timeout
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }
    
    /// Probes the network using HTTP HEAD request
    /// - Returns: `true` if the probe was successful
    public func probe() async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            
            // Consider 2xx and 3xx responses as success
            // Apple's captive portal returns 200 when internet is available
            return (200...399).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }
    
    /// Probes with detailed result including latency
    /// - Returns: ProbeResult with success status and latency
    public func probeWithDetails() async -> ProbeResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        
        do {
            let (_, response) = try await session.data(for: request)
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return ProbeResult(success: false, latencyMs: latency, error: nil)
            }
            
            let success = (200...399).contains(httpResponse.statusCode)
            return ProbeResult(success: success, latencyMs: latency, error: nil)
        } catch {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return ProbeResult(success: false, latencyMs: latency, error: error)
        }
    }
}
