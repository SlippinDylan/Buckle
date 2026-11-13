// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuckleCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "BuckleCore", targets: ["BuckleCore"])],
    targets: [
        .target(name: "BuckleCore", path: "App/Core"),
        .testTarget(name: "BuckleCoreTests", dependencies: ["BuckleCore"], path: "Tests/BuckleCoreTests"),
    ]
)
