import SwiftUI
import UIKit

/// Celebration sheet shown after a shift completes, presented as a growing bottom sheet
struct CelebrationOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

  private static let expandedExtraHeight: CGFloat = 24 + 140 + 16 + 24 + 16  // card + spacing + "great job" text

  private static let compactDetent: PresentationDetent = .height(compactContentHeight)
  private static let expandedDetent: PresentationDetent = .height(
    compactContentHeight + expandedExtraHeight)

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

  var body: some View {
    VStack(spacing: 0) {  // swiftlint:disable:this closure_body_length
      // Header with large number
      VStack(spacing: Spacing.sm) {
        Text(.celebrationYouEarned)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextSecondary)

        // Large amount - same size as TotalCard (88pt)
        Text(CurrencyConfig.format(displayedAmount, currency: data.currency))
          .font(.tidexHeroAmount)
          .foregroundColor(.tidexBlue)
          .minimumScaleFactor(0.4)
          .lineLimit(1)
          .contentTransition(.numericText(value: displayedAmount))

        Text(.celebrationSoFarThisMonth)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.top, Spacing.sm)
      .frame(maxWidth: contentMaxWidth)
      .frame(maxWidth: .infinity)

      // Expandable content - card and "great job"
      if showCard {
        VStack(spacing: Spacing.md) {
          FeaturedShiftCard(
            shift: data.featuredShift,
            isToday: false,
            isBestShift: false,
            countdownText: nil,
            progress: nil,
            showIncreaseHighlight: true,
            showFooter: false
          )

          Text(.celebrationGreatJob)
            .font(.tidexHeadline)
            .foregroundColor(.tidexTextPrimary)
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
          .frame(height: Spacing.buttonHeight)
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
    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: showCard)
    .task {
      Haptics.play(.success)

      if reduceMotion {
        displayedAmount = data.newDisplayValue
        showCard = true
        sheetDetent = Self.expandedDetent
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
          sheetDetent = Self.expandedDetent
        }
      }
    }
    .userCurrency(data.currency)
    .presentationDetents([Self.compactDetent, Self.expandedDetent], selection: $sheetDetent)
    .presentationDragIndicator(.visible)
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
  animateFrom: 12_000
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
