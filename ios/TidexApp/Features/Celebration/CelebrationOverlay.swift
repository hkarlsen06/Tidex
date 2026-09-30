import SwiftUI
import UIKit

/// Celebration sheet shown after a shift completes or on payday, presented as a growing bottom sheet
struct CelebrationOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dismiss) private var dismiss

  let data: CelebrationData

  @State private var displayedAmount: Double
  @State private var showCard = false
  @State private var sheetDetent: PresentationDetent

  private static let compactContentHeight: CGFloat =
    24 + 8 + 88 + 8 + 20  // header: label + spacing + number + spacing + subtitle
    + 24  // spacing before button
    + 56 + 12  // button height + bottom padding

  private static let messageExtraHeight: CGFloat = 24 + 24 + 16  // spacing + message text
  private static let cardExtraHeight: CGFloat = 140 + 16  // card + spacing

  private static let compactDetent: PresentationDetent = .height(compactContentHeight)

  private var expandedDetent: PresentationDetent {
    .height(
      Self.compactContentHeight + Self.messageExtraHeight
        + (data.featuredShift == nil ? 0 : Self.cardExtraHeight))
  }

  private var isPayday: Bool {
    data.message == .payday
  }

  private var isMonthRecord: Bool {
    data.message == .bestShiftThisMonth
  }

  private var messageText: LocalizedStringResource {
    switch data.message {
    case .firstShiftThisMonth: .celebrationMessageFirstShift
    case .bestShiftThisMonth: .celebrationMessageBestShift
    case .greatJob: .celebrationGreatJob
    case .niceWork: .celebrationMessageNiceWork
    case .wellEarned: .celebrationMessageWellEarned
    case .keepItUp: .celebrationMessageKeepItUp
    case .payday: .celebrationPaydayMessage
    }
  }

  init(data: CelebrationData) {
    self.data = data
    let animateFromValue: Double
    if let animateFrom = data.animateFrom {
      animateFromValue = animateFrom
    } else if abs(data.previousDisplayValue - data.newDisplayValue) <= 0.01 {
      animateFromValue = 0
    } else {
      animateFromValue = data.previousDisplayValue
    }
    _displayedAmount = State(initialValue: animateFromValue)
    _sheetDetent = State(initialValue: Self.compactDetent)
  }

  private var contentMaxWidth: CGFloat {
    horizontalSizeClass == .regular ? AdaptiveMaxWidth.tabContent : .infinity
  }

  /// The fixed-height detents only fit regular text sizes. At accessibility sizes the sheet
  /// is full height and its content scrolls.
  private var usesAdaptiveLayout: Bool {
    dynamicTypeSize.isAccessibilitySize
  }

  /// Skips the timed reveal for people who use Reduce Motion or VoiceOver.
  private var skipsReveal: Bool {
    reduceMotion || voiceOverEnabled
  }

  private var detentSelection: Binding<PresentationDetent> {
    usesAdaptiveLayout ? .constant(.large) : $sheetDetent
  }

  var body: some View {
    Group {
      if usesAdaptiveLayout {
        ScrollView {
          content
        }
      } else {
        content
      }
    }
    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: showCard)
    .task {
      Haptics.play(.success)

      if skipsReveal {
        displayedAmount = data.newDisplayValue
        showCard = true
        sheetDetent = expandedDetent
        AccessibilityNotification.LayoutChanged().post()
      } else {
        // Start count-up after the sheet slides in
        try? await Task.sleep(for: .seconds(0.5))
        withAnimation(.spring(duration: 1.0, bounce: 0)) {
          displayedAmount = data.newDisplayValue
        }

        // Show card after count-up completes (with a brief pause)
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
          showCard = true
          sheetDetent = expandedDetent
        }
        AccessibilityNotification.LayoutChanged().post()
      }
    }
    .userCurrency(data.currency)
    .presentationDetents(
      usesAdaptiveLayout ? [.large] : [Self.compactDetent, expandedDetent],
      selection: detentSelection
    )
    .presentationDragIndicator(.visible)
    .presentationBackground(Color.tidexBackground)
  }

  private var content: some View {
    VStack(spacing: 0) {  // swiftlint:disable:this closure_body_length
      // Header with large number
      VStack(spacing: Spacing.sm) {
        Text(isPayday ? .celebrationPaydayTitle : .celebrationYouEarned)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextSecondary)
          .accessibilityAddTraits(.isHeader)

        // Large amount - same size as TotalCard (88pt) at regular sizes. At accessibility sizes it
        // uses a smaller base font and wraps instead of shrinking.
        Text(CurrencyConfig.format(displayedAmount, currency: data.currency))
          .font(usesAdaptiveLayout ? .tidexAmountLarge : .tidexHeroAmount)
          .foregroundColor(.tidexBlueText)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(usesAdaptiveLayout ? 1 : 0.4)
          .lineLimit(usesAdaptiveLayout ? nil : 1)
          .contentTransition(.numericText(value: displayedAmount))
          // The visible number counts up, so speak the final amount from the start.
          .accessibilityLabel(CurrencyConfig.format(data.newDisplayValue, currency: data.currency))

        Text(isPayday ? .celebrationPaydaySubtitle : .celebrationSoFarThisMonth)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.top, Spacing.sm)
      .frame(maxWidth: contentMaxWidth)
      .frame(maxWidth: .infinity)

      // Expandable content - card and closing message
      if showCard {
        VStack(spacing: Spacing.md) {
          if let featuredShift = data.featuredShift {
            FeaturedShiftCard(
              shift: featuredShift,
              isToday: false,
              isBestShift: isMonthRecord,
              countdownText: nil,
              progress: nil,
              showIncreaseHighlight: true,
              showFooter: isMonthRecord
            )
          }

          Text(messageText)
            .font(.tidexHeadline)
            .foregroundColor(.tidexTextPrimary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xl)  // More gap to differentiate sections
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }

      Spacer(minLength: showCard ? 16 : 24)

      // Dismiss button
      Button {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
      } label: {
        Text(.celebrationContinue)
          .font(.tidexButton)
          .frame(maxWidth: .infinity)
          .frame(minHeight: Spacing.buttonHeight)
          .background(Color.tidexBrandPrimary)
          .foregroundColor(.tidexTextOnBrand)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxxl, style: .continuous))
      }
      .buttonStyle(CelebrationButtonStyle())
      .frame(maxWidth: contentMaxWidth)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, Spacing.md)
      .padding(.bottom, Spacing.sm)
    }
  }
}

