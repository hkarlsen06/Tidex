// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_enum_raw_value
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl sorted_enum_cases
/// Status of a shift preview (shared between iOS and Watch)
enum ShiftPreviewStatus: String, Codable, Sendable {
  case active
  case upcoming
  case past
}
