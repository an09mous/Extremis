// swift-tools-version: 5.9
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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Extremis",
            dependencies: [],
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

