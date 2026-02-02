// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidexLocalizationScripts",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "convert-strings", targets: ["ConvertStrings"]),
        .executable(name: "validate-localization", targets: ["ValidateLocalization"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        .executableTarget(
            name: "ConvertStrings",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            path: ".",
            exclude: ["validate-localization.swift"],
            sources: ["convert-strings.swift"]
        ),
        .executableTarget(
            name: "ValidateLocalization",
            dependencies: [],
            path: ".",
            exclude: ["convert-strings.swift"],
            sources: ["validate-localization.swift"]
        )
    ]
)
