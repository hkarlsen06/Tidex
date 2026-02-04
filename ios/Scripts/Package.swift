// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidexLocalizationScripts",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "validate-localization", targets: ["ValidateLocalization"]),
        .executable(name: "add-string", targets: ["AddString"]),
        .executable(name: "audit-strings", targets: ["AuditStrings"])
    ],
    targets: [
        .executableTarget(
            name: "ValidateLocalization",
            dependencies: [],
            path: ".",
            sources: ["validate-localization.swift"]
        ),
        .executableTarget(
            name: "AddString",
            dependencies: [],
            path: ".",
            sources: ["add-string.swift"]
        ),
        .executableTarget(
            name: "AuditStrings",
            dependencies: [],
            path: ".",
            sources: ["audit-strings.swift"]
        )
    ]
)
