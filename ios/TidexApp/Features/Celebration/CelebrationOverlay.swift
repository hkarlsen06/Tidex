import SwiftUI
import UIKit

/// Compact celebration overlay that slides up from the bottom
struct CelebrationOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let data: CelebrationData
  let onDismiss: () -> Void

  @State private var dragOffset: CGFloat = 0
  @State private var showContent = false
  @State private var startCountUp = false
  @State private var showCard = false

  private var animateFromValue: Double {
    if let animateFrom = data.animateFrom {
      return animateFrom
    }
    if abs(data.previousDisplayValue - data.newDisplayValue) <= 0.01 {
      return 0
    }
    return data.previousDisplayValue
  }

  // Compact height: drag indicator + header + button + padding
  private let compactContentHeight: CGFloat =
    10 + 5 + 20  // drag indicator with padding
    + 24 + 8 + 88 + 8 + 20  // header: label + spacing + number + spacing + subtitle
    + 24  // spacing before button
    + 56 + 12  // button height + bottom padding (before safe area)

  // Extra height when card is shown: top spacing + card (~140) + spacing + great job text
  private let expandedExtraHeight: CGFloat = 24 + 140 + 16 + 24 + 16

  var body: some View {
    GeometryReader { geometry in
      let safeBottom = geometry.safeAreaInsets.bottom
      let compactHeight = compactContentHeight + safeBottom
      let expandedHeight = compactContentHeight + expandedExtraHeight + safeBottom
      let currentHeight = showCard ? expandedHeight : compactHeight

      ZStack(alignment: .bottom) {
        // Dimmed background
        Color.black
          .opacity(showContent ? 0.35 : 0)
          .ignoresSafeArea()
          .onTapGesture {
            dismiss()
          }

        // Overlay card
        VStack(spacing: 0) {
          // Drag indicator
          Capsule()
            .fill(Color.tidexTextMuted.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, Spacing.xsm)
            .padding(.bottom, Spacing.mlg)

          // Header with large number
          VStack(spacing: Spacing.sm) {
            Text(.celebrationYouEarned)
              .font(.tidexHeadline)
              .foregroundColor(.tidexTextSecondary)

            // Large amount - same size as TotalCard (88pt)
            // Uses SteppingCountUpText for smooth rolling digit animation
            SteppingCountUpText(
              startValue: animateFromValue,
              endValue: data.newDisplayValue,
              duration: 1.0,
              currency: data.currency,
              isAnimating: startCountUp
            )
            .font(.tidexHeroAmount)
            .foregroundColor(.tidexBlue)
            .minimumScaleFactor(0.4)
            .lineLimit(1)

            Text(.celebrationSoFarThisMonth)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextMuted)
          }
          .padding(.horizontal, Spacing.md)

          // Expandable content - card and "great job"
          if showCard {
            VStack(spacing: Spacing.md) {
              FeaturedShiftCard(
                shift: data.featuredShift,
                isToday: false,
                isBestShift: true,
                countdownText: nil,
                progress: nil,
                showIncreaseHighlight: true
              )

              Text(.celebrationGreatJob)
                .font(.tidexHeadline)
                .foregroundColor(.tidexTextPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xl)  // More gap to differentiate sections
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
          .padding(.horizontal, Spacing.md)
          .padding(.bottom, safeBottom + Spacing.sm)
        }
        .frame(height: currentHeight)
        .frame(maxWidth: .infinity)
        .background(
          Color.tidexBackground
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 20, y: -5)
        )
        .offset(y: showContent ? dragOffset : currentHeight)
        .gesture(
          DragGesture()
            .onChanged { value in
              if value.translation.height > 0 {
                dragOffset = value.translation.height
              }
            }
            .onEnded { value in
              if value.translation.height > 80 || value.predictedEndTranslation.height > 200 {
                dismiss()
              } else {
                if reduceMotion {
                  dragOffset = 0
                } else {
                  withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragOffset = 0
                  }
                }
              }
            }
        )
      }
      .ignoresSafeArea(edges: .bottom)
    }
    .animation(
      reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: showContent
    )
    .animation(
      reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: dragOffset
    )
    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: showCard)
    .onAppear {
      showContent = true
      Haptics.play(.success)

      if reduceMotion {
        startCountUp = true
        showCard = true
      } else {
        // Start count-up after overlay slides in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          startCountUp = true
        }

        // Show card after count-up completes (with a brief pause)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
          showCard = true
        }
      }
    }
    .userCurrency(data.currency)
  }

  private func dismiss() {
    showContent = false
    dragOffset = 0
    if reduceMotion {
      onDismiss()
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        onDismiss()
      }
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

// MARK: - Stepping Count Up Text

/// Counts up from startValue to endValue by stepping through intermediate values
/// This ensures all digits roll properly as the number increments
private struct SteppingCountUpText: View {
  let startValue: Double
  let endValue: Double
  let duration: Double
  let currency: String
  let isAnimating: Bool

  @State private var currentValue: Double
  @State private var animationTask: Task<Void, Never>?

  /// Formatter without thousands separator for cleaner rolling digit display
  private static let compactFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.maximumFractionDigits = 0
    formatter.minimumFractionDigits = 0
    return formatter
  }()

  init(startValue: Double, endValue: Double, duration: Double, currency: String, isAnimating: Bool)
  {
    self.startValue = startValue
    self.endValue = endValue
    self.duration = duration
    self.currency = currency
    self.isAnimating = isAnimating
    _currentValue = State(initialValue: startValue)
  }

  /// Format amount without thousands separator, with currency suffix
  private func formatCompact(_ amount: Double) -> String {
    let formatted = Self.compactFormatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    return "\(formatted) \(currency)"
  }

  var body: some View {
    CountUpText(
      targetValue: currentValue,
      duration: 0.12,  // Short duration for smooth rolling between steps
      animateOnAppear: false,
      animateChanges: true,
      format: formatCompact
    )
    .onChange(of: isAnimating) { _, shouldAnimate in
      if shouldAnimate {
        startAnimation()
      }
    }
    .onDisappear {
      animationTask?.cancel()
      animationTask = nil
    }
  }

  private func startAnimation() {
    animationTask?.cancel()
    currentValue = startValue

    // Calculate number of steps based on duration
    let steps = max(12, min(60, Int(duration * 30)))
    let stepDuration = duration / Double(steps)

    animationTask = Task { @MainActor in
      for step in 1...steps {
        if Task.isCancelled { return }
        let progress = Double(step) / Double(steps)
        let eased = easeOutCubic(progress)
        currentValue = startValue + (endValue - startValue) * eased
        try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
      }
      currentValue = endValue
    }
  }

  private func easeOutCubic(_ t: Double) -> Double {
    let p = max(0.0, min(1.0, t))
    return 1 - pow(1 - p, 3)
  }
}

#Preview {
  ZStack {
    Color.tidexBackground.ignoresSafeArea()

    CelebrationOverlay(
      data: CelebrationData(
        previousDisplayValue: 12000,
        newDisplayValue: 14500,
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
            basePay: 1200,
            supplementPay: 300,
            gross: 1500,
            wagePeriods: [],
            originalWagePeriods: [],
            breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
          ),
          taxEnabled: false,
          taxPercentage: 0
        ),
        completedShiftCount: 1,
        currency: "kr",
        animateFrom: 12000
      ),
      onDismiss: {}
    )
  }
}
