//
//  RRPathMonitor.h
//  RealReachability2ObjC
//
//  Created by RealReachability2 on 2026.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Connection type for network path
typedef NS_ENUM(NSInteger, RRConnectionType) {
    /// WiFi connection
    RRConnectionTypeWiFi,
    /// Cellular connection
    RRConnectionTypeCellular,
    /// Wired/Ethernet connection
    RRConnectionTypeWired,
    /// Other or unknown connection type
    RRConnectionTypeOther,
    /// No connection
    RRConnectionTypeNone
};

/// Callback for path updates
typedef void (^RRPathUpdateHandler)(BOOL satisfied, RRConnectionType connectionType);

/// Wrapper for NWPathMonitor (iOS 12+)
API_AVAILABLE(ios(12.0))
@interface RRPathMonitor : NSObject

/// Whether the network path is currently satisfied
@property (nonatomic, readonly) BOOL isSatisfied;

/// Current connection type
@property (nonatomic, readonly) RRConnectionType connectionType;

/// Handler for path updates
@property (nonatomic, copy, nullable) RRPathUpdateHandler pathUpdateHandler;

/// Shared instance
+ (instancetype)sharedInstance;

/// Starts monitoring network path
- (void)startMonitoring;

/// Stops monitoring network path
- (void)stopMonitoring;

@end

NS_ASSUME_NONNULL_END
