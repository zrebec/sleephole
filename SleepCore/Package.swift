// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SleepCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SleepCore", targets: ["SleepCore"]),
    ],
    targets: [
        .target(name: "SleepCore"),
        .testTarget(name: "SleepCoreTests", dependencies: ["SleepCore"]),
    ]
)  
