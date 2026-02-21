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
NSString * const kRRSecondaryReachableKey = @"kRRSecondaryReachableKey";
static const NSTimeInterval kRRPeriodicProbeInterval = 5.0;
static NSString * const kRRDefaultHTTPProbeURLString = @"https://www.gstatic.com/generate_204";

@interface RRReachability ()

@property (nonatomic, strong) RRPathMonitor *pathMonitor;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign, readwrite) RRReachabilityStatus currentStatus;
@property (nonatomic, assign, readwrite) RRConnectionType connectionType;
@property (nonatomic, assign, readwrite) BOOL isSecondaryReachable;
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
- (void)performProbeForConnectionType:(RRConnectionType)type completion:(void (^)(BOOL reachable, BOOL secondaryReachable))completion;
- (void)performHTTPProbeAllowingCellular:(BOOL)allowCellular completion:(void (^)(BOOL reachable))completion;
- (void)performParallelProbeAllowingCellular:(BOOL)allowCellular completion:(void (^)(BOOL reachable))completion;
- (BOOL)probeModeSupportsHTTP;
- (BOOL)validateCellularFallbackConfiguration;
- (BOOL)shouldAttemptCellularFallbackForConnectionType:(RRConnectionType)type;
- (void)updateStatus:(RRReachabilityStatus)status connectionType:(RRConnectionType)type secondaryReachable:(BOOL)secondaryReachable;
- (NSURL *)probeURLByAppendingNonce:(NSURL *)url;
- (BOOL)isSuccessfulHTTPProbeResponse:(NSHTTPURLResponse *)response expectedURL:(NSURL *)expectedURL;

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
        _isSecondaryReachable = NO;
        _probeMode = RRProbeModeParallel;
        _timeout = 5.0;
        _httpProbeURL = [NSURL URLWithString:kRRDefaultHTTPProbeURLString];
        _icmpHost = @"8.8.8.8";
        _icmpPort = 53;  // Note: Port is not used for real ICMP ping, kept for API compatibility
        _allowCellularFallback = NO;
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
 `kRRReachabilityChangedNotification` when resolved status, connection type,
 or secondary fallback state changes.

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

- (void)setProbeMode:(RRProbeMode)probeMode {
    _probeMode = probeMode;
    if (self.allowCellularFallback && ![self probeModeSupportsHTTP]) {
        [self validateCellularFallbackConfiguration];
    }
}

- (void)setAllowCellularFallback:(BOOL)allowCellularFallback {
    _allowCellularFallback = allowCellularFallback;
    if (_allowCellularFallback) {
        [self validateCellularFallbackConfiguration];
    }
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
    
    [self updateStatus:RRReachabilityStatusNotReachable connectionType:type secondaryReachable:NO];
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
    [self performProbeForConnectionType:type completion:^(BOOL reachable, BOOL secondaryReachable) {
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
                [strongSelf updateStatus:status connectionType:type secondaryReachable:secondaryReachable];
            }
            
            if (shouldRunPendingProbe) {
                [strongSelf runProbeWithConnectionType:nextType token:nextToken];
            }
        });
    }];
}

- (void)updateStatus:(RRReachabilityStatus)status connectionType:(RRConnectionType)type {
    [self updateStatus:status connectionType:type secondaryReachable:NO];
}

- (void)updateStatus:(RRReachabilityStatus)status connectionType:(RRConnectionType)type secondaryReachable:(BOOL)secondaryReachable {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL statusChanged = (self.currentStatus != status);
        BOOL connectionTypeChanged = (self.connectionType != type);
        BOOL secondaryReachableChanged = (self.isSecondaryReachable != secondaryReachable);
        BOOL shouldNotify = statusChanged || connectionTypeChanged || secondaryReachableChanged;
        self.currentStatus = status;
        self.connectionType = type;
        self.isSecondaryReachable = secondaryReachable;
        
        if (shouldNotify) {
            NSDictionary *userInfo = @{
                kRRReachabilityStatusKey: @(status),
                kRRConnectionTypeKey: @(type),
                kRRSecondaryReachableKey: @(secondaryReachable)
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
            self.isSecondaryReachable = NO;
            completion(RRReachabilityStatusNotReachable, RRConnectionTypeNone);
        });
        return;
    }
    
    RRConnectionType type = self.pathMonitor.connectionType;
    
    [self performProbeForConnectionType:type completion:^(BOOL reachable, BOOL secondaryReachable) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isSecondaryReachable = secondaryReachable;
            RRReachabilityStatus status = reachable ? RRReachabilityStatusReachable : RRReachabilityStatusNotReachable;
            completion(status, type);
        });
    }];
}

