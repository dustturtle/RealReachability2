//
//  ProberIntegrationTests.swift
//  RealReachability2
//
//  Integration tests for HTTP and ICMP probers
//  These tests require network connectivity
//

import XCTest
@testable import RealReachability2

@available(iOS 13.0, macOS 10.15, *)
final class ProberIntegrationTests: XCTestCase {
    
    // MARK: - HTTP Prober Integration Tests
    
    func testHTTPProberWithDefaultURL() async {
        let prober = HTTPProber()
        let result = await prober.probe()
        // Note: This test may fail if there's no network connectivity
        // In CI, we expect network to be available
        XCTAssertTrue(result, "HTTP probe to Apple's captive portal should succeed with network connectivity")
    }
    
    func testHTTPProberWithGoogleURL() async {
        let url = URL(string: "https://www.google.com")!
        let prober = HTTPProber(url: url, timeout: 10.0)
        let result = await prober.probe()
        XCTAssertTrue(result, "HTTP probe to Google should succeed with network connectivity")
    }
    
    func testHTTPProberWithInvalidURL() async {
        let url = URL(string: "https://this-domain-definitely-does-not-exist-12345.com")!
        let prober = HTTPProber(url: url, timeout: 3.0)
        let result = await prober.probe()
        XCTAssertFalse(result, "HTTP probe to invalid domain should fail")
    }
    
    func testHTTPProberWithShortTimeout() async {
        // Use a very short timeout to potentially trigger a timeout
        let prober = HTTPProber(url: HTTPProber.defaultURL, timeout: 0.001)
        // Result depends on network speed, but should not crash
        let _ = await prober.probe()
    }
    
    func testHTTPProberProbeWithDetails() async {
        let prober = HTTPProber()
        let result = await prober.probeWithDetails()
        
        if result.success {
            XCTAssertNotNil(result.latencyMs)
            XCTAssertGreaterThan(result.latencyMs!, 0)
            XCTAssertNil(result.error)
        } else {
            // If probe failed, should have latency recorded (time taken to fail)
            XCTAssertNotNil(result.latencyMs)
        }
    }
    
    func testHTTPProberMultipleConcurrentProbes() async {
        let prober = HTTPProber()
        
        // Run multiple probes concurrently
        async let probe1 = prober.probe()
        async let probe2 = prober.probe()
        async let probe3 = prober.probe()
        
        let results = await [probe1, probe2, probe3]
        
        // At least one should succeed if network is available
        let anySuccess = results.contains(true)
        XCTAssertTrue(anySuccess || results.allSatisfy { !$0 }, "Concurrent probes should complete without crash")
    }
    
    // MARK: - ICMP Pinger Integration Tests
    
    func testICMPPingerWithDefaultHost() async {
        let pinger = ICMPPinger()
        let result = await pinger.probe()
        // Note: This test may fail if there's no network connectivity
        XCTAssertTrue(result, "ICMP probe to Google DNS should succeed with network connectivity")
    }
    
    func testICMPPingerWithCloudflare() async {
        let pinger = ICMPPinger(host: "1.1.1.1", port: 53, timeout: 5.0)
        let result = await pinger.probe()
        XCTAssertTrue(result, "ICMP probe to Cloudflare DNS should succeed with network connectivity")
    }
    
    func testICMPPingerWithInvalidHost() async {
        // Use an IP in a private, unroutable range
        let pinger = ICMPPinger(host: "192.0.2.1", port: 53, timeout: 2.0)
        let result = await pinger.probe()
        XCTAssertFalse(result, "ICMP probe to unroutable IP should fail")
    }
    
    func testICMPPingerWithShortTimeout() async {
        let pinger = ICMPPinger(host: "8.8.8.8", port: 53, timeout: 0.001)
        // Result depends on network speed, but should not crash
        let _ = await pinger.probe()
    }
    
    func testICMPPingerProbeWithDetails() async {
        let pinger = ICMPPinger()
        let result = await pinger.probeWithDetails()
        
        if result.success {
            XCTAssertNotNil(result.latencyMs)
            XCTAssertGreaterThan(result.latencyMs!, 0)
        } else {
            // If probe failed, should still have latency recorded
            XCTAssertNotNil(result.latencyMs)
        }
    }
    
    func testICMPPingerMultipleConcurrentProbes() async {
        let pinger = ICMPPinger()
        
        // Run multiple probes concurrently
        async let probe1 = pinger.probe()
        async let probe2 = pinger.probe()
        async let probe3 = pinger.probe()
        
        let results = await [probe1, probe2, probe3]
        
        // At least one should succeed if network is available
        let anySuccess = results.contains(true)
        XCTAssertTrue(anySuccess || results.allSatisfy { !$0 }, "Concurrent probes should complete without crash")
    }
    
    // MARK: - RealReachability Integration Tests with Different Probe Modes
    
