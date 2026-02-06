import Foundation

/// Status of a shift preview (shared between iOS and Watch)
enum ShiftPreviewStatus: String, Codable, Sendable {
  case active
  case upcoming
  case past
}
