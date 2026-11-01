// swift-tools-version:6.0
// DocumentationAgent: documentation of any codebase, as a README, as Markdown docs, or as an interactive static site
// with a code explorer, as a Granite agent package. An app that links it finds the `docs` agent through Granite's
// roster, with nothing listed by hand.

import PackageDescription

let package = Package(
    name: "DocumentationAgent",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DocumentationAgent", targets: ["DocumentationAgent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/riteshpakala/Granite.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "DocumentationAgent",
            dependencies: [.product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "DocumentationAgentTests",
            dependencies: ["DocumentationAgent", .product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