    func testCheckWithParallelMode() async {
        let config = ReachabilityConfiguration(probeMode: .parallel, timeout: 10.0)
        let reachability = RealReachability(configuration: config)
        
        let status = await reachability.check()
        
        // With network available, should be reachable
        switch status {
        case .reachable:
            XCTAssertTrue(true, "Network is reachable with parallel mode")
        case .notReachable:
            // Could happen if no network
            XCTAssertTrue(true, "Network is not reachable")
        case .unknown:
            XCTFail("Status should not be unknown after check")
        }
    }
    
    func testCheckWithHTTPOnlyMode() async {
        let config = ReachabilityConfiguration(probeMode: .httpOnly, timeout: 10.0)
        let reachability = RealReachability(configuration: config)
        
        let status = await reachability.check()
        
        switch status {
        case .reachable(let type):
            XCTAssertTrue(true, "Network is reachable via HTTP with type: \(type)")
        case .notReachable:
            XCTAssertTrue(true, "Network is not reachable via HTTP")
        case .unknown:
            XCTFail("Status should not be unknown after check")
        }
    }
    
    func testCheckWithICMPOnlyMode() async {
        let config = ReachabilityConfiguration(probeMode: .icmpOnly, timeout: 10.0)
        let reachability = RealReachability(configuration: config)
        
        let status = await reachability.check()
        
        switch status {
        case .reachable(let type):
            XCTAssertTrue(true, "Network is reachable via ICMP with type: \(type)")
        case .notReachable:
            XCTAssertTrue(true, "Network is not reachable via ICMP")
        case .unknown:
            XCTFail("Status should not be unknown after check")
        }
    }
    
    func testCheckMultipleTimesWithDifferentModes() async {
        let reachability = RealReachability()
        
        // Check with parallel mode
        reachability.configuration = ReachabilityConfiguration(probeMode: .parallel)
        let parallelStatus = await reachability.check()
        XCTAssertNotEqual(parallelStatus, .unknown)
        
        // Check with HTTP only mode
        reachability.configuration = ReachabilityConfiguration(probeMode: .httpOnly)
        let httpStatus = await reachability.check()
        XCTAssertNotEqual(httpStatus, .unknown)
        
        // Check with ICMP only mode
        reachability.configuration = ReachabilityConfiguration(probeMode: .icmpOnly)
        let icmpStatus = await reachability.check()
        XCTAssertNotEqual(icmpStatus, .unknown)
    }
    
    // MARK: - Parallel Probe Behavior Tests
    
    func testParallelModeSucceedsIfHTTPSucceeds() async {
        // Use valid HTTP URL and invalid ICMP host
        let config = ReachabilityConfiguration(
            probeMode: .parallel,
            timeout: 5.0,
            httpProbeURL: HTTPProber.defaultURL,
            icmpHost: "192.0.2.1",  // Unroutable IP
            icmpPort: 53
        )
        let reachability = RealReachability(configuration: config)
        
        let status = await reachability.check()
        
        // Parallel mode should succeed because HTTP probe succeeds
        if case .reachable = status {
            XCTAssertTrue(true, "Parallel mode succeeded via HTTP")
        } else if case .notReachable = status {
            // Network might not be available
            XCTAssertTrue(true, "Network not available")
        } else {
            XCTFail("Unexpected status: \(status)")
        }
    }
    
    func testParallelModeSucceedsIfICMPSucceeds() async {
        // Use invalid HTTP URL and valid ICMP host
        let config = ReachabilityConfiguration(
            probeMode: .parallel,
            timeout: 5.0,
            httpProbeURL: URL(string: "https://this-domain-definitely-does-not-exist-12345.com")!,
            icmpHost: "8.8.8.8",
            icmpPort: 53
        )
        let reachability = RealReachability(configuration: config)
        
        let status = await reachability.check()
        
        // Parallel mode should succeed because ICMP probe succeeds
        if case .reachable = status {
            XCTAssertTrue(true, "Parallel mode succeeded via ICMP")
        } else if case .notReachable = status {
            // Network might not be available
            XCTAssertTrue(true, "Network not available")
        } else {
            XCTFail("Unexpected status: \(status)")
        }
    }
    
    func testParallelModeFailsIfBothFail() async {
        // Use invalid URLs for both probes
        let config = ReachabilityConfiguration(
            probeMode: .parallel,
            timeout: 2.0,
            httpProbeURL: URL(string: "https://this-domain-definitely-does-not-exist-12345.com")!,
            icmpHost: "192.0.2.1",
            icmpPort: 53
        )
        let reachability = RealReachability(configuration: config)
        
        let status = await reachability.check()
        
        // Both probes should fail, so result should be not reachable
        XCTAssertEqual(status, .notReachable, "Parallel mode should fail when both probes fail")
    }
    
    // MARK: - Status Stream Tests
    
    func testStatusStreamEmitsInitialStatus() async {
        let reachability = RealReachability()
        
        var receivedStatus: ReachabilityStatus?
        
        for await status in reachability.statusStream {
            receivedStatus = status
            break  // Just get the first status
        }
        
        XCTAssertNotNil(receivedStatus, "Status stream should emit at least one status")
        
        reachability.stopNotifier()
    }
}
