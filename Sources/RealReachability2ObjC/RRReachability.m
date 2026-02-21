//
//  RRReachability.m
//  RealReachability2ObjC
//
//  Created by RealReachability2 on 2026.
//

#import "RRReachability.h"
#import "RRPathMonitor.h"
#import "RRPingHelper.h"
#import <Network/Network.h>

NSNotificationName const kRRReachabilityChangedNotification = @"kRRReachabilityChangedNotification";
NSString * const kRRReachabilityStatusKey = @"kRRReachabilityStatusKey";
NSString * const kRRConnectionTypeKey = @"kRRConnectionTypeKey";
static const NSTimeInterval kRRPeriodicProbeInterval = 5.0;

@interface RRReachability ()

@property (nonatomic, strong) RRPathMonitor *pathMonitor;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign, readwrite) RRReachabilityStatus currentStatus;
@property (nonatomic, assign, readwrite) RRConnectionType connectionType;
@property (nonatomic, assign, readwrite) BOOL isNotifierRunning;
@property (nonatomic, strong) dispatch_queue_t probeQueue;
@property (nonatomic, strong) RRPingHelper *pingHelper;
@property (nonatomic, strong, nullable) dispatch_source_t periodicProbeTimer;
@property (nonatomic, assign) BOOL probeInFlight;
@property (nonatomic, assign) BOOL hasPendingProbe;
@property (nonatomic, assign) RRConnectionType pendingProbeConnectionType;
@property (nonatomic, assign) NSUInteger probeSequence;

- (void)startPeriodicProbeIfNeeded;
- (void)stopPeriodicProbeIfNeeded;
- (void)handlePeriodicProbeTick;
- (void)handleUnsatisfiedPathWithConnectionType:(RRConnectionType)type;
- (void)triggerProbeForConnectionType:(RRConnectionType)type;
- (void)runProbeWithConnectionType:(RRConnectionType)type token:(NSUInteger)token;

@end

@implementation RRReachability

+ (instancetype)sharedInstance {
    static RRReachability *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RRReachability alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentStatus = RRReachabilityStatusUnknown;
        _connectionType = RRConnectionTypeNone;
        _probeMode = RRProbeModeParallel;
        _timeout = 5.0;
        _httpProbeURL = [NSURL URLWithString:@"https://captive.apple.com/hotspot-detect.html"];
        _icmpHost = @"8.8.8.8";
        _icmpPort = 53;  // Note: Port is not used for real ICMP ping, kept for API compatibility
        _periodicProbeEnabled = YES;
        _isNotifierRunning = NO;
        _probeInFlight = NO;
        _hasPendingProbe = NO;
        _pendingProbeConnectionType = RRConnectionTypeNone;
        _probeSequence = 0;
        _probeQueue = dispatch_queue_create("com.realreachability2.probe", DISPATCH_QUEUE_CONCURRENT);
        
        _pathMonitor = [[RRPathMonitor alloc] init];
        
        _pingHelper = [[RRPingHelper alloc] init];
        _pingHelper.host = _icmpHost;
        _pingHelper.timeout = _timeout;
        
        [self setupURLSession];
    }
    return self;
}

- (void)setupURLSession {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = self.timeout;
    config.timeoutIntervalForResource = self.timeout;
    config.waitsForConnectivity = NO;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    self.session = [NSURLSession sessionWithConfiguration:config];
}

/**
 Starts continuous network reachability monitoring.

 This method installs a path update handler, begins monitoring via `RRPathMonitor`,
 and runs active probes (HTTP and/or ICMP based on `probeMode`) when the network
 path becomes satisfied.

 The notifier is idempotent: calling this method while monitoring is already active
 has no effect.

 - Note: Reachability change notifications are posted through
 `kRRReachabilityChangedNotification` when either the resolved status or
 connection type changes.

- SeeAlso: `-stopNotifier`
 */
- (void)startNotifier {
    if (self.isNotifierRunning) {
        return;
    }
    
    self.isNotifierRunning = YES;
    
    __weak typeof(self) weakSelf = self;
    self.pathMonitor.pathUpdateHandler = ^(BOOL satisfied, RRConnectionType type) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (satisfied) {
            [strongSelf triggerProbeForConnectionType:type];
        } else {
            [strongSelf handleUnsatisfiedPathWithConnectionType:type];
        }
    };
    
    [self.pathMonitor startMonitoring];
    [self startPeriodicProbeIfNeeded];
}

