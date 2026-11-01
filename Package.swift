// swift-tools-version:6.0
// NetworkAgent: an app's backend API layer, a typed client package written from compact endpoint and entity lines,
// as a Granite agent package. An app that links it finds the `network` agent through Granite's roster, with nothing
// listed by hand.

import PackageDescription

let package = Package(
    name: "NetworkAgent",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NetworkAgent", targets: ["NetworkAgent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/riteshpakala/Granite.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "NetworkAgent",
            dependencies: [.product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "NetworkAgentTests",
            dependencies: ["NetworkAgent", .product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
