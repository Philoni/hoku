// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HueKit",
    defaultLocalization: "de",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "HueKit", targets: ["HueKit"]),
    ],
    targets: [
        .target(name: "HueKit"),
        .testTarget(
            name: "HueKitTests",
            dependencies: ["HueKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