- (void)stopNotifier {
    if (!self.isNotifierRunning) {
        return;
    }
    
    self.isNotifierRunning = NO;
    [self stopPeriodicProbeIfNeeded];
    self.pathMonitor.pathUpdateHandler = nil;
    [self.pathMonitor stopMonitoring];
    
    @synchronized(self) {
        self.probeSequence += 1;
        self.probeInFlight = NO;
        self.hasPendingProbe = NO;
        self.pendingProbeConnectionType = RRConnectionTypeNone;
    }
}

- (void)setPeriodicProbeEnabled:(BOOL)periodicProbeEnabled {
    _periodicProbeEnabled = periodicProbeEnabled;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.isNotifierRunning) {
            return;
        }
        
        if (self.periodicProbeEnabled) {
            [self startPeriodicProbeIfNeeded];
            [self handlePeriodicProbeTick];
        } else {
            [self stopPeriodicProbeIfNeeded];
        }
    });
}

- (void)startPeriodicProbeIfNeeded {
    if (!self.periodicProbeEnabled || !self.isNotifierRunning || self.periodicProbeTimer != nil) {
        return;
    }
    
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!timer) {
        return;
    }
    
    uint64_t interval = (uint64_t)(kRRPeriodicProbeInterval * NSEC_PER_SEC);
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, interval),
                              interval,
                              (uint64_t)(0.2 * NSEC_PER_SEC));
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf handlePeriodicProbeTick];
    });
    
    self.periodicProbeTimer = timer;
    dispatch_resume(timer);
}

- (void)stopPeriodicProbeIfNeeded {
    if (!self.periodicProbeTimer) {
        return;
    }
    
    dispatch_source_cancel(self.periodicProbeTimer);
    self.periodicProbeTimer = nil;
}

- (void)handlePeriodicProbeTick {
    if (!self.isNotifierRunning || !self.periodicProbeEnabled) {
        return;
    }
    
    RRConnectionType type = self.pathMonitor.connectionType;
    if (!self.pathMonitor.isSatisfied) {
        [self handleUnsatisfiedPathWithConnectionType:type];
        return;
    }
    
    [self triggerProbeForConnectionType:type];
}

- (void)handleUnsatisfiedPathWithConnectionType:(RRConnectionType)type {
    @synchronized(self) {
        self.probeSequence += 1;
        self.probeInFlight = NO;
        self.hasPendingProbe = NO;
        self.pendingProbeConnectionType = RRConnectionTypeNone;
    }
    
    [self updateStatus:RRReachabilityStatusNotReachable connectionType:type];
}

- (void)triggerProbeForConnectionType:(RRConnectionType)type {
    NSUInteger token = 0;
    
    @synchronized(self) {
        if (!self.isNotifierRunning) {
            return;
        }
        
        if (self.probeInFlight) {
            self.hasPendingProbe = YES;
            self.pendingProbeConnectionType = type;
            return;
        }
        
        self.probeInFlight = YES;
        self.probeSequence += 1;
        token = self.probeSequence;
    }
    
    [self runProbeWithConnectionType:type token:token];
}

- (void)runProbeWithConnectionType:(RRConnectionType)type token:(NSUInteger)token {
    __weak typeof(self) weakSelf = self;
    [self performProbeWithCompletion:^(BOOL reachable) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL shouldApplyResult = NO;
            BOOL shouldRunPendingProbe = NO;
            RRConnectionType nextType = RRConnectionTypeNone;
            NSUInteger nextToken = 0;
            
            @synchronized(strongSelf) {
                shouldApplyResult = strongSelf.isNotifierRunning && (token == strongSelf.probeSequence);
                
                if (strongSelf.hasPendingProbe && strongSelf.isNotifierRunning && strongSelf.pathMonitor.isSatisfied) {
                    shouldRunPendingProbe = YES;
                    nextType = strongSelf.pendingProbeConnectionType;
                    strongSelf.hasPendingProbe = NO;
                    strongSelf.probeSequence += 1;
                    nextToken = strongSelf.probeSequence;
                    strongSelf.probeInFlight = YES;
                } else {
                    strongSelf.hasPendingProbe = NO;
                    strongSelf.pendingProbeConnectionType = RRConnectionTypeNone;
                    strongSelf.probeInFlight = NO;
                }
            }
            
            if (shouldApplyResult) {
                RRReachabilityStatus status = reachable ? RRReachabilityStatusReachable : RRReachabilityStatusNotReachable;
                [strongSelf updateStatus:status connectionType:type];
            }
            
            if (shouldRunPendingProbe) {
                [strongSelf runProbeWithConnectionType:nextType token:nextToken];
            }
        });
    }];
}

