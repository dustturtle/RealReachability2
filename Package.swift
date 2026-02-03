// swift-tools-version:5.7

import PackageDescription

var products: [Product] = [
    .library(
        name: "RealReachability2",
        targets: ["RealReachability2"]
    )
]

var targets: [Target] = [
    // Swift version - iOS 13+ / macOS 10.15+
    .target(
        name: "RealReachability2",
        dependencies: [],
        path: "Sources/RealReachability2"
    ),
    .testTarget(
        name: "RealReachability2Tests",
        dependencies: ["RealReachability2"]
    )
]

#if canImport(ObjectiveC)
products.append(
    .library(
        name: "RealReachability2ObjC",
        targets: ["RealReachability2ObjC"]
    )
)

targets.append(
    // Objective-C version - iOS 12+
    .target(
        name: "RealReachability2ObjC",
        dependencies: [],
        path: "Sources/RealReachability2ObjC",
        publicHeadersPath: "include"
    )
)

targets.append(
    .testTarget(
        name: "RealReachability2ObjCTests",
        dependencies: ["RealReachability2ObjC"],
        path: "Tests/RealReachability2ObjCTests"
    )
)
#endif

let package = Package(
    name: "RealReachability2",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_15)
    ],
    products: products,
    targets: targets
)
