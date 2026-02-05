// swift-tools-version: 6.0
import PackageDescription

// All non-Package.swift files in the directory — each target picks its own source and excludes the rest
let allFiles: [String] = [
    "validate-localization",
    "validate-localization.swift",
    "add-strings",
    "add-strings.swift",
    "audit-strings",
    "audit-strings.swift",
    "delete-strings",
    "delete-strings.swift",
    "search-strings",
    "search-strings.swift",
    "generate-appstore-metadata.mjs",
    "reset-translations.mjs",
    "translate-xcstrings.mjs",
    "appstore-metadata-source.json",
]

func excluding(_ source: String) -> [String] {
    allFiles.filter { $0 != source }
}

let package = Package(
    name: "TidexLocalizationScripts",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "validate-localization", targets: ["ValidateLocalization"]),
        .executable(name: "add-strings", targets: ["AddStrings"]),
        .executable(name: "audit-strings", targets: ["AuditStrings"]),
        .executable(name: "delete-strings", targets: ["DeleteStrings"]),
        .executable(name: "search-strings", targets: ["SearchStrings"])
    ],
    targets: [
        .executableTarget(
            name: "ValidateLocalization",
            dependencies: [],
            path: ".",
            exclude: excluding("validate-localization.swift"),
            sources: ["validate-localization.swift"]
        ),
        .executableTarget(
            name: "AddStrings",
            dependencies: [],
            path: ".",
            exclude: excluding("add-strings.swift"),
            sources: ["add-strings.swift"]
        ),
        .executableTarget(
            name: "AuditStrings",
            dependencies: [],
            path: ".",
            exclude: excluding("audit-strings.swift"),
            sources: ["audit-strings.swift"]
        ),
        .executableTarget(
            name: "DeleteStrings",
            dependencies: [],
            path: ".",
            exclude: excluding("delete-strings.swift"),
            sources: ["delete-strings.swift"]
        ),
        .executableTarget(
            name: "SearchStrings",
            dependencies: [],
            path: ".",
            exclude: excluding("search-strings.swift"),
            sources: ["search-strings.swift"]
        )
    ]
)
