// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Extremis",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Extremis",
            targets: ["Extremis"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "Extremis",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: ".",
            exclude: [
                "Package.swift",
                "Info.plist",
                "Extremis.entitlements",
                "scripts",
                "build",
                "Tests",
                "docs"
            ],
            sources: [
                "App",
                "Connectors",
                "Core",
                "Extractors",
                "LLMProviders",
                "UI",
                "Utilities"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)

