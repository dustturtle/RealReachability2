//
//  RealReachability2Tests.swift
//  RealReachability2
//
//  Created by RealReachability2 on 2026.
//

import XCTest
@testable import RealReachability2

@available(iOS 13.0, macOS 10.15, *)
final class RealReachability2Tests: XCTestCase {
    
    // MARK: - ReachabilityStatus Tests
    
    func testReachabilityStatusEquatable() {
        XCTAssertEqual(ReachabilityStatus.unknown, ReachabilityStatus.unknown)
        XCTAssertEqual(ReachabilityStatus.notReachable, ReachabilityStatus.notReachable)
        XCTAssertEqual(ReachabilityStatus.reachable(.wifi), ReachabilityStatus.reachable(.wifi))
        XCTAssertNotEqual(ReachabilityStatus.reachable(.wifi), ReachabilityStatus.reachable(.cellular))
        XCTAssertNotEqual(ReachabilityStatus.reachable(.wifi), ReachabilityStatus.notReachable)
    }
    
    func testReachabilityStatusIsReachable() {
        XCTAssertTrue(ReachabilityStatus.reachable(.wifi).isReachable)
        XCTAssertTrue(ReachabilityStatus.reachable(.cellular).isReachable)
        XCTAssertTrue(ReachabilityStatus.reachable(.wired).isReachable)
        XCTAssertTrue(ReachabilityStatus.reachable(.other).isReachable)
        XCTAssertFalse(ReachabilityStatus.notReachable.isReachable)
        XCTAssertFalse(ReachabilityStatus.unknown.isReachable)
    }
    
    // MARK: - ConnectionType Tests
    
    func testConnectionTypeEquatable() {
        XCTAssertEqual(ConnectionType.wifi, ConnectionType.wifi)
        XCTAssertEqual(ConnectionType.cellular, ConnectionType.cellular)
        XCTAssertNotEqual(ConnectionType.wifi, ConnectionType.cellular)
    }
    
    func testAllConnectionTypes() {
        // Test all connection types exist and are distinct
        let wifi = ConnectionType.wifi
        let cellular = ConnectionType.cellular
        let wired = ConnectionType.wired
        let other = ConnectionType.other
        
        XCTAssertNotEqual(wifi, cellular)
        XCTAssertNotEqual(wifi, wired)
        XCTAssertNotEqual(wifi, other)
        XCTAssertNotEqual(cellular, wired)
        XCTAssertNotEqual(cellular, other)
        XCTAssertNotEqual(wired, other)
    }
    
    // MARK: - Configuration Tests
    
    func testDefaultConfiguration() {
        let config = ReachabilityConfiguration.default
        XCTAssertEqual(config.probeMode, .parallel)
        XCTAssertEqual(config.timeout, 5.0)
        XCTAssertEqual(config.httpProbeURL, HTTPProber.defaultURL)
        XCTAssertEqual(config.icmpHost, ICMPPinger.defaultHost)
        XCTAssertEqual(config.icmpPort, ICMPPinger.defaultPort)
    }
    
    func testCustomConfiguration() {
        let customURL = URL(string: "https://example.com")!
        let config = ReachabilityConfiguration(
            probeMode: .httpOnly,
            timeout: 10.0,
            httpProbeURL: customURL,
            icmpHost: "1.1.1.1",
            icmpPort: 80
        )
        
        XCTAssertEqual(config.probeMode, .httpOnly)
        XCTAssertEqual(config.timeout, 10.0)
        XCTAssertEqual(config.httpProbeURL, customURL)
        XCTAssertEqual(config.icmpHost, "1.1.1.1")
        XCTAssertEqual(config.icmpPort, 80)
    }
    
    func testConfigurationWithParallelMode() {
        let config = ReachabilityConfiguration(probeMode: .parallel)
        XCTAssertEqual(config.probeMode, .parallel)
        // Parallel mode should use default URLs and hosts
        XCTAssertEqual(config.httpProbeURL, HTTPProber.defaultURL)
        XCTAssertEqual(config.icmpHost, ICMPPinger.defaultHost)
    }
    
    func testConfigurationWithHTTPOnlyMode() {
        let config = ReachabilityConfiguration(probeMode: .httpOnly)
        XCTAssertEqual(config.probeMode, .httpOnly)
    }
    
