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

@interface RRReachability (TestHooks)
- (void)updateStatus:(RRReachabilityStatus)status connectionType:(RRConnectionType)type;
- (void)updateStatus:(RRReachabilityStatus)status connectionType:(RRConnectionType)type secondaryReachable:(BOOL)secondaryReachable;
- (void)performProbeWithCompletion:(void (^)(BOOL reachable))completion;
- (void)performHTTPProbeAllowingCellular:(BOOL)allowCellular completion:(void (^)(BOOL reachable))completion;
@end

@interface RRPathMonitorFake : RRPathMonitor
- (void)triggerPathSatisfied:(BOOL)satisfied connectionType:(RRConnectionType)type;
@end

@implementation RRPathMonitorFake

- (void)startMonitoring {}
- (void)stopMonitoring {}

- (void)triggerPathSatisfied:(BOOL)satisfied connectionType:(RRConnectionType)type {
    if (self.pathUpdateHandler) {
        self.pathUpdateHandler(satisfied, type);
    }
}

@end

@interface RRReachabilityProbeStub : RRReachability
@property (nonatomic, assign) BOOL stubProbeReachable;
@end

@implementation RRReachabilityProbeStub

- (void)performProbeWithCompletion:(void (^)(BOOL reachable))completion {
    if (completion) {
        completion(self.stubProbeReachable);
    }
}

@end

@interface RRReachabilityHTTPProbeCaptureStub : RRReachability
@property (nonatomic, assign) BOOL didPerformHTTPProbe;
@property (nonatomic, assign) BOOL lastAllowsCellular;
@end

@implementation RRReachabilityHTTPProbeCaptureStub

- (void)performHTTPProbeAllowingCellular:(BOOL)allowCellular completion:(void (^)(BOOL reachable))completion {
    self.didPerformHTTPProbe = YES;
    self.lastAllowsCellular = allowCellular;
    if (completion) {
        completion(YES);
    }
}

@end

@implementation RRReachabilityTests

