//
//  RRReachabilityTests.m
//  RealReachability2ObjCTests
//
//  Comprehensive tests for the Objective-C RealReachability2 implementation
//

#import <XCTest/XCTest.h>
#import "RealReachability2ObjC.h"

@interface RRReachabilityTests : XCTestCase

@end

@implementation RRReachabilityTests

#pragma mark - Singleton Tests

- (void)testSharedInstanceReturnsNonNil {
    RRReachability *instance = [RRReachability sharedInstance];
    XCTAssertNotNil(instance, @"Shared instance should not be nil");
}

- (void)testSharedInstanceReturnsSameObject {
    RRReachability *instance1 = [RRReachability sharedInstance];
    RRReachability *instance2 = [RRReachability sharedInstance];
    XCTAssertEqual(instance1, instance2, @"Shared instance should always return the same object");
}

#pragma mark - Default Configuration Tests

- (void)testDefaultProbeMode {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertEqual(reachability.probeMode, RRProbeModeParallel, @"Default probe mode should be parallel");
}

- (void)testDefaultTimeout {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertEqual(reachability.timeout, 5.0, @"Default timeout should be 5.0 seconds");
}

- (void)testDefaultHTTPProbeURL {
    RRReachability *reachability = [[RRReachability alloc] init];
    NSURL *expectedURL = [NSURL URLWithString:@"https://captive.apple.com/hotspot-detect.html"];
    XCTAssertEqualObjects(reachability.httpProbeURL, expectedURL, @"Default HTTP probe URL should be Apple's captive portal");
}

- (void)testDefaultICMPHost {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertEqualObjects(reachability.icmpHost, @"8.8.8.8", @"Default ICMP host should be Google DNS");
}

- (void)testDefaultICMPPort {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertEqual(reachability.icmpPort, 53, @"Default ICMP port should be 53");
}

- (void)testDefaultStatus {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertEqual(reachability.currentStatus, RRReachabilityStatusUnknown, @"Initial status should be unknown");
}

- (void)testDefaultConnectionType {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertEqual(reachability.connectionType, RRConnectionTypeNone, @"Initial connection type should be none");
}

#pragma mark - Probe Mode Configuration Tests

- (void)testSetProbeModeParallel {
    RRReachability *reachability = [[RRReachability alloc] init];
    reachability.probeMode = RRProbeModeParallel;
    XCTAssertEqual(reachability.probeMode, RRProbeModeParallel, @"Should be able to set parallel mode");
}

- (void)testSetProbeModeHTTPOnly {
    RRReachability *reachability = [[RRReachability alloc] init];
    reachability.probeMode = RRProbeModeHTTPOnly;
    XCTAssertEqual(reachability.probeMode, RRProbeModeHTTPOnly, @"Should be able to set HTTP only mode");
}

- (void)testSetProbeModeICMPOnly {
    RRReachability *reachability = [[RRReachability alloc] init];
    reachability.probeMode = RRProbeModeICMPOnly;
    XCTAssertEqual(reachability.probeMode, RRProbeModeICMPOnly, @"Should be able to set ICMP only mode");
}

- (void)testSwitchBetweenProbeModes {
    RRReachability *reachability = [[RRReachability alloc] init];
    
    // Start with parallel
    XCTAssertEqual(reachability.probeMode, RRProbeModeParallel);
    
    // Switch to HTTP only
    reachability.probeMode = RRProbeModeHTTPOnly;
    XCTAssertEqual(reachability.probeMode, RRProbeModeHTTPOnly);
    
    // Switch to ICMP only
    reachability.probeMode = RRProbeModeICMPOnly;
    XCTAssertEqual(reachability.probeMode, RRProbeModeICMPOnly);
    
    // Switch back to parallel
    reachability.probeMode = RRProbeModeParallel;
    XCTAssertEqual(reachability.probeMode, RRProbeModeParallel);
}

#pragma mark - Custom Configuration Tests

- (void)testSetCustomTimeout {
    RRReachability *reachability = [[RRReachability alloc] init];
    reachability.timeout = 10.0;
    XCTAssertEqual(reachability.timeout, 10.0, @"Should be able to set custom timeout");
}

- (void)testSetCustomHTTPProbeURL {
    RRReachability *reachability = [[RRReachability alloc] init];
    NSURL *customURL = [NSURL URLWithString:@"https://www.example.com/check"];
    reachability.httpProbeURL = customURL;
    XCTAssertEqualObjects(reachability.httpProbeURL, customURL, @"Should be able to set custom HTTP probe URL");
}

- (void)testSetCustomICMPHost {
    RRReachability *reachability = [[RRReachability alloc] init];
    reachability.icmpHost = @"1.1.1.1";
    XCTAssertEqualObjects(reachability.icmpHost, @"1.1.1.1", @"Should be able to set custom ICMP host");
}

- (void)testSetCustomICMPPort {
    RRReachability *reachability = [[RRReachability alloc] init];
    reachability.icmpPort = 443;
    XCTAssertEqual(reachability.icmpPort, 443, @"Should be able to set custom ICMP port");
}

