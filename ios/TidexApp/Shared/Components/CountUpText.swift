// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_types_order identifier_name no_magic_numbers number_separator
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_contents_order
import SwiftUI

/// Currency-formatted rolling text using the user's selected currency
/// Uses SwiftUI's built-in content transition for smooth digit animations
struct CurrencyCountUpText: View {
  let amount: Double
  let duration: Double
  let animateOnAppear: Bool
  let animateChanges: Bool
  /// Optional starting value to animate FROM (useful when view may be recreated)
  let animateFrom: Double?

  @Environment(\.userCurrency) private var currency

  /// Track the displayed amount for animation
  @State private var displayedAmount: Double?
  /// Track if this is the initial appear
  @State private var hasAppeared = false

  init(
    amount: Double,
    duration: Double = 1.0,
    animateOnAppear: Bool = true,
    animateChanges: Bool = true,
    animateFrom: Double? = nil
  ) {
    self.amount = amount
    self.duration = duration
    self.animateOnAppear = animateOnAppear
    self.animateChanges = animateChanges
    self.animateFrom = animateFrom
  }

  private var formattedText: String {
    CurrencyConfig.format(displayedAmount ?? amount, currency: currency)
  }

  private func formattedText(for amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  var body: some View {
    Text(formattedText)
      .contentTransition(.numericText(value: displayedAmount ?? amount))
      .accessibilityLabel(CurrencyConfig.format(amount, currency: currency))
      .onAppear {
        if !hasAppeared {
          hasAppeared = true
          // Use animateFrom if provided (for recreated views), otherwise 0 or immediate
          let startValue = animateFrom ?? (animateOnAppear ? 0 : amount)
          if animateOnAppear || animateFrom != nil {
            displayedAmount = startValue
            // Only animate if we're not already at the target
            if startValue != amount {
              withAnimation(.spring(duration: duration, bounce: 0).delay(0.05)) {
                displayedAmount = amount
              }
            }
          } else {
            displayedAmount = amount
          }
        }
      }
      .onChange(of: amount) { _, newValue in
        guard formattedText(for: displayedAmount ?? amount) != formattedText(for: newValue) else {
          var transaction = Transaction()
          transaction.animation = nil
          withTransaction(transaction) {
            displayedAmount = newValue
          }
          return
        }

        if animateChanges {
          withAnimation(.spring(duration: duration, bounce: 0)) {
            displayedAmount = newValue
          }
        } else {
          displayedAmount = newValue
        }
      }
  }
}

// MARK: - Previews

#Preview("Currency") {
  VStack(spacing: Spacing.lg) {
    CurrencyCountUpText(amount: 24_650)
      .font(.system(size: 48, weight: .bold))
      .foregroundColor(.tidexBlue)

    CurrencyCountUpText(amount: 31_200)
      .font(.system(size: 48, weight: .bold))
      .foregroundColor(.tidexSuccess)
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Large Number") {
  CurrencyCountUpText(amount: 156_789)
    .font(.system(size: 72, weight: .bold))
    .foregroundColor(.tidexBlue)
    .padding()
    .background(Color.tidexBackground)
}

#Preview("Value Changes") {
  struct ValueChangePreview: View {
    @State private var amount: Double = 1_234

    var body: some View {
      VStack(spacing: Spacing.lg) {
        CurrencyCountUpText(amount: amount)
          .font(.system(size: 48, weight: .bold))
          .foregroundColor(.tidexBlue)

        HStack(spacing: Spacing.md) {
          Button("-500") { amount = max(0, amount - 500) }
          Button("+500") { amount += 500 }
          Button("Random") { amount = Double.random(in: 1_000...50_000) }
        }
        .buttonStyle(.bordered)
      }
      .padding()
      .background(Color.tidexBackground)
    }
  }

  return ValueChangePreview()
}
