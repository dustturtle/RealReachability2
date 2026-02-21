//
//  RRReachability.h
//  RealReachability2ObjC
//
//  Created by RealReachability2 on 2026.
//

#import <Foundation/Foundation.h>
#import "RRPathMonitor.h"

NS_ASSUME_NONNULL_BEGIN

/// Notification posted when reachability status, connection type, or secondary fallback state changes
FOUNDATION_EXPORT NSNotificationName const kRRReachabilityChangedNotification;

/// Key for the reachability status in the notification userInfo
FOUNDATION_EXPORT NSString * const kRRReachabilityStatusKey;

/// Key for the connection type in the notification userInfo
FOUNDATION_EXPORT NSString * const kRRConnectionTypeKey;

/// Key for the secondary-link reachability flag in the notification userInfo
FOUNDATION_EXPORT NSString * const kRRSecondaryReachableKey;

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

/// Whether network is reachable through secondary fallback link (for example, cellular fallback while on Wi-Fi)
@property (nonatomic, readonly) BOOL isSecondaryReachable;

/// Probe mode (default: RRProbeModeParallel)
@property (nonatomic, assign) RRProbeMode probeMode;

/// Timeout for probe requests in seconds (default: 5.0)
@property (nonatomic, assign) NSTimeInterval timeout;

/// HTTP probe URL (default: https://www.gstatic.com/generate_204)
@property (nonatomic, strong) NSURL *httpProbeURL;

/// ICMP ping host (default: 8.8.8.8)
@property (nonatomic, copy) NSString *icmpHost;

/// ICMP ping port (default: 53)
@property (nonatomic, assign) uint16_t icmpPort;

/// Enables cellular fallback when primary Wi-Fi probe fails (default: NO).
/// Requires HTTP participation (.parallel or .httpOnly). Invalid with .icmpOnly.
/// When enabled on Wi-Fi, probing uses HTTP primary/fallback checks and updates isSecondaryReachable.
/// When disabled on Wi-Fi, primary HTTP probing keeps cellular access disabled.
@property (nonatomic, assign) BOOL allowCellularFallback;

/// Enables periodic probing while notifier is running (default: YES).
/// When disabled, monitoring falls back to path-change-driven probing only.
@property (nonatomic, assign) BOOL periodicProbeEnabled;

/// Starts the reachability notifier
/// Posts kRRReachabilityChangedNotification when status, connection type, or secondary fallback state changes
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