- (void)testSetAllCustomConfiguration {
    RRReachability *reachability = [[RRReachability alloc] init];
    
    reachability.probeMode = RRProbeModeHTTPOnly;
    reachability.timeout = 15.0;
    reachability.httpProbeURL = [NSURL URLWithString:@"https://www.google.com"];
    reachability.icmpHost = @"1.1.1.1";
    reachability.icmpPort = 80;
    
    XCTAssertEqual(reachability.probeMode, RRProbeModeHTTPOnly);
    XCTAssertEqual(reachability.timeout, 15.0);
    XCTAssertEqualObjects(reachability.httpProbeURL.absoluteString, @"https://www.google.com");
    XCTAssertEqualObjects(reachability.icmpHost, @"1.1.1.1");
    XCTAssertEqual(reachability.icmpPort, 80);
}

#pragma mark - Notifier Lifecycle Tests

- (void)testNotifierNotRunningInitially {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertFalse(reachability.isNotifierRunning, @"Notifier should not be running initially");
}

- (void)testStartNotifier {
    RRReachability *reachability = [[RRReachability alloc] init];
    [reachability startNotifier];
    XCTAssertTrue(reachability.isNotifierRunning, @"Notifier should be running after start");
    [reachability stopNotifier];
}

- (void)testStopNotifier {
    RRReachability *reachability = [[RRReachability alloc] init];
    [reachability startNotifier];
    [reachability stopNotifier];
    XCTAssertFalse(reachability.isNotifierRunning, @"Notifier should not be running after stop");
}

- (void)testStartNotifierIdempotent {
    RRReachability *reachability = [[RRReachability alloc] init];
    [reachability startNotifier];
    [reachability startNotifier];  // Call again
    XCTAssertTrue(reachability.isNotifierRunning, @"Multiple start calls should not cause issues");
    [reachability stopNotifier];
}

- (void)testStopNotifierIdempotent {
    RRReachability *reachability = [[RRReachability alloc] init];
    [reachability startNotifier];
    [reachability stopNotifier];
    [reachability stopNotifier];  // Call again
    XCTAssertFalse(reachability.isNotifierRunning, @"Multiple stop calls should not cause issues");
}

- (void)testMultipleStartStopCycles {
    RRReachability *reachability = [[RRReachability alloc] init];
    
    for (int i = 0; i < 3; i++) {
        [reachability startNotifier];
        XCTAssertTrue(reachability.isNotifierRunning);
        [reachability stopNotifier];
        XCTAssertFalse(reachability.isNotifierRunning);
    }
}

#pragma mark - RRPathMonitor Tests

- (void)testPathMonitorSharedInstance {
    RRPathMonitor *instance1 = [RRPathMonitor sharedInstance];
    RRPathMonitor *instance2 = [RRPathMonitor sharedInstance];
    XCTAssertEqual(instance1, instance2, @"Path monitor shared instance should return same object");
}

- (void)testPathMonitorInitialState {
    RRPathMonitor *monitor = [[RRPathMonitor alloc] init];
    XCTAssertEqual(monitor.connectionType, RRConnectionTypeNone, @"Initial connection type should be none");
}

- (void)testPathMonitorStartStopMonitoring {
    RRPathMonitor *monitor = [[RRPathMonitor alloc] init];
    [monitor startMonitoring];
    [monitor stopMonitoring];
    // Test passes if no crash
}

- (void)testPathMonitorMultipleStartStopCycles {
    RRPathMonitor *monitor = [[RRPathMonitor alloc] init];
    
    for (int i = 0; i < 3; i++) {
        [monitor startMonitoring];
        [monitor stopMonitoring];
    }
    // Test passes if no crash
}

#pragma mark - RRConnectionType Tests

- (void)testConnectionTypeValues {
    XCTAssertEqual(RRConnectionTypeWiFi, 0);
    XCTAssertEqual(RRConnectionTypeCellular, 1);
    XCTAssertEqual(RRConnectionTypeWired, 2);
    XCTAssertEqual(RRConnectionTypeOther, 3);
    XCTAssertEqual(RRConnectionTypeNone, 4);
}

#pragma mark - RRReachabilityStatus Tests

- (void)testReachabilityStatusValues {
    XCTAssertEqual(RRReachabilityStatusUnknown, 0);
    XCTAssertEqual(RRReachabilityStatusNotReachable, 1);
    XCTAssertEqual(RRReachabilityStatusReachable, 2);
}

#pragma mark - RRProbeMode Tests

- (void)testProbeModeValues {
    XCTAssertEqual(RRProbeModeParallel, 0);
    XCTAssertEqual(RRProbeModeHTTPOnly, 1);
    XCTAssertEqual(RRProbeModeICMPOnly, 2);
}

#pragma mark - Notification Tests

- (void)testNotificationNameDefined {
    XCTAssertNotNil(kRRReachabilityChangedNotification, @"Notification name should be defined");
    XCTAssertEqualObjects(kRRReachabilityChangedNotification, @"kRRReachabilityChangedNotification");
}

- (void)testNotificationKeysDefined {
    XCTAssertNotNil(kRRReachabilityStatusKey, @"Status key should be defined");
    XCTAssertNotNil(kRRConnectionTypeKey, @"Connection type key should be defined");
    XCTAssertEqualObjects(kRRReachabilityStatusKey, @"kRRReachabilityStatusKey");
    XCTAssertEqualObjects(kRRConnectionTypeKey, @"kRRConnectionTypeKey");
}

@end