- (void)drainMainQueue {
    XCTestExpectation *drainExpectation = [self expectationWithDescription:@"Drain main queue"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [drainExpectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

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
    NSURL *expectedURL = [NSURL URLWithString:@"https://www.gstatic.com/generate_204"];
    XCTAssertEqualObjects(reachability.httpProbeURL, expectedURL, @"Default HTTP probe URL should be generate_204 endpoint");
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

- (void)testDefaultPeriodicProbeEnabled {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertTrue(reachability.periodicProbeEnabled, @"Periodic probe should be enabled by default");
}

- (void)testDefaultAllowCellularFallbackDisabled {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertFalse(reachability.allowCellularFallback, @"Cellular fallback should be disabled by default");
}

- (void)testDefaultSecondaryReachabilityDisabled {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTAssertFalse(reachability.isSecondaryReachable, @"Secondary reachability should be disabled by default");
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

- (void)testSetPeriodicProbeEnabled {
    RRReachability *reachability = [[RRReachability alloc] init];
    
    reachability.periodicProbeEnabled = NO;
    XCTAssertFalse(reachability.periodicProbeEnabled, @"Should be able to disable periodic probe");
    
    reachability.periodicProbeEnabled = YES;
    XCTAssertTrue(reachability.periodicProbeEnabled, @"Should be able to enable periodic probe");
}

- (void)testSetAllowCellularFallback {
    RRReachability *reachability = [[RRReachability alloc] init];
    
    reachability.allowCellularFallback = YES;
    XCTAssertTrue(reachability.allowCellularFallback, @"Should be able to enable cellular fallback");
    
    reachability.allowCellularFallback = NO;
    XCTAssertFalse(reachability.allowCellularFallback, @"Should be able to disable cellular fallback");
}

- (void)testICMPOnlyWithAllowCellularFallbackReturnsNotReachable {
    RRReachabilityProbeStub *reachability = [[RRReachabilityProbeStub alloc] init];
    RRPathMonitorFake *fakeMonitor = [[RRPathMonitorFake alloc] init];
    
    [reachability setValue:fakeMonitor forKey:@"pathMonitor"];
    [fakeMonitor setValue:@(YES) forKey:@"isSatisfied"];
    [fakeMonitor setValue:@(RRConnectionTypeWiFi) forKey:@"connectionType"];
    
    reachability.stubProbeReachable = YES;
    reachability.probeMode = RRProbeModeICMPOnly;
    reachability.allowCellularFallback = YES;
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Completion should return not reachable for invalid fallback configuration"];
    [reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        XCTAssertEqual(status, RRReachabilityStatusNotReachable, @"Invalid fallback configuration should fail immediately");
        XCTAssertEqual(type, RRConnectionTypeWiFi, @"Connection type should still be reported from current path");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testHTTPOnlyProbeDisablesCellularOnWiFiWhenFallbackDisabled {
    RRReachabilityHTTPProbeCaptureStub *reachability = [[RRReachabilityHTTPProbeCaptureStub alloc] init];
    RRPathMonitorFake *fakeMonitor = [[RRPathMonitorFake alloc] init];
    
    [reachability setValue:fakeMonitor forKey:@"pathMonitor"];
    [fakeMonitor setValue:@(YES) forKey:@"isSatisfied"];
    [fakeMonitor setValue:@(RRConnectionTypeWiFi) forKey:@"connectionType"];
    
    reachability.probeMode = RRProbeModeHTTPOnly;
    reachability.allowCellularFallback = NO;
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP probe should disable cellular on Wi-Fi when fallback is off"];
    [reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        XCTAssertTrue(reachability.didPerformHTTPProbe, @"HTTP probe should run");
        XCTAssertFalse(reachability.lastAllowsCellular, @"Cellular should be disallowed for primary Wi-Fi probe");
        XCTAssertEqual(status, RRReachabilityStatusReachable);
        XCTAssertEqual(type, RRConnectionTypeWiFi);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testHTTPOnlyProbeAllowsCellularOnCellularConnection {
    RRReachabilityHTTPProbeCaptureStub *reachability = [[RRReachabilityHTTPProbeCaptureStub alloc] init];
    RRPathMonitorFake *fakeMonitor = [[RRPathMonitorFake alloc] init];
    
    [reachability setValue:fakeMonitor forKey:@"pathMonitor"];
    [fakeMonitor setValue:@(YES) forKey:@"isSatisfied"];
    [fakeMonitor setValue:@(RRConnectionTypeCellular) forKey:@"connectionType"];
    
    reachability.probeMode = RRProbeModeHTTPOnly;
    reachability.allowCellularFallback = NO;
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP probe should allow cellular on cellular path"];
    [reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        XCTAssertTrue(reachability.didPerformHTTPProbe, @"HTTP probe should run");
        XCTAssertTrue(reachability.lastAllowsCellular, @"Cellular should be allowed on cellular path");
        XCTAssertEqual(status, RRReachabilityStatusReachable);
        XCTAssertEqual(type, RRConnectionTypeCellular);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
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

#pragma mark - RRPingFoundation Tests

- (void)testPingFoundationInitialization {
    RRPingFoundation *ping = [[RRPingFoundation alloc] initWithHostName:@"8.8.8.8"];
    XCTAssertNotNil(ping, @"Ping foundation should initialize");
    XCTAssertEqualObjects(ping.hostName, @"8.8.8.8", @"Host name should be set correctly");
}

- (void)testPingFoundationWithDifferentHosts {
    NSArray *hosts = @[@"8.8.8.8", @"1.1.1.1", @"google.com", @"apple.com"];
    
    for (NSString *host in hosts) {
        RRPingFoundation *ping = [[RRPingFoundation alloc] initWithHostName:host];
        XCTAssertNotNil(ping, @"Ping foundation should initialize for host: %@", host);
        XCTAssertEqualObjects(ping.hostName, host, @"Host name should match");
    }
}

- (void)testPingFoundationIdentifier {
    RRPingFoundation *ping = [[RRPingFoundation alloc] initWithHostName:@"8.8.8.8"];
    XCTAssertTrue(ping.identifier > 0, @"Identifier should be set");
}

- (void)testPingFoundationInitialSequenceNumber {
    RRPingFoundation *ping = [[RRPingFoundation alloc] initWithHostName:@"8.8.8.8"];
    XCTAssertEqual(ping.nextSequenceNumber, 0, @"Initial sequence number should be 0");
}

- (void)testPingFoundationAddressStyleDefault {
    RRPingFoundation *ping = [[RRPingFoundation alloc] initWithHostName:@"8.8.8.8"];
    XCTAssertEqual(ping.addressStyle, RRPingFoundationAddressStyleAny, @"Default address style should be any");
}

- (void)testPingFoundationAddressStyleConfiguration {
    RRPingFoundation *ping = [[RRPingFoundation alloc] initWithHostName:@"8.8.8.8"];
    
    ping.addressStyle = RRPingFoundationAddressStyleICMPv4;
    XCTAssertEqual(ping.addressStyle, RRPingFoundationAddressStyleICMPv4);
    
    ping.addressStyle = RRPingFoundationAddressStyleICMPv6;
    XCTAssertEqual(ping.addressStyle, RRPingFoundationAddressStyleICMPv6);
    
    ping.addressStyle = RRPingFoundationAddressStyleAny;
    XCTAssertEqual(ping.addressStyle, RRPingFoundationAddressStyleAny);
}

- (void)testPingFoundationInitialHostAddress {
    RRPingFoundation *ping = [[RRPingFoundation alloc] initWithHostName:@"8.8.8.8"];
    // Before start, host address should be nil
    XCTAssertNil(ping.hostAddress, @"Host address should be nil before start");
}

- (void)testPingFoundationWithEmptyHost {
    RRPingFoundation *ping = [[RRPingFoundation alloc] initWithHostName:@""];
    XCTAssertNil(ping, @"Ping foundation should not initialize with empty host");
}

#pragma mark - RRPingHelper Tests

- (void)testPingHelperInitialization {
    RRPingHelper *helper = [[RRPingHelper alloc] init];
    XCTAssertNotNil(helper, @"Ping helper should initialize");
}

- (void)testPingHelperDefaultTimeout {
    RRPingHelper *helper = [[RRPingHelper alloc] init];
    XCTAssertEqual(helper.timeout, 2.0, @"Default timeout should be 2.0 seconds");
}

- (void)testPingHelperSetHost {
    RRPingHelper *helper = [[RRPingHelper alloc] init];
    helper.host = @"8.8.8.8";
    XCTAssertEqualObjects(helper.host, @"8.8.8.8", @"Host should be set correctly");
}

- (void)testPingHelperSetTimeout {
    RRPingHelper *helper = [[RRPingHelper alloc] init];
    helper.timeout = 5.0;
    XCTAssertEqual(helper.timeout, 5.0, @"Timeout should be set correctly");
}

- (void)testPingHelperCancel {
    RRPingHelper *helper = [[RRPingHelper alloc] init];
    helper.host = @"8.8.8.8";
    // Cancel should not crash even if not pinging
    [helper cancel];
    // Test passes if no crash
}

#pragma mark - Notification Tests

- (void)testNotificationNameDefined {
    XCTAssertNotNil(kRRReachabilityChangedNotification, @"Notification name should be defined");
    XCTAssertEqualObjects(kRRReachabilityChangedNotification, @"kRRReachabilityChangedNotification");
}

- (void)testNotificationKeysDefined {
    XCTAssertNotNil(kRRReachabilityStatusKey, @"Status key should be defined");
    XCTAssertNotNil(kRRConnectionTypeKey, @"Connection type key should be defined");
    XCTAssertNotNil(kRRSecondaryReachableKey, @"Secondary reachability key should be defined");
    XCTAssertEqualObjects(kRRReachabilityStatusKey, @"kRRReachabilityStatusKey");
    XCTAssertEqualObjects(kRRConnectionTypeKey, @"kRRConnectionTypeKey");
    XCTAssertEqualObjects(kRRSecondaryReachableKey, @"kRRSecondaryReachableKey");
}

- (void)testNotificationPostedWhenStatusChanges {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Notification should be posted when status changes"];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kRRReachabilityChangedNotification
                                                                    object:reachability
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *notification) {
        [expectation fulfill];
    }];
    
    [reachability updateStatus:RRReachabilityStatusReachable connectionType:RRConnectionTypeWiFi];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testNotificationPostedWhenConnectionTypeChangesButStatusSame {
    RRReachability *reachability = [[RRReachability alloc] init];
    
    [reachability updateStatus:RRReachabilityStatusReachable connectionType:RRConnectionTypeWiFi];
    [self drainMainQueue];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Notification should be posted when connection type changes"];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kRRReachabilityChangedNotification
                                                                    object:reachability
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *notification) {
        [expectation fulfill];
    }];
    
    [reachability updateStatus:RRReachabilityStatusReachable connectionType:RRConnectionTypeCellular];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testNotificationNotPostedWhenStatusAndConnectionTypeUnchanged {
    RRReachability *reachability = [[RRReachability alloc] init];
    
    [reachability updateStatus:RRReachabilityStatusReachable connectionType:RRConnectionTypeWiFi];
    [self drainMainQueue];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Notification should not be posted when state is unchanged"];
    expectation.inverted = YES;
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kRRReachabilityChangedNotification
                                                                    object:reachability
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *notification) {
        [expectation fulfill];
    }];
    
    [reachability updateStatus:RRReachabilityStatusReachable connectionType:RRConnectionTypeWiFi];
    
    [self waitForExpectationsWithTimeout:0.3 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testNotificationPostedWhenSecondaryReachabilityChanges {
    RRReachability *reachability = [[RRReachability alloc] init];
    
    [reachability updateStatus:RRReachabilityStatusReachable connectionType:RRConnectionTypeWiFi secondaryReachable:NO];
    [self drainMainQueue];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Notification should be posted when secondary reachability changes"];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kRRReachabilityChangedNotification
                                                                    object:reachability
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *notification) {
        NSNumber *secondary = notification.userInfo[kRRSecondaryReachableKey];
        XCTAssertTrue(secondary.boolValue);
        [expectation fulfill];
    }];
    
    [reachability updateStatus:RRReachabilityStatusReachable connectionType:RRConnectionTypeWiFi secondaryReachable:YES];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testNotificationUserInfoContainsLatestStatusConnectionTypeAndSecondaryReachability {
    RRReachability *reachability = [[RRReachability alloc] init];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Notification userInfo should contain latest status, connection type, and secondary reachability"];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kRRReachabilityChangedNotification
                                                                    object:reachability
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *notification) {
        NSNumber *status = notification.userInfo[kRRReachabilityStatusKey];
        NSNumber *type = notification.userInfo[kRRConnectionTypeKey];
        NSNumber *secondary = notification.userInfo[kRRSecondaryReachableKey];
        
        XCTAssertEqual(status.integerValue, RRReachabilityStatusNotReachable);
        XCTAssertEqual(type.integerValue, RRConnectionTypeNone);
        XCTAssertFalse(secondary.boolValue);
        [expectation fulfill];
    }];
    
    [reachability updateStatus:RRReachabilityStatusNotReachable connectionType:RRConnectionTypeNone];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testNotificationPostedWhenConnectionTypeChangesViaPathHandler {
    RRReachabilityProbeStub *reachability = [[RRReachabilityProbeStub alloc] init];
    RRPathMonitorFake *fakeMonitor = [[RRPathMonitorFake alloc] init];
    reachability.stubProbeReachable = YES;
    reachability.periodicProbeEnabled = NO;
    [reachability setValue:fakeMonitor forKey:@"pathMonitor"];
    
    [reachability startNotifier];
    
    XCTestExpectation *initialExpectation = [self expectationWithDescription:@"Initial reachable notification should be posted"];
    id initialObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kRRReachabilityChangedNotification
                                                                            object:reachability
                                                                             queue:[NSOperationQueue mainQueue]
                                                                        usingBlock:^(NSNotification *notification) {
        [initialExpectation fulfill];
    }];
    
    [fakeMonitor triggerPathSatisfied:YES connectionType:RRConnectionTypeWiFi];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:initialObserver];
    
    XCTestExpectation *switchExpectation = [self expectationWithDescription:@"Connection type switch should post notification"];
    __block RRConnectionType notifiedType = RRConnectionTypeNone;
    id switchObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kRRReachabilityChangedNotification
                                                                           object:reachability
                                                                            queue:[NSOperationQueue mainQueue]
                                                                       usingBlock:^(NSNotification *notification) {
        notifiedType = [notification.userInfo[kRRConnectionTypeKey] integerValue];
        [switchExpectation fulfill];
    }];
    
    [fakeMonitor triggerPathSatisfied:YES connectionType:RRConnectionTypeCellular];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertEqual(notifiedType, RRConnectionTypeCellular);
    
    [[NSNotificationCenter defaultCenter] removeObserver:switchObserver];
    [reachability stopNotifier];
}

@end
