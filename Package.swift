// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "RealReachability2",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "RealReachability2",
            targets: ["RealReachability2"]
        ),
        .library(
            name: "RealReachability2ObjC",
            targets: ["RealReachability2ObjC"]
        )
    ],
    targets: [
        // Swift version - iOS 13+ / macOS 10.15+
        .target(
            name: "RealReachability2",
            dependencies: [],
            path: "Sources/RealReachability2"
        ),
        // Objective-C version - iOS 12+
        .target(
            name: "RealReachability2ObjC",
            dependencies: [],
            path: "Sources/RealReachability2ObjC",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "RealReachability2Tests",
            dependencies: ["RealReachability2"]
        ),
        .testTarget(
            name: "RealReachability2ObjCTests",
            dependencies: ["RealReachability2ObjC"],
            path: "Tests/RealReachability2ObjCTests"
        )
    ]
)