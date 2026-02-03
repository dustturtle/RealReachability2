//
//  RRReachabilityIntegrationTests.m
//  RealReachability2ObjCTests
//
//  Integration tests for the Objective-C RealReachability2 implementation
//  These tests require network connectivity
//

#import <XCTest/XCTest.h>
#import "RealReachability2ObjC.h"

@interface RRReachabilityIntegrationTests : XCTestCase

@property (nonatomic, strong) RRReachability *reachability;

@end

@implementation RRReachabilityIntegrationTests

- (void)setUp {
    [super setUp];
    self.reachability = [[RRReachability alloc] init];
}

- (void)tearDown {
    [self.reachability stopNotifier];
    self.reachability = nil;
    [super tearDown];
}

#pragma mark - Check Reachability with Different Probe Modes

- (void)testCheckReachabilityWithParallelMode {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Parallel mode check"];
    
    self.reachability.probeMode = RRProbeModeParallel;
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        // Status should not be unknown after check
        XCTAssertNotEqual(status, RRReachabilityStatusUnknown, @"Status should not be unknown after check");
        
        if (status == RRReachabilityStatusReachable) {
            NSLog(@"Parallel mode: Network reachable with connection type: %ld", (long)type);
            XCTAssertTrue(type != RRConnectionTypeNone, @"Connection type should be set when reachable");
        } else {
            NSLog(@"Parallel mode: Network not reachable");
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testCheckReachabilityWithHTTPOnlyMode {
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP only mode check"];
    
    self.reachability.probeMode = RRProbeModeHTTPOnly;
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        XCTAssertNotEqual(status, RRReachabilityStatusUnknown, @"Status should not be unknown after check");
        
        if (status == RRReachabilityStatusReachable) {
            NSLog(@"HTTP only mode: Network reachable with connection type: %ld", (long)type);
        } else {
            NSLog(@"HTTP only mode: Network not reachable");
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testCheckReachabilityWithICMPOnlyMode {
    XCTestExpectation *expectation = [self expectationWithDescription:@"ICMP only mode check"];
    
    self.reachability.probeMode = RRProbeModeICMPOnly;
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        XCTAssertNotEqual(status, RRReachabilityStatusUnknown, @"Status should not be unknown after check");
        
        if (status == RRReachabilityStatusReachable) {
            NSLog(@"ICMP only mode: Network reachable with connection type: %ld", (long)type);
        } else {
            NSLog(@"ICMP only mode: Network not reachable");
        }
        
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

#pragma mark - Multiple Checks with Different Modes

- (void)testMultipleChecksWithDifferentModes {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Multiple mode checks"];
    
    __block int checksCompleted = 0;
    
    // Check with parallel mode
    self.reachability.probeMode = RRProbeModeParallel;
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        NSLog(@"Parallel check completed: status=%ld, type=%ld", (long)status, (long)type);
        checksCompleted++;
        
        if (checksCompleted == 3) {
            [expectation fulfill];
        }
    }];
    
    // Check with HTTP only mode
    self.reachability.probeMode = RRProbeModeHTTPOnly;
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        NSLog(@"HTTP check completed: status=%ld, type=%ld", (long)status, (long)type);
        checksCompleted++;
        
        if (checksCompleted == 3) {
            [expectation fulfill];
        }
    }];
    
    // Check with ICMP only mode
    self.reachability.probeMode = RRProbeModeICMPOnly;
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        NSLog(@"ICMP check completed: status=%ld, type=%ld", (long)status, (long)type);
        checksCompleted++;
        
        if (checksCompleted == 3) {
            [expectation fulfill];
        }
    }];
    
    [self waitForExpectationsWithTimeout:30.0 handler:nil];
}

#pragma mark - Parallel Mode Behavior Tests