- (void)performProbeForConnectionType:(RRConnectionType)type completion:(void (^)(BOOL reachable, BOOL secondaryReachable))completion {
    BOOL shouldAttemptFallback = [self shouldAttemptCellularFallbackForConnectionType:type];
    if (shouldAttemptFallback) {
        if (![self validateCellularFallbackConfiguration]) {
            completion(NO, NO);
            return;
        }
        
        [self performHTTPProbeAllowingCellular:NO completion:^(BOOL primaryReachable) {
            if (primaryReachable) {
                completion(YES, NO);
                return;
            }
            
            [self performHTTPProbeAllowingCellular:YES completion:^(BOOL fallbackReachable) {
                completion(fallbackReachable, fallbackReachable);
            }];
        }];
        return;
    }
    
    // Wi-Fi primary probing should not silently route through cellular when fallback is disabled.
    if (type == RRConnectionTypeWiFi && [self probeModeSupportsHTTP] && !self.allowCellularFallback) {
        if (self.probeMode == RRProbeModeHTTPOnly) {
            [self performHTTPProbeAllowingCellular:NO completion:^(BOOL reachable) {
                completion(reachable, NO);
            }];
            return;
        }
        
        if (self.probeMode == RRProbeModeParallel) {
            [self performParallelProbeAllowingCellular:NO completion:^(BOOL reachable) {
                completion(reachable, NO);
            }];
            return;
        }
    }
    
    [self performProbeWithCompletion:^(BOOL reachable) {
        completion(reachable, NO);
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
    [self performParallelProbeAllowingCellular:YES completion:completion];
}

- (void)performParallelProbeAllowingCellular:(BOOL)allowCellular completion:(void (^)(BOOL reachable))completion {
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
        [self performHTTPProbeAllowingCellular:allowCellular completion:^(BOOL reachable) {
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
    [self performHTTPProbeAllowingCellular:YES completion:completion];
}

- (void)performHTTPProbeAllowingCellular:(BOOL)allowCellular completion:(void (^)(BOOL reachable))completion {
    NSURL *baseURL = self.httpProbeURL;
    NSURL *probeURL = [self probeURLByAppendingNonce:baseURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:probeURL];
    request.HTTPMethod = @"HEAD";
    request.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    request.timeoutInterval = self.timeout;
    request.allowsCellularAccess = allowCellular;
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Pragma"];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
#if DEBUG
            NSLog(@"[RRReachability][HTTPProbe] failed allowCellular=%@ error=%@",
                  allowCellular ? @"YES" : @"NO",
                  error);
#endif
            completion(NO);
            return;
        }
        
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
#if DEBUG
            NSLog(@"[RRReachability][HTTPProbe] failed allowCellular=%@ reason=non-http-response response=%@",
                  allowCellular ? @"YES" : @"NO",
                  response);
#endif
            completion(NO);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        BOOL success = [self isSuccessfulHTTPProbeResponse:httpResponse expectedURL:baseURL];
#if DEBUG
        if (success) {
            NSLog(@"[RRReachability][HTTPProbe] success allowCellular=%@ status=%ld responseURL=%@ expectedURL=%@",
                  allowCellular ? @"YES" : @"NO",
                  (long)httpResponse.statusCode,
                  httpResponse.URL.absoluteString,
                  baseURL.absoluteString);
        }
        if (!success) {
            NSLog(@"[RRReachability][HTTPProbe] failed allowCellular=%@ status=%ld responseURL=%@ expectedURL=%@",
                  allowCellular ? @"YES" : @"NO",
                  (long)httpResponse.statusCode,
                  httpResponse.URL.absoluteString,
                  baseURL.absoluteString);
        }
#endif
        completion(success);
    }];
    
    [task resume];
}

- (NSURL *)probeURLByAppendingNonce:(NSURL *)url {
    if (!url) {
        return nil;
    }
    
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) {
        return url;
    }
    
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    if (components.queryItems.count > 0) {
        [items addObjectsFromArray:components.queryItems];
    }
    [items addObject:[NSURLQueryItem queryItemWithName:@"rr_nonce" value:[[NSUUID UUID] UUIDString]]];
    components.queryItems = items;
    return components.URL ?: url;
}

- (BOOL)isSuccessfulHTTPProbeResponse:(NSHTTPURLResponse *)response expectedURL:(NSURL *)expectedURL {
    if (!response || !expectedURL) {
        return NO;
    }
    
    NSURL *actualURL = response.URL;
    if (!actualURL) {
        return NO;
    }
    
    NSString *expectedHost = expectedURL.host.lowercaseString;
    NSString *actualHost = actualURL.host.lowercaseString;
    BOOL hostMatches = (expectedHost.length > 0 && actualHost.length > 0 && [expectedHost isEqualToString:actualHost]);
    if (!hostMatches) {
        return NO;
    }
    
    NSString *expectedPath = expectedURL.path.length > 0 ? expectedURL.path : @"/";
    NSString *actualPath = actualURL.path.length > 0 ? actualURL.path : @"/";
    BOOL pathMatches = [expectedPath isEqualToString:actualPath];
    if (!pathMatches) {
        return NO;
    }
    
    NSInteger statusCode = response.statusCode;
    BOOL isGenerate204Endpoint = [expectedPath isEqualToString:@"/generate_204"];
    if (isGenerate204Endpoint) {
        return statusCode == 204;
    }
    
    return (statusCode >= 200 && statusCode < 300);
}

- (BOOL)probeModeSupportsHTTP {
    return self.probeMode == RRProbeModeParallel || self.probeMode == RRProbeModeHTTPOnly;
}

- (BOOL)validateCellularFallbackConfiguration {
    if (!self.allowCellularFallback) {
        return YES;
    }
    
    if ([self probeModeSupportsHTTP]) {
        return YES;
    }
    
    NSLog(@"[RRReachability] Configuration error: allowCellularFallback requires HTTP participation (probeMode must be RRProbeModeParallel or RRProbeModeHTTPOnly).");
    return NO;
}

- (BOOL)shouldAttemptCellularFallbackForConnectionType:(RRConnectionType)type {
    return self.allowCellularFallback && (type == RRConnectionTypeWiFi);
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
