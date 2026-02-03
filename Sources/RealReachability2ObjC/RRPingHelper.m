//
//  RRPingHelper.m
//  RealReachability2ObjC
//
//  A helper class that wraps RRPingFoundation for easier use.
//  Based on PingHelper from RealReachability.
//
//  Copyright © 2016 Dustturtle. All rights reserved.
//

#import "RRPingHelper.h"
#import "RRPingFoundation.h"

@interface RRPingHelper () <RRPingFoundationDelegate>

@property (nonatomic, strong) NSMutableArray<RRPingCompletionBlock> *completionBlocks;
@property (nonatomic, strong, nullable) RRPingFoundation *pingFoundation;
@property (nonatomic, assign) BOOL isPinging;
@property (nonatomic, assign) CFAbsoluteTime pingStartTime;
@property (nonatomic, strong, nullable) NSTimer *timeoutTimer;

@end

@implementation RRPingHelper

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _isPinging = NO;
        _timeout = 2.0;
        _completionBlocks = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    [self cancel];
    [self.completionBlocks removeAllObjects];
}

#pragma mark - Public Methods

- (void)pingWithBlock:(RRPingCompletionBlock)completion {
    if (completion) {
        @synchronized(self) {
            [self.completionBlocks addObject:[completion copy]];
        }
    }
    
    if (!self.isPinging) {
        // Must ensure pingFoundation runs on main thread
        __weak typeof(self) weakSelf = self;
        if (![[NSThread currentThread] isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf startPing];
            });
        } else {
            [self startPing];
        }
    }
}

- (void)cancel {
    [self clearPingFoundation];
    [self invalidateTimer];
    self.isPinging = NO;
    
    @synchronized(self) {
        [self.completionBlocks removeAllObjects];
    }
}

#pragma mark - Private Methods

- (void)clearPingFoundation {
    if (self.pingFoundation) {
        [self.pingFoundation stop];
        self.pingFoundation.delegate = nil;
        self.pingFoundation = nil;
    }
}

- (void)invalidateTimer {
    if (self.timeoutTimer) {
        [self.timeoutTimer invalidate];
        self.timeoutTimer = nil;
    }
}

- (void)startPing {
    if (!self.host || self.host.length == 0) {
        // No host set, fail immediately
        [self endWithFlag:NO];
        return;
    }
    
    [self clearPingFoundation];
    
    self.isPinging = YES;
    self.pingStartTime = CFAbsoluteTimeGetCurrent();
    
    self.pingFoundation = [[RRPingFoundation alloc] initWithHostName:self.host];
    self.pingFoundation.delegate = self;
    [self.pingFoundation start];
    
    // Setup timeout
    __weak typeof(self) weakSelf = self;
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:self.timeout repeats:NO block:^(NSTimer * _Nonnull timer) {
        [weakSelf pingTimeOut];
    }];
}

- (void)setHost:(NSString *)host {
    _host = [host copy];
    
    // Clear any existing ping foundation when host changes
    self.pingFoundation.delegate = nil;
    self.pingFoundation = nil;
}

- (void)endWithFlag:(BOOL)isSuccess {
    [self invalidateTimer];
    
    if (!self.isPinging) {
        return;
    }
    
    self.isPinging = NO;
    
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    NSTimeInterval latency = isSuccess ? (end - self.pingStartTime) : 0;
    
    [self clearPingFoundation];
    
    @synchronized(self) {
        for (RRPingCompletionBlock completion in self.completionBlocks) {
            completion(isSuccess, latency);
        }
        [self.completionBlocks removeAllObjects];
    }
}

#pragma mark - RRPingFoundationDelegate

- (void)pingFoundation:(RRPingFoundation *)pinger didStartWithAddress:(NSData *)address {
    // Send the ping immediately when started
    [self.pingFoundation sendPingWithData:nil];
}

- (void)pingFoundation:(RRPingFoundation *)pinger didFailWithError:(NSError *)error {
    [self endWithFlag:NO];
}

- (void)pingFoundation:(RRPingFoundation *)pinger didFailToSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber error:(NSError *)error {
    [self endWithFlag:NO];
}

- (void)pingFoundation:(RRPingFoundation *)pinger didReceivePingResponsePacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber {
    [self endWithFlag:YES];
}

#pragma mark - Timeout Handler

- (void)pingTimeOut {
    if (!self.isPinging) {
        return;
    }
    
    self.isPinging = NO;
    [self clearPingFoundation];
    
    @synchronized(self) {
        for (RRPingCompletionBlock completion in self.completionBlocks) {
            completion(NO, self.timeout);
        }
        [self.completionBlocks removeAllObjects];
    }
}

@end
