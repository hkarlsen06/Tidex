import SwiftUI

/// Progress bar showing Wagey message usage
/// - Blue: < 75% used
/// - Yellow: 75-99% used
/// - Red: 100% used (limit reached)
struct WageyUsageBar: View {
  /// Number of messages used this month
  let used: Int

  /// Total message limit
  let limit: Int

  /// Calculated progress (0.0 to 1.0)
  private var progress: Double {
    guard limit > 0 else { return 0 }
    return min(Double(used) / Double(limit), 1.0)
  }

  /// Color based on usage percentage
  private var progressColor: Color {
    switch progress {
    case 0..<0.75:
      return .tidexBlue
    case 0.75..<1.0:
      return .tidexWarning
    default:
      return .tidexError
    }
  }

  /// Background color for the track
  private var trackColor: Color {
    progressColor.opacity(0.15)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        // Track
        RoundedRectangle(cornerRadius: 2)
          .fill(trackColor)
          .frame(height: 4)

        // Progress
        RoundedRectangle(cornerRadius: 2)
          .fill(progressColor)
          .frame(width: geometry.size.width * progress, height: 4)
          .animation(.easeInOut(duration: 0.3), value: progress)
      }
    }
    .frame(height: 4)
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
