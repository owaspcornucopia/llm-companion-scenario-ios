// swift-tools-version: 5.7
import PackageDescription

// Keep the portable core separate so testers can validate card decisions without booting a Simulator.
let package = Package(
    name: "PwnedNextCore",
    platforms: [
        .iOS(.v15)
    ],
    // The library is shared by the app target and the package-only test target.
    products: [
        .library(name: "PwnedNextCore", targets: ["PwnedNextCore"])
    ],
    // Pure Swift tests cover parser, decision, crypto-demo, and catalog behavior without native model startup.
    targets: [
        .target(name: "PwnedNextCore"),
        .testTarget(name: "PwnedNextCoreTests", dependencies: ["PwnedNextCore"])
    ]
)