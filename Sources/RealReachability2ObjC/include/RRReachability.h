//
//  RRReachability.h
//  RealReachability2ObjC
//
//  Created by RealReachability2 on 2026.
//

#import <Foundation/Foundation.h>
#import "RRPathMonitor.h"

NS_ASSUME_NONNULL_BEGIN

/// Notification posted when reachability status changes
FOUNDATION_EXPORT NSNotificationName const kRRReachabilityChangedNotification;

/// Key for the reachability status in the notification userInfo
FOUNDATION_EXPORT NSString * const kRRReachabilityStatusKey;

/// Key for the connection type in the notification userInfo
FOUNDATION_EXPORT NSString * const kRRConnectionTypeKey;

/// Reachability status
typedef NS_ENUM(NSInteger, RRReachabilityStatus) {
    /// Network status is unknown
    RRReachabilityStatusUnknown,
    /// Network is not reachable
    RRReachabilityStatusNotReachable,
    /// Network is reachable
    RRReachabilityStatusReachable
};

/// Probe mode for reachability checks
typedef NS_ENUM(NSInteger, RRProbeMode) {
    /// Use both HTTP and ICMP probes in parallel (default)
    RRProbeModeParallel,
    /// Use only HTTP HEAD probe
    RRProbeModeHTTPOnly,
    /// Use only ICMP ping probe
    RRProbeModeICMPOnly
};

/// Main reachability class with notification-based API
API_AVAILABLE(ios(12.0))
@interface RRReachability : NSObject

/// Shared singleton instance
+ (instancetype)sharedInstance;

/// Current reachability status
@property (nonatomic, readonly) RRReachabilityStatus currentStatus;

/// Current connection type
@property (nonatomic, readonly) RRConnectionType connectionType;

/// Probe mode (default: RRProbeModeParallel)
@property (nonatomic, assign) RRProbeMode probeMode;

/// Timeout for probe requests in seconds (default: 5.0)
@property (nonatomic, assign) NSTimeInterval timeout;

/// HTTP probe URL (default: https://captive.apple.com/hotspot-detect.html)
@property (nonatomic, strong) NSURL *httpProbeURL;

/// ICMP ping host (default: 8.8.8.8)
@property (nonatomic, copy) NSString *icmpHost;

/// ICMP ping port (default: 53)
@property (nonatomic, assign) uint16_t icmpPort;

/// Starts the reachability notifier
/// Posts kRRReachabilityChangedNotification when status changes
- (void)startNotifier;

/// Stops the reachability notifier
- (void)stopNotifier;

/// Performs a one-time reachability check
/// @param completion Callback with the reachability status and connection type
- (void)checkReachabilityWithCompletion:(void (^)(RRReachabilityStatus status, RRConnectionType type))completion;

/// Whether the notifier is currently running
@property (nonatomic, readonly) BOOL isNotifierRunning;

@end

NS_ASSUME_NONNULL_END
