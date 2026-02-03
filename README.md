# RealReachability2

A modern, reliable network reachability library for iOS with both Swift and Objective-C support.

## Features

- **Hybrid Approach**: Combines NWPathMonitor, HTTP HEAD, and ICMP Ping for accurate reachability detection
- **Dual Target Support**: 
  - Swift version (iOS 13+) with async/await API
  - Objective-C version (iOS 12+) with notification-based API
- **Configurable**: Choose between parallel, HTTP-only, or ICMP-only probe modes
- **True Reachability**: Verifies actual internet connectivity, not just network presence
- **Mix ICMP Ping & HTTP HEAD For Real Reachability**: Verifies actual internet connectivity, not just network presence; uses HTTP head & ICMP echo request/reply (based on Apple's SimplePing)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│           NWPathMonitor: path.status == .satisfied       │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────┴──────────────────┐
        │            Parallel Probes           │
        ▼                                     ▼
┌───────────────────┐               ┌───────────────────┐
│   HTTP HEAD       │               │   ICMP Ping       │
│   captive.apple   │               │   8.8.8.8         │
│                   │               │   (Real ICMP)     │
└───────────────────┘               └───────────────────┘
        │                                     │
        └──────────────┬──────────────────────┘
                       ▼
              ┌─────────────────┐
              │  Any Success?   │
              └─────────────────┘
                       │
         ┌─────────────┴─────────────┐
         │ YES                       │ NO
         ▼                           ▼
   ✅ .reachable                ❌ .notReachable
```

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/dustturtle/RealReachability2.git", from: "1.0.0")
]
```

Then add the appropriate target:

```swift
// For Swift (iOS 13+)
.product(name: "RealReachability2", package: "RealReachability2")

// For Objective-C (iOS 12+)
.product(name: "RealReachability2ObjC", package: "RealReachability2")
```

## Usage

### Swift (iOS 13+)

```swift
import RealReachability2

// One-time check
let status = await RealReachability.shared.check()
switch status {
case .reachable(let connectionType):
    print("Connected via \(connectionType)")
case .notReachable:
    print("No internet connection")
case .unknown:
    print("Status unknown")
}

// Continuous monitoring
Task {
    for await status in RealReachability.shared.statusStream {
        print("Network status: \(status)")
    }
}

// SwiftUI usage
.task {
    for await status in RealReachability.shared.statusStream {
        self.networkStatus = status
    }
}

// Configuration
RealReachability.shared.configuration = ReachabilityConfiguration(
    probeMode: .parallel,  // .parallel, .httpOnly, or .icmpOnly
    timeout: 5.0,
    httpProbeURL: URL(string: "https://captive.apple.com/hotspot-detect.html")!,
    icmpHost: "8.8.8.8"  // Host for ICMP ping
)
```

### Objective-C (iOS 12+)

```objc
#import <RealReachability2ObjC/RealReachability2ObjC.h>

// Start monitoring
[[RRReachability sharedInstance] startNotifier];

// Listen for changes
[[NSNotificationCenter defaultCenter] 
    addObserver:self 
    selector:@selector(reachabilityChanged:)
    name:kRRReachabilityChangedNotification 
    object:nil];

- (void)reachabilityChanged:(NSNotification *)notification {
    RRReachabilityStatus status = [notification.userInfo[kRRReachabilityStatusKey] integerValue];
    RRConnectionType type = [notification.userInfo[kRRConnectionTypeKey] integerValue];
    
    switch (status) {
        case RRReachabilityStatusReachable:
            NSLog(@"Network reachable");
            break;
        case RRReachabilityStatusNotReachable:
            NSLog(@"Network not reachable");
            break;
        default:
            break;
    }
}

// One-time check
[[RRReachability sharedInstance] checkReachabilityWithCompletion:^(RRReachabilityStatus status, RRConnectionType type) {
    // Handle result
}];

// Configuration
[RRReachability sharedInstance].probeMode = RRProbeModeParallel;
[RRReachability sharedInstance].timeout = 5.0;

// Stop monitoring
[[RRReachability sharedInstance] stopNotifier];
```

## Probe Modes

| Mode | Description |
|------|-------------|
| `.parallel` (default) | Uses both HTTP HEAD and ICMP in parallel, succeeds if either succeeds |
| `.httpOnly` | Uses only HTTP HEAD request to Apple's captive portal |
| `.icmpOnly` | Uses real ICMP echo request/reply |

## Components

- **NWPathMonitor**: System-level network status changes (fast notification)
- **HTTP HEAD**: Checks connectivity to Apple's captive portal (most reliable)
- **ICMP Ping**: Real ICMP echo request/reply to Google DNS (based on Apple's SimplePing)

## Requirements

- **Swift version**: iOS 13.0+
- **Objective-C version**: iOS 12.0+
- Swift 5.7+

## License

MIT License. See [LICENSE](LICENSE) for details.
