import SwiftUI

/// Step progression state for visual hierarchy
enum StepProgressState {
  case active  // Step 1: Full opacity, checkmark pulse
  case upcoming  // Step 2: Slightly dimmed
  case future  // Step 3: More subtle

  var contentOpacity: Double {
    switch self {
    case .active: return 1.0
    case .upcoming: return 0.8
    case .future: return 0.65
    }
  }

  var iconBackgroundOpacity: Double {
    switch self {
    case .active: return 0.2
    case .upcoming: return 0.16
    case .future: return 0.12
    }
  }
}

/// Individual step item for the "How It Works" screen
/// Supports visual hierarchy through progress states
struct StepItem: View {
  let icon: String
  let title: String
  let description: String
  let index: Int
  let isVisible: Bool
  let progressState: StepProgressState
  let showConnector: Bool  // Show line to next step

  @State private var showCheckPulse = false

  // Stagger delays: 0ms, 120ms, 240ms
  private var entranceDelay: Double {
    Double(index) * 0.12
  }

  private let iconSize: CGFloat = 44
  private let connectorHeight: CGFloat = 20

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      // Left column: Icon + connector line (vertically stacked, centered)
      VStack(spacing: 0) {
        // Icon circle with optional check pulse
        ZStack {
          Circle()
            .fill(Color.tidexBlue.opacity(progressState.iconBackgroundOpacity))
            .frame(width: iconSize, height: iconSize)

          // Checkmark pulse ring (only for active step)
          if progressState == .active && showCheckPulse {
            Circle()
              .stroke(Color.tidexBlue.opacity(0.3), lineWidth: 2)
              .frame(width: iconSize, height: iconSize)
              .scaleEffect(showCheckPulse ? 1.3 : 1.0)
              .opacity(showCheckPulse ? 0 : 1)
          }

          Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.tidexBlue)
            .opacity(progressState.contentOpacity)
        }

        // Connector line below icon
        if showConnector {
          Rectangle()
            .fill(Color.tidexBlue.opacity(0.15))
            .frame(width: 2, height: connectorHeight)
            .opacity(isVisible ? 1 : 0)
            .animation(
              .easeOut(duration: 0.4).delay(entranceDelay + 0.2),
              value: isVisible
            )
        }
      }
      .frame(width: iconSize)

      // Right column: Text content (vertically centered to icon)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.tidexTextPrimary)
          .opacity(progressState.contentOpacity)

        Text(description)
          .font(.system(size: 14))
          .foregroundColor(.tidexTextSecondary)
          .opacity(progressState.contentOpacity * 0.9)
      }
      .frame(minHeight: iconSize, alignment: .center)

      Spacer(minLength: 0)
    }
    .opacity(isVisible ? 1 : 0)
    .offset(y: isVisible ? 0 : 20)
    .animation(
      .spring(response: 0.4, dampingFraction: 0.8)
        .delay(entranceDelay),
      value: isVisible
    )
    .onChange(of: isVisible) { _, visible in
      // Trigger checkmark pulse for active step after entrance
      if visible && progressState == .active {
        DispatchQueue.main.asyncAfter(deadline: .now() + entranceDelay + 0.3) {
          withAnimation(.easeOut(duration: 0.6)) {
            showCheckPulse = true
          }
        }
      }
    }
  }
}

// MARK: - Convenience initializer for backward compatibility
extension StepItem {
  init(icon: String, title: String, description: String, index: Int, isVisible: Bool) {
    self.icon = icon
    self.title = title
    self.description = description
    self.index = index
    self.isVisible = isVisible
    self.progressState = .active
    self.showConnector = false
  }
}

#Preview("Progression Timeline") {
  VStack(spacing: 0) {
    StepItem(
      icon: "clock.badge.checkmark",
      title: "Log your shift",
      description: "Add start time, end time, done",
      index: 0,
      isVisible: true,
      progressState: .active,
      showConnector: true
    )

    StepItem(
      icon: "banknote",
      title: "See your earnings",
      description: "Wages calculated automatically",
      index: 1,
      isVisible: true,
      progressState: .upcoming,
      showConnector: true
    )

    StepItem(
      icon: "chart.line.uptrend.xyaxis",
      title: "Track your month",
      description: "Dashboard shows your progress",
      index: 2,
      isVisible: true,
      progressState: .future,
      showConnector: false
    )
  }
  .padding(.horizontal, 24)
  .frame(maxHeight: .infinity)
  .background(Color.tidexBackground)
}
