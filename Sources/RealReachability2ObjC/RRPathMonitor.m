//
//  RRPathMonitor.m
//  RealReachability2ObjC
//
//  Created by RealReachability2 on 2026.
//

#import "RRPathMonitor.h"
#import <Network/Network.h>

@interface RRPathMonitor ()

@property (nonatomic, strong) nw_path_monitor_t monitor;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) BOOL isMonitoring;
@property (nonatomic, assign, readwrite) BOOL isSatisfied;
@property (nonatomic, assign, readwrite) RRConnectionType connectionType;

@end

@implementation RRPathMonitor

+ (instancetype)sharedInstance {
    static RRPathMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RRPathMonitor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isSatisfied = NO;
        _connectionType = RRConnectionTypeNone;
        _isMonitoring = NO;
        _queue = dispatch_queue_create("com.realreachability2.pathmonitor", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

- (void)startMonitoring {
    if (self.isMonitoring) {
        return;
    }
    
    self.monitor = nw_path_monitor_create();
    
    __weak typeof(self) weakSelf = self;
    nw_path_monitor_set_update_handler(self.monitor, ^(nw_path_t path) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        BOOL satisfied = (nw_path_get_status(path) == nw_path_status_satisfied);
        RRConnectionType type = [strongSelf connectionTypeFromPath:path];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf.isSatisfied = satisfied;
            strongSelf.connectionType = type;
            
            if (strongSelf.pathUpdateHandler) {
                strongSelf.pathUpdateHandler(satisfied, type);
            }
        });
    });
    
    nw_path_monitor_set_queue(self.monitor, self.queue);
    nw_path_monitor_start(self.monitor);
    self.isMonitoring = YES;
}

- (void)stopMonitoring {
    if (!self.isMonitoring) {
        return;
    }
    
    if (self.monitor) {
        nw_path_monitor_cancel(self.monitor);
        self.monitor = nil;
    }
    
    self.isMonitoring = NO;
}

- (RRConnectionType)connectionTypeFromPath:(nw_path_t)path {
    if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) {
        return RRConnectionTypeWiFi;
    } else if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) {
        return RRConnectionTypeCellular;
    } else if (nw_path_uses_interface_type(path, nw_interface_type_wired)) {
        return RRConnectionTypeWired;
    } else if (nw_path_get_status(path) == nw_path_status_satisfied) {
        return RRConnectionTypeOther;
    } else {
        return RRConnectionTypeNone;
    }
}

@end