- (void)updateStatus:(RRReachabilityStatus)status connectionType:(RRConnectionType)type {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL statusChanged = (self.currentStatus != status);
        BOOL connectionTypeChanged = (self.connectionType != type);
        BOOL shouldNotify = statusChanged || connectionTypeChanged;
        self.currentStatus = status;
        self.connectionType = type;
        
        if (shouldNotify) {
            NSDictionary *userInfo = @{
                kRRReachabilityStatusKey: @(status),
                kRRConnectionTypeKey: @(type)
            };
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kRRReachabilityChangedNotification
                                                                object:self
                                                              userInfo:userInfo];
        }
    });
}

- (void)checkReachabilityWithCompletion:(void (^)(RRReachabilityStatus, RRConnectionType))completion {
    if (!self.pathMonitor.isSatisfied) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(RRReachabilityStatusNotReachable, RRConnectionTypeNone);
        });
        return;
    }
    
    RRConnectionType type = self.pathMonitor.connectionType;
    
    [self performProbeWithCompletion:^(BOOL reachable) {
        dispatch_async(dispatch_get_main_queue(), ^{
            RRReachabilityStatus status = reachable ? RRReachabilityStatusReachable : RRReachabilityStatusNotReachable;
            completion(status, type);
        });
    }];
}

- (void)performProbeWithCompletion:(void (^)(BOOL reachable))completion {
    switch (self.probeMode) {
        case RRProbeModeParallel:
            [self performParallelProbeWithCompletion:completion];
            break;
        case RRProbeModeHTTPOnly:
            [self performHTTPProbeWithCompletion:completion];
            break;
        case RRProbeModeICMPOnly:
            [self performICMPProbeWithCompletion:completion];
            break;
    }
}

- (void)performParallelProbeWithCompletion:(void (^)(BOOL reachable))completion {
    __block BOOL httpResult = NO;
    __block BOOL icmpResult = NO;
    __block BOOL httpDone = NO;
    __block BOOL icmpDone = NO;
    __block BOOL completionCalled = NO;
    
    dispatch_semaphore_t lock = dispatch_semaphore_create(1);
    
    void (^checkCompletion)(void) = ^{
        dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
        
        // If either succeeds, return immediately
        if ((httpResult || icmpResult) && !completionCalled) {
            completionCalled = YES;
            dispatch_semaphore_signal(lock);
            completion(YES);
            return;
        }
        
        // If both are done and neither succeeded
        if (httpDone && icmpDone && !completionCalled) {
            completionCalled = YES;
            dispatch_semaphore_signal(lock);
            completion(NO);
            return;
        }
        
        dispatch_semaphore_signal(lock);
    };
    
    // HTTP Probe
    dispatch_async(self.probeQueue, ^{
        [self performHTTPProbeWithCompletion:^(BOOL reachable) {
            dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
            httpResult = reachable;
            httpDone = YES;
            dispatch_semaphore_signal(lock);
            checkCompletion();
        }];
    });
    
    // ICMP Probe
    dispatch_async(self.probeQueue, ^{
        [self performICMPProbeWithCompletion:^(BOOL reachable) {
            dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
            icmpResult = reachable;
            icmpDone = YES;
            dispatch_semaphore_signal(lock);
            checkCompletion();
        }];
    });
}

- (void)performHTTPProbeWithCompletion:(void (^)(BOOL reachable))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.httpProbeURL];
    request.HTTPMethod = @"HEAD";
    request.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    request.timeoutInterval = self.timeout;
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(NO);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        BOOL success = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 400);
        completion(success);
    }];
    
    [task resume];
}

- (void)performICMPProbeWithCompletion:(void (^)(BOOL reachable))completion {
    // Use real ICMP ping via RRPingHelper
    self.pingHelper.host = self.icmpHost;
    self.pingHelper.timeout = self.timeout;
    
    [self.pingHelper pingWithBlock:^(BOOL isSuccess, NSTimeInterval latency) {
        completion(isSuccess);
    }];
}

@end
