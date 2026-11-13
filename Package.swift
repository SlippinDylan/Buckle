// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuckleCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BuckleCore", targets: ["BuckleCore"]),
        .library(name: "BucklePermissionSupport", type: .static, targets: ["BucklePermissionSupport"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/jaywcjlove/PermissionFlow.git",
            revision: "65434c9ae04dba97cf52c1dffbe3e4e62b547c82")
    ],
    targets: [
        .target(name: "BuckleCore", path: "App/Core"),
        .target(
            name: "BucklePermissionSupport",
            dependencies: [
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "SystemSettingsKit", package: "PermissionFlow"),
            ],
            path: "Support/PermissionGuidance"),
        .testTarget(name: "BuckleCoreTests", dependencies: ["BuckleCore"], path: "Tests/BuckleCoreTests"),
        .testTarget(
            name: "PermissionSupportTests", dependencies: ["BucklePermissionSupport"],
            path: "Tests/PermissionSupportTests"),
    ]
)