// MARK: - Button Style

private struct CelebrationButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
      .opacity(configuration.isPressed ? 0.9 : 1.0)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

// MARK: - Preview

private let previewCelebrationData = CelebrationData(
  previousDisplayValue: 12_000,
  newDisplayValue: 14_500,
  featuredShift: ShiftWithComputations(
    shift: ShiftRow(
      id: "preview",
      user_id: nil,
      shift_date: "2025-02-03",
      start_time: "09:00",
      end_time: "17:00",
      custom_supplements: nil,
      created_at: nil
    ),
    computed: ShiftComputed(
      id: "preview",
      durationHours: 8,
      paidHours: 7.5,
      basePay: 1_200,
      supplementPay: 300,
      gross: 1_500,
      wagePeriods: [],
      originalWagePeriods: [],
      breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
    ),
    taxEnabled: false,
    taxPercentage: 0
  ),
  completedShiftCount: 1,
  currency: "kr",
  animateFrom: 12_000,
  message: .bestShiftThisMonth
)

private struct CelebrationOverlayPreview: View {
  @State private var isPresented = true

  var body: some View {
    Color.tidexBackground
      .ignoresSafeArea()
      .sheet(isPresented: $isPresented) {
        CelebrationOverlay(data: previewCelebrationData)
      }
  }
}

#Preview {
  CelebrationOverlayPreview()
}
