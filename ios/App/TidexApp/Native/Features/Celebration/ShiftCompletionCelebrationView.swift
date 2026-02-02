import SwiftUI
import UIKit

struct ShiftCompletionCelebrationView: View {
    let data: CelebrationData
    let onDismiss: () -> Void

    
    @State private var showConfetti = false
    @State private var showCard = false
    @State private var showButton = false
    @State private var hapticTask: Task<Void, Never>?
    @State private var animationsCompleted = false

    private var badgeText: String? {
        guard data.completedShiftCount > 1 else { return nil }
        return String(localized: .celebrationShiftsCompleted(Int32(data.completedShiftCount)))
    }

    private var animateFromValue: Double? {
        data.animateFrom ?? data.previousDisplayValue
    }

    private var shouldAnimateNumber: Bool {
        let startValue = animateFromValue ?? data.newDisplayValue
        return abs(startValue - data.newDisplayValue) > 0.01
    }

    var body: some View {
        ZStack {
            Color.tidexBackground
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        Spacer(minLength: 0)

                        VStack(spacing: Spacing.sm) {
                            Text(.celebrationYouEarned)
                                .font(.tidexHeadline)
                                .foregroundColor(.tidexTextSecondary)

                            CurrencyCountUpText(
                                amount: data.newDisplayValue,
                                duration: 1.0,
                                animateOnAppear: true,
                                animateChanges: false,
                                animateFrom: animateFromValue
                            )
                            .font(.system(size: 104, weight: .bold))
                            .foregroundColor(.tidexBlue)
                            .minimumScaleFactor(0.32)
                            .lineLimit(1)

                            Text(.celebrationSoFarThisMonth)
                                .font(.tidexSubheadline)
                                .foregroundColor(.tidexTextMuted)
                        }
                        .multilineTextAlignment(.center)

                        Spacer(minLength: Spacing.lg)

                        VStack(spacing: Spacing.lg) {
                            if let badgeText {
                                Text(badgeText)
                                    .font(.tidexCaptionStrong)
                                    .foregroundColor(.tidexBlue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.tidexBlue.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            FeaturedShiftCard(
                                shift: data.featuredShift,
                                isToday: false,
                                isBestShift: true,
                                countdownText: nil,
                                progress: nil
                            )
                            .opacity(showCard ? 1 : 0)
                            .offset(y: showCard ? 0 : 24)
                            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: showCard)

                            Text(.celebrationGreatJob)
                                .font(.tidexHeadline)
                                .foregroundColor(.tidexTextPrimary)
                                .padding(.top, Spacing.sm)
                        }

                        Spacer(minLength: Spacing.lg)
                    }
                    .frame(minHeight: proxy.size.height - (Spacing.buttonHeight + Spacing.lg + Spacing.md))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.cardPadding)
                    .padding(.vertical, Spacing.lg)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: String(localized: .celebrationContinue)) {
                onDismiss()
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.bottom, Spacing.md)
            .opacity(showButton ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: showButton)
            .allowsHitTesting(showButton)
        }
        .overlay {
            ConfettiView(isActive: showConfetti) {
                showConfetti = false
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            skipAnimations()
        }
        .onAppear {
            scheduleAnimations()
        }
        .onDisappear {
            hapticTask?.cancel()
            hapticTask = nil
        }
        .userCurrency(data.currency)
    }

    private func scheduleAnimations() {
        showConfetti = false
        showCard = false
        showButton = false

        hapticTask?.cancel()
        hapticTask = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showConfetti = true
        }

        if shouldAnimateNumber {
            hapticTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                let ticks = 10
                for _ in 0..<ticks {
                    if Task.isCancelled { return }
                    generator.impactOccurred(intensity: 0.6)
                    try? await Task.sleep(nanoseconds: 90_000_000)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                showCard = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showButton = true
            }
            animationsCompleted = true
        }
    }

    private func skipAnimations() {
        guard !animationsCompleted else { return }
        animationsCompleted = true

        hapticTask?.cancel()
        hapticTask = nil

        withAnimation(.easeInOut(duration: 0.2)) {
            showCard = true
            showButton = true
        }
    }
}

#Preview {
    ShiftCompletionCelebrationView(
        data: CelebrationData(
            previousDisplayValue: 12000,
            newDisplayValue: 16500,
            featuredShift: ShiftWithComputations(
                shift: ShiftRow(
                    id: "preview",
                    user_id: nil,
                    shift_date: todayISO(),
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
                    supplementPay: 200,
                    gross: 1400,
                    wagePeriods: [],
                    originalWagePeriods: [],
                    breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
                ),
                taxEnabled: false,
                taxPercentage: 0
            ),
            completedShiftCount: 3,
            currency: "kr",
            animateFrom: 12000
        ),
        onDismiss: {}
    )
}