    func testConfigurationWithICMPOnlyMode() {
        let config = ReachabilityConfiguration(probeMode: .icmpOnly)
        XCTAssertEqual(config.probeMode, .icmpOnly)
    }
    
    func testConfigurationWithCustomTimeout() {
        let config = ReachabilityConfiguration(timeout: 15.0)
        XCTAssertEqual(config.timeout, 15.0)
    }
    
    func testConfigurationWithMinimalTimeout() {
        let config = ReachabilityConfiguration(timeout: 0.5)
        XCTAssertEqual(config.timeout, 0.5)
    }
    
    // MARK: - HTTPProber Tests
    
    func testHTTPProberDefaultURL() {
        XCTAssertEqual(
            HTTPProber.defaultURL.absoluteString,
            "https://captive.apple.com/hotspot-detect.html"
        )
    }
    
    func testHTTPProberInitialization() {
        let prober = HTTPProber()
        XCTAssertNotNil(prober)
    }
    
    func testHTTPProberCustomInitialization() {
        let customURL = URL(string: "https://example.com")!
        let prober = HTTPProber(url: customURL, timeout: 10.0)
        XCTAssertNotNil(prober)
    }
    
    func testHTTPProberWithDifferentURLs() {
        let urls = [
            URL(string: "https://www.google.com")!,
            URL(string: "https://www.apple.com")!,
            URL(string: "https://www.cloudflare.com")!
        ]
        
        for url in urls {
            let prober = HTTPProber(url: url, timeout: 5.0)
            XCTAssertNotNil(prober)
        }
    }
    
    // MARK: - ICMPPinger Tests
    
    func testICMPPingerDefaults() {
        XCTAssertEqual(ICMPPinger.defaultHost, "8.8.8.8")
        XCTAssertEqual(ICMPPinger.defaultPort, 53)
    }
    
    func testICMPPingerInitialization() {
        let pinger = ICMPPinger()
        XCTAssertNotNil(pinger)
    }
    
    func testICMPPingerCustomInitialization() {
        let pinger = ICMPPinger(host: "1.1.1.1", port: 80, timeout: 10.0)
        XCTAssertNotNil(pinger)
    }
    
    func testICMPPingerWithDifferentHosts() {
        let hosts = ["8.8.8.8", "1.1.1.1", "8.8.4.4", "208.67.222.222"]
        
        for host in hosts {
            let pinger = ICMPPinger(host: host, port: 53, timeout: 5.0)
            XCTAssertNotNil(pinger)
        }
    }
    
    func testICMPPingerWithDifferentPorts() {
        let ports: [UInt16] = [53, 80, 443]
        
        for port in ports {
            let pinger = ICMPPinger(host: "8.8.8.8", port: port, timeout: 5.0)
            XCTAssertNotNil(pinger)
        }
    }
    
    // MARK: - RealReachability Tests
    
    func testSharedInstance() {
        let instance1 = RealReachability.shared
        let instance2 = RealReachability.shared
        XCTAssertTrue(instance1 === instance2)
    }
    
    func testRealReachabilityInitialization() {
        let reachability = RealReachability()
        XCTAssertNotNil(reachability)
    }
    
    func testRealReachabilityCustomConfiguration() {
        let config = ReachabilityConfiguration(probeMode: .icmpOnly, timeout: 3.0)
        let reachability = RealReachability(configuration: config)
        XCTAssertEqual(reachability.configuration.probeMode, .icmpOnly)
        XCTAssertEqual(reachability.configuration.timeout, 3.0)
    }
    
    func testConfigurationUpdate() {
        let reachability = RealReachability()
        XCTAssertEqual(reachability.configuration.probeMode, .parallel)
        
        reachability.configuration = ReachabilityConfiguration(probeMode: .httpOnly)
        XCTAssertEqual(reachability.configuration.probeMode, .httpOnly)
    }
    
    func testRealReachabilityWithParallelMode() {
        let config = ReachabilityConfiguration(probeMode: .parallel)
        let reachability = RealReachability(configuration: config)
        XCTAssertEqual(reachability.configuration.probeMode, .parallel)
    }
    