- (void)testParallelModeSucceedsWithValidHTTPAndInvalidICMP {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Parallel with valid HTTP"];
    
    self.reachability.probeMode = RRProbeModeParallel;
    // Use invalid ICMP host but valid HTTP URL
    self.reachability.icmpHost = @"192.0.2.1";  // Unroutable IP
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        // Should succeed if HTTP probe succeeds
        if (status == RRReachabilityStatusReachable) {
            NSLog(@"Parallel mode succeeded via HTTP");
        } else {
            // Network might not be available
            NSLog(@"Network not available for HTTP probe");
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testParallelModeSucceedsWithInvalidHTTPAndValidICMP {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Parallel with valid ICMP"];
    
    self.reachability.probeMode = RRProbeModeParallel;
    // Use invalid HTTP URL but valid ICMP host
    self.reachability.httpProbeURL = [NSURL URLWithString:@"https://this-domain-definitely-does-not-exist-12345.com"];
    self.reachability.icmpHost = @"8.8.8.8";
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        // Should succeed if ICMP probe succeeds
        if (status == RRReachabilityStatusReachable) {
            NSLog(@"Parallel mode succeeded via ICMP");
        } else {
            // Network might not be available
            NSLog(@"Network not available for ICMP probe");
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testParallelModeFailsWithBothInvalid {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Parallel with both invalid"];
    
    self.reachability.probeMode = RRProbeModeParallel;
    self.reachability.timeout = 3.0;
    // Use invalid URLs for both probes
    self.reachability.httpProbeURL = [NSURL URLWithString:@"https://this-domain-definitely-does-not-exist-12345.com"];
    self.reachability.icmpHost = @"192.0.2.1";  // Unroutable IP
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        XCTAssertEqual(status, RRReachabilityStatusNotReachable, @"Should fail when both probes fail");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

#pragma mark - HTTP Only Mode Tests

- (void)testHTTPOnlyModeWithValidURL {
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP with valid URL"];
    
    self.reachability.probeMode = RRProbeModeHTTPOnly;
    self.reachability.httpProbeURL = [NSURL URLWithString:@"https://www.google.com"];
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        if (status == RRReachabilityStatusReachable) {
            NSLog(@"HTTP probe to Google succeeded");
        } else {
            NSLog(@"Network not available");
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testHTTPOnlyModeWithInvalidURL {
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP with invalid URL"];
    
    self.reachability.probeMode = RRProbeModeHTTPOnly;
    self.reachability.timeout = 3.0;
    self.reachability.httpProbeURL = [NSURL URLWithString:@"https://this-domain-definitely-does-not-exist-12345.com"];
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        XCTAssertEqual(status, RRReachabilityStatusNotReachable, @"Should fail with invalid URL");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

#pragma mark - ICMP Only Mode Tests

- (void)testICMPOnlyModeWithValidHost {
    XCTestExpectation *expectation = [self expectationWithDescription:@"ICMP with valid host"];
    
    self.reachability.probeMode = RRProbeModeICMPOnly;
    self.reachability.icmpHost = @"8.8.8.8";
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        if (status == RRReachabilityStatusReachable) {
            NSLog(@"ICMP probe to Google DNS succeeded");
        } else {
            NSLog(@"Network not available");
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testICMPOnlyModeWithInvalidHost {
    XCTestExpectation *expectation = [self expectationWithDescription:@"ICMP with invalid host"];
    
    self.reachability.probeMode = RRProbeModeICMPOnly;
    self.reachability.timeout = 3.0;
    self.reachability.icmpHost = @"192.0.2.1";  // Unroutable IP
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        XCTAssertEqual(status, RRReachabilityStatusNotReachable, @"Should fail with unroutable IP");
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

#pragma mark - Notification Tests

- (void)testNotificationPostedOnReachabilityChange {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Notification received"];
    
    __block BOOL notificationReceived = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:kRRReachabilityChangedNotification
                                                                    object:nil
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *notification) {
        notificationReceived = YES;
        
        // Verify notification contains expected keys
        XCTAssertNotNil(notification.userInfo[kRRReachabilityStatusKey]);
        XCTAssertNotNil(notification.userInfo[kRRConnectionTypeKey]);
        
        [expectation fulfill];
    }];
    
    [self.reachability startNotifier];
    
    [self waitForExpectationsWithTimeout:15.0 handler:^(NSError *error) {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }];
}

#pragma mark - Timeout Tests

- (void)testShortTimeout {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Short timeout"];
    
    self.reachability.probeMode = RRProbeModeHTTPOnly;
    self.reachability.timeout = 0.001;  // Very short timeout
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        // Test passes if no crash, status can be either reachable or not
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

- (void)testLongTimeout {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Long timeout"];
    
    self.reachability.probeMode = RRProbeModeHTTPOnly;
    self.reachability.timeout = 30.0;  // Long timeout
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        // Should complete within timeout
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:35.0 handler:nil];
}

#pragma mark - Custom Configuration Integration Tests

- (void)testCustomHTTPConfiguration {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Custom HTTP config"];
    
    self.reachability.probeMode = RRProbeModeHTTPOnly;
    self.reachability.httpProbeURL = [NSURL URLWithString:@"https://www.apple.com"];
    self.reachability.timeout = 10.0;
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        if (status == RRReachabilityStatusReachable) {
            NSLog(@"Custom HTTP probe to Apple succeeded");
        } else {
            NSLog(@"Network not available");
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

- (void)testCustomICMPConfiguration {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Custom ICMP config"];
    
    self.reachability.probeMode = RRProbeModeICMPOnly;
    self.reachability.icmpHost = @"1.1.1.1";  // Cloudflare DNS
    self.reachability.icmpPort = 53;
    self.reachability.timeout = 10.0;
    
    [self.reachability checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
        if (status == RRReachabilityStatusReachable) {
            NSLog(@"Custom ICMP probe to Cloudflare succeeded");
        } else {
            NSLog(@"Network not available");
        }
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:15.0 handler:nil];
}

@end
