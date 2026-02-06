import SwiftUI
import UIKit

// MARK: - Calendar View Mode Toggle

/// Reusable hours/money toggle bar for calendar views
/// Uses glass effect for selected state
struct CalendarViewModeToggle: View {
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
        HStack(spacing: 6) {
          Text("--:--")
          Image(systemName: "clock")
            .font(.tidexCaptionStrong)
        }
        .font(viewMode == .hours ? .tidexLabelStrong : .tidexSubheadline)
        .foregroundColor(viewMode == .hours ? .tidexTextPrimary : .tidexTextMuted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .background(
          Group {
            if viewMode == .hours {
              Capsule()
                .fill(.clear)
                .tidexGlass(shape: .capsule, interactive: true)
            }
          }
        )
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
          Text("---- \(currency)")
            .font(viewMode == .money ? .tidexLabelStrong : .tidexSubheadline)
            .foregroundColor(viewMode == .money ? .tidexTextPrimary : .tidexTextMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
            .background(
              Group {
                if viewMode == .money {
                  Capsule()
                    .fill(.clear)
                    .tidexGlass(shape: .capsule, interactive: true)
                }
              }
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(Capsule().fill(Color.tidexSurfaceSecondary))
    .onAppear {
      toggleHaptic.prepare()
    }
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: 20) {
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
