//
//  RealReachability2Tests.swift
//  RealReachability2
//
//  Created by RealReachability2 on 2026.
//

import XCTest
@testable import RealReachability2

@available(iOS 13.0, *)
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
    
    // MARK: - ProbeMode Tests
    
    func testProbeModeValues() {
        let parallel = ProbeMode.parallel
        let httpOnly = ProbeMode.httpOnly
        let icmpOnly = ProbeMode.icmpOnly
        
        XCTAssertNotNil(parallel)
        XCTAssertNotNil(httpOnly)
        XCTAssertNotNil(icmpOnly)
    }
}
