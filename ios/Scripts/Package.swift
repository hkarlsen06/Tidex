// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidexLocalizationScripts",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "validate-localization", targets: ["ValidateLocalization"])
    ],
    targets: [
        .executableTarget(
            name: "ValidateLocalization",
            dependencies: [],
            path: ".",
            sources: ["validate-localization.swift"]
        )
    ]
)
