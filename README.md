# RealReachability2

A modern, reliable network reachability library for iOS with both Swift and Objective-C support. Version 1.0 released! Shipped with demos!

## Features

- **Hybrid Approach**: Combines NWPathMonitor, HTTP HEAD, and ICMP Ping for accurate reachability detection
- **Dual Target Support**: 
  - Swift version (iOS 13+) with async/await API
  - Objective-C API supports iOS 12+ (non-SPM/source integration) with notification-based API
  - When integrated via Swift Package Manager, package platform is iOS 13+
- **Configurable**: Choose between parallel, HTTP-only, or ICMP-only probe modes
- **True Reachability**: Verifies actual internet connectivity, not just network presence
- **Fallback Semantics (ObjC)**: Optional Wi-Fi->cellular fallback probe with explicit secondary-link state


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
    .package(url: "https://github.com/dustturtle/RealReachability2.git", from: "1.0")
]
```

Then add the appropriate target:

```swift
// For Swift (iOS 13+)
.product(name: "RealReachability2", package: "RealReachability2")

// For Objective-C via SPM (iOS 13+)
.product(name: "RealReachability2ObjC", package: "RealReachability2")
```

> Note: Under Swift Package Manager, both products follow the package-level `platforms` setting (currently iOS 13+).
> The Objective-C API itself can support iOS 12+, but that does not mean this current SPM package can be consumed directly by iOS 12 projects.

### Source Integration (Without SPM)

If you need different deployment targets between Swift and Objective-C integration, you can integrate from source directly.

#### Swift Source Integration (iOS 13+)

1. In Xcode, use **File -> Add Files to "YourProject"...** and add all `.swift` files under `Sources/RealReachability2/`.
2. In the add-files dialog, enable your app target in **Add to targets** (or your internal framework target).
3. In **Target -> Build Settings -> iOS Deployment Target**, set iOS 13.0 or later.
4. In **Target -> Build Phases -> Link Binary With Libraries**, ensure `Network.framework` is present (required by `NWPathMonitor` usage).
5. In **Target -> Build Phases -> Compile Sources**, verify added Swift files are included.

Usage:

```swift
// If files are added into the same app target, no module import is required.
let status = await RealReachability.shared.check()
```

#### Objective-C Source Integration (iOS 12+)

1. In Xcode, use **File -> Add Files to "YourProject"...** and add Objective-C sources under `Sources/RealReachability2ObjC/`:
   - `RRReachability.m`
   - `RRPathMonitor.m`
   - `RRPingHelper.m`
   - `RRPingFoundation.m`
2. Add headers under `Sources/RealReachability2ObjC/include/`:
   - `RealReachability2ObjC.h`
   - `RRReachability.h`
   - `RRPathMonitor.h`
   - `RRPingFoundation.h`
   - `RRPingHelper.h`
3. In the add-files dialog, enable your target in **Add to targets**, and verify `.m` files are in **Target -> Build Phases -> Compile Sources**.
4. If your project does not use header maps for these paths, set **Target -> Build Settings -> Header Search Paths** to include:
   - `$(SRCROOT)/.../Sources/RealReachability2ObjC/include` (replace `...` with your actual relative path)
5. In **Target -> Build Phases -> Link Binary With Libraries**, ensure `Network.framework` is present.
6. Keep **Target -> Build Settings -> iOS Deployment Target** at iOS 12.0 or later for ObjC source integration.

Usage:

```objc
#import "RealReachability2ObjC.h"
// or: #import "RRReachability.h"
```

If your app is Swift-first but integrates Objective-C sources directly:

1. Set **Target -> Build Settings -> Objective-C Bridging Header** to your bridging header file path.
2. Add `#import "RealReachability2ObjC.h"` inside that bridging header.

Notes:

- `Network.framework` is required for path monitoring.
- `RRPingFoundation.h` references `CFNetwork`/`CoreServices`; these are Apple system frameworks. In typical iOS builds they resolve automatically, but if your linker reports missing symbols, add `CFNetwork.framework` explicitly.

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
    httpProbeURL: URL(string: "https://www.gstatic.com/generate_204")!,
    icmpHost: "8.8.8.8"  // Host for ICMP ping
)
```

### Objective-C (iOS 12+)

```objc
#import <RealReachability2ObjC/RealReachability2ObjC.h>

// Start monitoring
[[RRReachability sharedInstance] startNotifier];

// Listen for changes
// Posted when reachability status or connection type changes
[[NSNotificationCenter defaultCenter] 
    addObserver:self 
    selector:@selector(reachabilityChanged:)
    name:kRRReachabilityChangedNotification 
    object:nil];

- (void)reachabilityChanged:(NSNotification *)notification {
    RRReachabilityStatus status = [notification.userInfo[kRRReachabilityStatusKey] integerValue];
    RRConnectionType type = [notification.userInfo[kRRConnectionTypeKey] integerValue];
    BOOL isSecondaryReachable = [notification.userInfo[kRRSecondaryReachableKey] boolValue];
    
    switch (status) {
        case RRReachabilityStatusReachable:
            if (isSecondaryReachable) {
                NSLog(@"Network reachable (secondary cellular fallback)");
            } else {
                NSLog(@"Network reachable");
            }
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
[RRReachability sharedInstance].periodicProbeEnabled = YES;  // default: YES
[RRReachability sharedInstance].allowCellularFallback = NO;  // default: NO
// allowCellularFallback requires HTTP participation (parallel/httpOnly)
// when enabled on Wi-Fi, ObjC uses HTTP primary probe (cellular disabled) + fallback probe (cellular allowed)
// when disabled on Wi-Fi, ObjC primary HTTP probing also keeps cellular disabled to avoid implicit fallback

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

- **Swift API**: iOS 13.0+
- **Objective-C API**: iOS 12.0+
- **Swift Package Manager integration (current package)**: iOS 13.0+
- Swift 5.7+

## License

MIT License. See [LICENSE](LICENSE) for details.
