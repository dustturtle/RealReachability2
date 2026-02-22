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
    /// Default URL for HTTP probe (generate_204 endpoint)
    public static let defaultURL = URL(string: "https://www.gstatic.com/generate_204")!
    
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
        await probe(allowsCellularAccess: true)
    }

    /// Probes the network with explicit cellular access policy.
    /// - Parameter allowsCellularAccess: Whether cellular can be used for this probe.
    /// - Returns: `true` if the probe was successful.
    public func probe(allowsCellularAccess: Bool) async -> Bool {
        let request = makeRequest(allowsCellularAccess: allowsCellularAccess)
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
#if DEBUG
                logProbe("failed allowsCellular=\(allowsCellularAccess) reason=non-http-response response=\(response)")
#endif
                return false
            }
            
            let success = isSuccessfulResponse(httpResponse)
#if DEBUG
            if success {
                logProbe("success allowsCellular=\(allowsCellularAccess) status=\(httpResponse.statusCode) responseURL=\(httpResponse.url?.absoluteString ?? "nil") expectedURL=\(url.absoluteString)")
            } else {
                logProbe("failed allowsCellular=\(allowsCellularAccess) status=\(httpResponse.statusCode) responseURL=\(httpResponse.url?.absoluteString ?? "nil") expectedURL=\(url.absoluteString)")
            }
#endif
            return success
        } catch {
            if isExpectedCancellation(error) {
                return false
            }
#if DEBUG
            logProbe("failed allowsCellular=\(allowsCellularAccess) error=\(error)")
#endif
            return false
        }
    }
    
    /// Probes with detailed result including latency
    /// - Returns: ProbeResult with success status and latency
    public func probeWithDetails() async -> ProbeResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let request = makeRequest(allowsCellularAccess: true)
        
        do {
            let (_, response) = try await session.data(for: request)
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            
            guard let httpResponse = response as? HTTPURLResponse else {
#if DEBUG
                logProbe("details failed reason=non-http-response response=\(response)")
#endif
                return ProbeResult(success: false, latencyMs: latency, error: nil)
            }
            
            let success = isSuccessfulResponse(httpResponse)
#if DEBUG
            if success {
                logProbe("details success status=\(httpResponse.statusCode) responseURL=\(httpResponse.url?.absoluteString ?? "nil") expectedURL=\(url.absoluteString)")
            } else {
                logProbe("details failed status=\(httpResponse.statusCode) responseURL=\(httpResponse.url?.absoluteString ?? "nil") expectedURL=\(url.absoluteString)")
            }
#endif
            return ProbeResult(success: success, latencyMs: latency, error: nil)
        } catch {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if isExpectedCancellation(error) {
                return ProbeResult(success: false, latencyMs: latency, error: nil)
            }
#if DEBUG
            logProbe("details failed error=\(error)")
#endif
            return ProbeResult(success: false, latencyMs: latency, error: error)
        }
    }

    private func makeRequest(allowsCellularAccess: Bool) -> URLRequest {
        var request = URLRequest(url: urlByAppendingNonce(url))
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        request.allowsCellularAccess = allowsCellularAccess
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private func urlByAppendingNonce(_ baseURL: URL) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "rr_nonce", value: UUID().uuidString))
        components.queryItems = items
        return components.url ?? baseURL
    }

    private func isSuccessfulResponse(_ response: HTTPURLResponse) -> Bool {
        guard let responseURL = response.url else {
            return false
        }
        
        let expectedHost = url.host?.lowercased()
        let actualHost = responseURL.host?.lowercased()
        guard expectedHost != nil, expectedHost == actualHost else {
            return false
        }
        
        let expectedPath = url.path.isEmpty ? "/" : url.path
        let actualPath = responseURL.path.isEmpty ? "/" : responseURL.path
        guard expectedPath == actualPath else {
            return false
        }
        
        if expectedPath == "/generate_204" {
            return response.statusCode == 204
        }
        return (200...299).contains(response.statusCode)
    }

    private func isExpectedCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

#if DEBUG
    private func logProbe(_ message: String) {
        NSLog("[HTTPProber] %@", message)
    }
#endif
}
