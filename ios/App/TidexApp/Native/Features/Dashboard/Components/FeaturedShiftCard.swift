import SwiftUI

/// Card displaying a featured shift
/// - For current month: shows next upcoming shift with countdown
/// - For other months: shows best shift (highest earnings)
/// Design matches ShiftCard from the Next.js app
struct FeaturedShiftCard: View {
    let shift: ShiftWithComputations
    let isToday: Bool
    let isBestShift: Bool  // true = showing best shift, false = showing next shift
    let countdownText: String?  // Countdown text shown below the card
    /// Progress through the shift (0-100), shows a subtle progress bar when provided (for active shifts)
    var progress: Double?

    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    /// Animated progress value for smooth entrance animation
    @State private var animatedProgress: Double = 0

    // MARK: - Computed Properties

    private var showBreakdown: Bool {
        shift.taxEnabled && shift.taxAmount > 0
    }

    private var formattedHours: String {
        ShiftCardFormatter.formattedHours(shift.paidHours, locale: localization.currentLocale)
    }

    private var dateParts: ShiftCardDateParts {
        ShiftCardFormatter.dateParts(for: shift.shiftDate, locale: localization.currentLocale)
    }

    /// Footer label shown below the card - "Best shift" or countdown text
    private var footerText: String? {
        if isBestShift {
            return localization.string("dashboard.bestShift")
        }
        return countdownText
    }

    /// Whether to show the progress bar (valid progress between 0-100)
    private var hasProgress: Bool {
        guard let progress = progress else { return false }
        return progress >= 0 && progress <= 100
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            // Main card content
            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Date (left) and earnings amount (right) - center aligned
                HStack(alignment: .center) {
                    // Day name and date
                    HStack(spacing: 4) {
                        Text(dateParts.dayName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)
                        Text("·")
                            .foregroundColor(.tidexTextMuted)
                        Text("\(dateParts.dayNumber) \(dateParts.monthName)")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.tidexTextMuted)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()

                    // Net/gross amount
                    let displayAmount = shift.taxEnabled ? shift.netPay : shift.grossPay
                    Text(formatCurrency(displayAmount))
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(.tidexTextPrimary)
                }

                // Row 2: Time range (left) and breakdown (right) - center aligned
                HStack(alignment: .center) {
                    // Time range and hours
                    HStack(spacing: 8) {
                        // Time with clock icon
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.tidexTextMuted)
                            Text("\(shift.startTime)–\(shift.endTime)")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.tidexTextPrimary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        // Arrow and hours combined
                        Text("→ \(formattedHours)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.tidexTextMuted)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Spacer()

                    // Breakdown (gross - tax) when tax enabled
                    if showBreakdown {
                        HStack(spacing: 4) {
                            Text(formatPlainAmount(shift.grossPay))
                            Text("−")
                            Text(formatPlainAmount(shift.taxAmount))
                        }
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.tidexTextMuted)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(Color.tidexSurfacePrimary)
            .overlay(alignment: .leading) {
                // Progress bar overlay - fills from left based on progress (for active shifts)
                // Uses Rectangle instead of RoundedRectangle so small widths don't overflow
                // The clipShape on the parent handles the rounded corners
                if hasProgress {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.tidexBlue.opacity(0.1))
                            .frame(width: geometry.size.width * (animatedProgress / 100))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .tidexCardShadow()
            .onChange(of: progress) { _, newValue in
                // Animate to new progress value
                withAnimation(.linear(duration: 1.0)) {
                    animatedProgress = newValue ?? 0
                }
            }
            .onAppear {
                // Animate from 0 to current progress on appear (matches CSS animation)
                if let progress = progress, progress >= 0, progress <= 100 {
                    withAnimation(.linear(duration: 1.0)) {
                        animatedProgress = progress
                    }
                }
            }

            // Footer text below the card (countdown or "Best shift")
            // Uses fixed height to prevent layout shift during transitions
            HStack(spacing: 6) {
                if isBestShift {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.tidexBlue)
                }
                Text(footerText ?? " ")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
            }
            .opacity(footerText != nil ? 1 : 0)
            .frame(height: 20) // Fixed height prevents vertical jerk
        }
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }

    /// Format amount without currency symbol (for breakdown display)
    private func formatPlainAmount(_ amount: Double) -> String {
        CurrencyConfig.formatPlain(amount)
    }
}

// Preview disabled - requires full app context
// #Preview {
//     VStack(spacing: 16) {
//         FeaturedShiftCard(shift: mockShift, isToday: true, isBestShift: false)
//         FeaturedShiftCard(shift: mockShift, isToday: false, isBestShift: true)
//     }
// }
