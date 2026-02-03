//
//  RRPingHelper.h
//  RealReachability2ObjC
//
//  A helper class that wraps RRPingFoundation for easier use.
//  Based on PingHelper from RealReachability.
//
//  Copyright © 2016 Dustturtle. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Completion block type for ping operations
typedef void (^RRPingCompletionBlock)(BOOL isSuccess, NSTimeInterval latency);

/// Helper class for ICMP ping operations
/// Provides a simple block-based API for pinging hosts.
API_AVAILABLE(ios(12.0), macos(10.14))
@interface RRPingHelper : NSObject

/// The host to ping. You MUST set this before calling pingWithBlock:.
@property (nonatomic, copy, nullable) NSString *host;

/// Ping timeout in seconds. Default is 2 seconds.
@property (nonatomic, assign) NSTimeInterval timeout;

/// Triggers a ping action with a completion block.
/// @param completion Async completion block called with success status and latency (in seconds).
///        Latency is 0 if ping failed.
- (void)pingWithBlock:(RRPingCompletionBlock)completion;

/// Cancels any ongoing ping operation.
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
