// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image closure_body_length conditional_returns_on_newline explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface no_magic_numbers type_contents_order
import SwiftUI
import UIKit

// MARK: - Calendar View Mode Toggle

/// Reusable hours/money toggle bar for calendar views
/// Uses glass effect for selected state
struct CalendarViewModeToggle: View {
  private let controlHeight: CGFloat = 44
  private let controlInset: CGFloat = Spacing.xxs
  @Binding var viewMode: CalendarViewMode
  let currency: String
  let showMoneyOption: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // Haptic feedback
  private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)

  init(
    viewMode: Binding<CalendarViewMode>,
    currency: String,
    showMoneyOption: Bool = true
  ) {
    self._viewMode = viewMode
    self.currency = currency
    self.showMoneyOption = showMoneyOption
  }

  var body: some View {
    ZStack {
      Capsule()
        .fill(Color.tidexSurfaceSecondary.opacity(0.55))

      GeometryReader { geometry in
        let innerWidth = max(0, geometry.size.width - (controlInset * 2))
        let segmentCount: CGFloat = showMoneyOption ? 2 : 1
        let segmentWidth = innerWidth / segmentCount
        let selectedIndex: CGFloat = viewMode == .money && showMoneyOption ? 1 : 0

        Capsule()
          .fill(Color.clear)
          .tidexGlass(
            shape: .capsule,
            tint: .tidexGlassSurface.opacity(0.32),
            interactive: true
          )
          .frame(width: segmentWidth, height: controlHeight)
          .offset(x: controlInset + (selectedIndex * segmentWidth), y: controlInset)
          .animation(
            reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8),
            value: selectedIndex
          )
      }

      HStack(spacing: 0) {
        // Hours button
        Button {
          guard viewMode != .hours else { return }
          toggleHaptic.impactOccurred()
          if reduceMotion {
            viewMode = .hours
            viewMode.save()
          } else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
              viewMode = .hours
              viewMode.save()
            }
          }
        } label: {
          HStack(spacing: Spacing.xxxs) {
            Image(systemName: "clock.fill")
              .font(.tidexLabel)
            Text(.shiftsCalendarToggleHours)
              .font(viewMode == .hours ? .tidexLabelStrong : .tidexSubheadline)
          }
          .foregroundColor(viewMode == .hours ? .tidexTextPrimary : .tidexTextMuted)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.sm)
          .frame(height: controlHeight)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        // Money button (only if showing earnings)
        if showMoneyOption {
          Button {
            guard viewMode != .money else { return }
            toggleHaptic.impactOccurred()
            if reduceMotion {
              viewMode = .money
              viewMode.save()
            } else {
              withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewMode = .money
                viewMode.save()
              }
            }
          } label: {
            HStack(spacing: Spacing.xxxs) {
              Image(systemName: "banknote.fill")
                .font(.tidexLabel)
              Text(.shiftsCalendarToggleEarnings)
                .font(viewMode == .money ? .tidexLabelStrong : .tidexSubheadline)
            }
            .foregroundColor(viewMode == .money ? .tidexTextPrimary : .tidexTextMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .frame(height: controlHeight)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(controlInset)
    }
    .frame(height: controlHeight + (controlInset * 2))
    .onAppear {
      toggleHaptic.prepare()
    }
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.mlg) {
    CalendarViewModeToggle(
      viewMode: .constant(.hours),
      currency: "kr"
    )

    CalendarViewModeToggle(
      viewMode: .constant(.money),
      currency: "kr"
    )

    CalendarViewModeToggle(
      viewMode: .constant(.hours),
      currency: "kr",
      showMoneyOption: false
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
