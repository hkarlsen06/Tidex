import SwiftUI

/// Progress bar showing Wagey message usage
/// - Blue: < 75% used
/// - Yellow: 75-99% used
/// - Red: 100% used (limit reached)
struct WageyUsageBar: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  /// Number of messages used this month
  let used: Int  // swiftlint:disable:this explicit_acl

  /// Total message limit
  let limit: Int  // swiftlint:disable:this explicit_acl

  /// Calculated progress (0.0 to 1.0)
  private var progress: Double {
    guard limit > 0 else { return 0 }  // swiftlint:disable:this conditional_returns_on_newline
    return min(Double(used) / Double(limit), 1.0)
  }

  /// Color based on usage percentage
  private var progressColor: Color {
    switch progress {
    case 0..<0.75:  // swiftlint:disable:this no_magic_numbers
      return .tidexBlue

    case 0.75..<1.0:  // swiftlint:disable:this no_magic_numbers
      return .tidexWarning

    default:
      return .tidexError
    }
  }

  /// Background color for the track
  private var trackColor: Color {
    progressColor.opacity(0.15)  // swiftlint:disable:this no_magic_numbers
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        // Track
        RoundedRectangle(cornerRadius: 2)  // swiftlint:disable:this no_magic_numbers
          .fill(trackColor)
          .frame(height: 4)  // swiftlint:disable:this no_magic_numbers

        // Progress
        RoundedRectangle(cornerRadius: 2)  // swiftlint:disable:this no_magic_numbers
          .fill(progressColor)
          .frame(width: geometry.size.width * progress, height: 4)  // swiftlint:disable:this no_magic_numbers
          .animation(.easeInOut(duration: 0.3), value: progress)  // swiftlint:disable:this no_magic_numbers
      }
    }
    .frame(height: 4)  // swiftlint:disable:this no_magic_numbers
  }
}

// MARK: - Previews

#Preview("Low Usage") {
  VStack(spacing: Spacing.mlg) {
    WageyUsageBar(used: 5, limit: 40)
    WageyUsageBar(used: 20, limit: 40)
    WageyUsageBar(used: 32, limit: 40)
    WageyUsageBar(used: 40, limit: 40)
  }
  .padding()
  .background(Color.tidexBackground)
}
