// swift-tools-version: 6.0
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface prefixed_toplevel_constant
import PackageDescription

// All non-Package.swift files in the directory — each target picks its own source and excludes the rest
let allFiles: [String] = [
  "validate-localization.swift",
  "audit-strings.swift",
  "delete-strings.swift",
  "search-strings.swift",
  "check-swift-imports.swift",
  "validate-localization.sh",
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
    .executable(name: "audit-strings", targets: ["AuditStrings"]),
    .executable(name: "delete-strings", targets: ["DeleteStrings"]),
    .executable(name: "search-strings", targets: ["SearchStrings"]),
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
    ),
  ]
)
