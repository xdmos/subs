// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SubsCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SubsCore", targets: ["SubsCore"]),
    ],
    targets: [
        .target(name: "SubsCore"),
        .testTarget(name: "SubsCoreTests", dependencies: ["SubsCore"]),
    ]
)
