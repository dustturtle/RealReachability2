//
//  RRReachability.m
//  RealReachability2ObjC
//
//  Created by RealReachability2 on 2026.
//

#import "RRReachability.h"
#import "RRPathMonitor.h"
#import <Network/Network.h>

NSNotificationName const kRRReachabilityChangedNotification = @"kRRReachabilityChangedNotification";
NSString * const kRRReachabilityStatusKey = @"kRRReachabilityStatusKey";
NSString * const kRRConnectionTypeKey = @"kRRConnectionTypeKey";

@interface RRReachability ()

@property (nonatomic, strong) RRPathMonitor *pathMonitor;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign, readwrite) RRReachabilityStatus currentStatus;
@property (nonatomic, assign, readwrite) RRConnectionType connectionType;
@property (nonatomic, assign, readwrite) BOOL isNotifierRunning;
@property (nonatomic, strong) dispatch_queue_t probeQueue;

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
        _icmpPort = 53;
        _isNotifierRunning = NO;
        _probeQueue = dispatch_queue_create("com.realreachability2.probe", DISPATCH_QUEUE_CONCURRENT);
        
        _pathMonitor = [[RRPathMonitor alloc] init];
        
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

- (void)startNotifier {
    if (self.isNotifierRunning) {
        return;
    }
    
    self.isNotifierRunning = YES;
    
    __weak typeof(self) weakSelf = self;
    self.pathMonitor.pathUpdateHandler = ^(BOOL satisfied, RRConnectionType type) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.connectionType = type;
        
        if (satisfied) {
            [strongSelf performProbeWithCompletion:^(BOOL reachable) {
                [strongSelf updateStatus:reachable ? RRReachabilityStatusReachable : RRReachabilityStatusNotReachable
                          connectionType:type];
            }];
        } else {
            [strongSelf updateStatus:RRReachabilityStatusNotReachable connectionType:type];
        }
    };
    
    [self.pathMonitor startMonitoring];
}

- (void)stopNotifier {
    if (!self.isNotifierRunning) {
        return;
    }
    
    self.isNotifierRunning = NO;
    self.pathMonitor.pathUpdateHandler = nil;
    [self.pathMonitor stopMonitoring];
}

- (void)updateStatus:(RRReachabilityStatus)status connectionType:(RRConnectionType)type {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL statusChanged = (self.currentStatus != status);
        self.currentStatus = status;
        self.connectionType = type;
        
        if (statusChanged) {
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
    // Use Network framework for TCP connection check
    nw_endpoint_t endpoint = nw_endpoint_create_host([self.icmpHost UTF8String], 
                                                      [[NSString stringWithFormat:@"%d", self.icmpPort] UTF8String]);
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, 
                                                                   NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_connection_t connection = nw_connection_create(endpoint, parameters);
    
    __block BOOL completionCalled = NO;
    dispatch_semaphore_t lock = dispatch_semaphore_create(1);
    
    dispatch_queue_t queue = dispatch_queue_create("com.realreachability2.icmp", DISPATCH_QUEUE_SERIAL);
    
    // Set up timeout
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeout * NSEC_PER_SEC)), queue, ^{
        dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
        if (!completionCalled) {
            completionCalled = YES;
            dispatch_semaphore_signal(lock);
            nw_connection_cancel(connection);
            completion(NO);
        } else {
            dispatch_semaphore_signal(lock);
        }
    });
    
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        switch (state) {
            case nw_connection_state_ready:
                dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
                if (!completionCalled) {
                    completionCalled = YES;
                    dispatch_semaphore_signal(lock);
                    nw_connection_cancel(connection);
                    completion(YES);
                } else {
                    dispatch_semaphore_signal(lock);
                }
                break;
                
            case nw_connection_state_failed:
            case nw_connection_state_cancelled:
                dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
                if (!completionCalled) {
                    completionCalled = YES;
                    dispatch_semaphore_signal(lock);
                    nw_connection_cancel(connection);
                    completion(NO);
                } else {
                    dispatch_semaphore_signal(lock);
                }
                break;
                
            default:
                break;
        }
    });
    
    nw_connection_set_queue(connection, queue);
    nw_connection_start(connection);
}

@end