    func testRealReachabilityWithHTTPOnlyMode() {
        let config = ReachabilityConfiguration(probeMode: .httpOnly)
        let reachability = RealReachability(configuration: config)
        XCTAssertEqual(reachability.configuration.probeMode, .httpOnly)
    }
    
    func testRealReachabilityWithICMPOnlyMode() {
        let config = ReachabilityConfiguration(probeMode: .icmpOnly)
        let reachability = RealReachability(configuration: config)
        XCTAssertEqual(reachability.configuration.probeMode, .icmpOnly)
    }
    
    // MARK: - ProbeMode Tests
    
    func testProbeModeValues() {
        let parallel = ProbeMode.parallel
        let httpOnly = ProbeMode.httpOnly
        let icmpOnly = ProbeMode.icmpOnly
        
        XCTAssertNotNil(parallel)
        XCTAssertNotNil(httpOnly)
        XCTAssertNotNil(icmpOnly)
    }
    
    func testProbeModeDistinct() {
        // Ensure all probe modes are distinct
        let modes: [ProbeMode] = [.parallel, .httpOnly, .icmpOnly]
        for i in 0..<modes.count {
            for j in (i+1)..<modes.count {
                XCTAssertTrue(String(describing: modes[i]) != String(describing: modes[j]))
            }
        }
    }
    
    // MARK: - ProbeResult Tests
    
    func testProbeResultSuccess() {
        let result = ProbeResult(success: true, latencyMs: 50.0, error: nil)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.latencyMs, 50.0)
        XCTAssertNil(result.error)
    }
    
    func testProbeResultFailure() {
        let error = NSError(domain: "test", code: -1, userInfo: nil)
        let result = ProbeResult(success: false, latencyMs: 100.0, error: error)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.latencyMs, 100.0)
        XCTAssertNotNil(result.error)
    }
    
    func testProbeResultWithNoLatency() {
        let result = ProbeResult(success: true, latencyMs: nil, error: nil)
        XCTAssertTrue(result.success)
        XCTAssertNil(result.latencyMs)
    }
    
    // MARK: - Notifier Lifecycle Tests
    
    func testStartAndStopNotifier() {
        let reachability = RealReachability()
        
        // Start notifier
        reachability.startNotifier()
        
        // Should be able to start again (idempotent)
        reachability.startNotifier()
        
        // Stop notifier
        reachability.stopNotifier()
        
        // Should be able to stop again (idempotent)
        reachability.stopNotifier()
    }
    
    func testMultipleStartStopCycles() {
        let reachability = RealReachability()
        
        for _ in 0..<3 {
            reachability.startNotifier()
            reachability.stopNotifier()
        }
        // Test passes if no crash occurs
    }
    
    // MARK: - Configuration Mode Switching Tests
    
    func testSwitchingBetweenProbeModes() {
        let reachability = RealReachability()
        
        // Start with parallel
        XCTAssertEqual(reachability.configuration.probeMode, .parallel)
        
        // Switch to HTTP only
        reachability.configuration = ReachabilityConfiguration(probeMode: .httpOnly)
        XCTAssertEqual(reachability.configuration.probeMode, .httpOnly)
        
        // Switch to ICMP only
        reachability.configuration = ReachabilityConfiguration(probeMode: .icmpOnly)
        XCTAssertEqual(reachability.configuration.probeMode, .icmpOnly)
        
        // Switch back to parallel
        reachability.configuration = ReachabilityConfiguration(probeMode: .parallel)
        XCTAssertEqual(reachability.configuration.probeMode, .parallel)
    }
    
    func testConfigurationUpdateWithCustomValues() {
        let reachability = RealReachability()
        
        let customURL = URL(string: "https://www.example.com/check")!
        let config = ReachabilityConfiguration(
            probeMode: .httpOnly,
            timeout: 8.0,
            httpProbeURL: customURL,
            icmpHost: "1.1.1.1",
            icmpPort: 443
        )
        
        reachability.configuration = config
        
        XCTAssertEqual(reachability.configuration.probeMode, .httpOnly)
        XCTAssertEqual(reachability.configuration.timeout, 8.0)
        XCTAssertEqual(reachability.configuration.httpProbeURL, customURL)
        XCTAssertEqual(reachability.configuration.icmpHost, "1.1.1.1")
        XCTAssertEqual(reachability.configuration.icmpPort, 443)
    }
}
