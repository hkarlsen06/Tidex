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
  let isDimmedForFocus: Bool
  let titleFocusTrigger: Int

  @State private var showCheckPulse = false

  // Stagger delays: 0ms, 120ms, 240ms
  private var entranceDelay: Double {
    Double(index) * 0.12
  }

  private let iconSize: CGFloat = 44
  private let connectorHeight: CGFloat = 20

  var body: some View {
    let emphasisOpacity = isDimmedForFocus ? 0.5 : 1.0
    let descriptionOpacity = isDimmedForFocus ? 0.42 : 0.9
    let iconBackgroundOpacity = isDimmedForFocus ? 0.1 : 0.2

    HStack(alignment: .top, spacing: Spacing.md) {
      // Left column: Icon + connector line (vertically stacked, centered)
      VStack(spacing: 0) {
        // Icon circle with optional check pulse
        ZStack {
          Circle()
            .fill(Color.tidexBlue.opacity(iconBackgroundOpacity))
            .frame(width: iconSize, height: iconSize)

          // Checkmark pulse ring (only for active step)
          if progressState == .active, showCheckPulse {
            Circle()
              .stroke(Color.tidexBlue.opacity(0.3), lineWidth: 2)
              .frame(width: iconSize, height: iconSize)
              .scaleEffect(showCheckPulse ? 1.3 : 1.0)
              .opacity(showCheckPulse ? 0 : 1)
          }

          Image(systemName: icon)
            .font(.tidexHeadline)
            .foregroundColor(.tidexBlue)
            .opacity(emphasisOpacity)
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
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)
          .opacity(emphasisOpacity)
          .overlay(alignment: .bottomLeading) {
            GeometryReader { geometry in
              StepTitleFocusIndicator(
                trackWidth: max(geometry.size.width, 28),
                trigger: titleFocusTrigger,
                isVisible: isVisible
              )
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
              .offset(y: Spacing.xxxs + 1)
            }
          }
          .padding(.bottom, Spacing.xxxs + 2)

        Text(description)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .opacity(descriptionOpacity)
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
    .animation(.easeInOut(duration: 0.26), value: isDimmedForFocus)
    .onChange(of: isVisible) { _, visible in
      // Trigger checkmark pulse for active step after entrance
      if visible, progressState == .active {
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
    self.isDimmedForFocus = false
    self.titleFocusTrigger = 0
  }
}

private struct StepTitleFocusIndicator: View {
  let trackWidth: CGFloat
  let trigger: Int
  let isVisible: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var animationToken = 0
  @State private var leadingProgress: CGFloat = 0
  @State private var trailingProgress: CGFloat = 0
  @State private var indicatorOpacity: CGFloat = 0

  private let dotDiameter: CGFloat = 6
  private let lineHeight: CGFloat = 4
  private let expandDuration: TimeInterval = 0.54
  private let collapseDuration: TimeInterval = 0.58
  private let fadeOutDuration: TimeInterval = 0.18

  var body: some View {
    let travel = trackWidth - dotDiameter
    let startX = travel * leadingProgress
    let endX = travel * trailingProgress
    let width = max(dotDiameter, (endX - startX) + dotDiameter)

    Capsule(style: .continuous)
      .fill(Color.tidexBlue)
      .frame(width: width, height: lineHeight)
      .offset(x: startX)
      .frame(width: trackWidth, height: dotDiameter, alignment: .leading)
      .opacity(Double(indicatorOpacity) * (isVisible ? 1.0 : 0.0))
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onChange(of: trigger) { _, _ in
        runOneShot()
      }
      .onChange(of: isVisible) { _, visible in
        if !visible {
          resetHiddenState()
        }
      }
      .onDisappear {
        animationToken += 1
        resetHiddenState()
      }
  }

  private func resetHiddenState() {
    leadingProgress = 0
    trailingProgress = 0
    indicatorOpacity = 0
  }

  private func runOneShot() {
    animationToken += 1
    let token = animationToken
    leadingProgress = 0
    trailingProgress = 0
    indicatorOpacity = 1

    guard !reduceMotion else {
      withAnimation(.easeOut(duration: fadeOutDuration)) {
        indicatorOpacity = 0
      }
      return
    }

    withAnimation(.easeInOut(duration: expandDuration)) {
      trailingProgress = 1
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + expandDuration) {
      guard token == animationToken else { return }
      withAnimation(.easeInOut(duration: collapseDuration)) {
        leadingProgress = 1
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + expandDuration + collapseDuration) {
      guard token == animationToken else { return }
      withAnimation(.easeOut(duration: fadeOutDuration)) {
        indicatorOpacity = 0
      }
    }
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
      showConnector: true,
      isDimmedForFocus: false,
      titleFocusTrigger: 1
    )

    StepItem(
      icon: "banknote",
      title: "See your earnings",
      description: "Wages calculated automatically",
      index: 1,
      isVisible: true,
      progressState: .upcoming,
      showConnector: true,
      isDimmedForFocus: false,
      titleFocusTrigger: 0
    )

    StepItem(
      icon: "chart.line.uptrend.xyaxis",
      title: "Track your month",
      description: "Dashboard shows your progress",
      index: 2,
      isVisible: true,
      progressState: .future,
      showConnector: false,
      isDimmedForFocus: false,
      titleFocusTrigger: 0
    )
  }
  .padding(.horizontal, Spacing.lg)
  .frame(maxHeight: .infinity)
  .background(Color.tidexBackground)
}
