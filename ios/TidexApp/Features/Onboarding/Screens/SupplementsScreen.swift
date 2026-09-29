import SwiftUI

/// Screen for configuring custom supplement rules
/// Only shown for custom wage users
struct SupplementsScreen: View {
  @Bindable var data: OnboardingData
  let onContinue: () -> Void
  var onBack: (() -> Void)?  // swiftlint:disable:this explicit_acl

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showingRuleEditor = false
  @State private var editingRule: OnboardingSupplementRule?

  private var primaryButtonTitle: LocalizedStringResource {
    data.supplementRules.isEmpty ? .onboardingSupplementsSkip : .commonContinue
  }

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          scrollContent
        }

        // Bottom action
        OnboardingButton(
          title: String(localized: primaryButtonTitle),
          action: {
            Haptics.play(.success)
            onContinue()
          }
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xl)
        .adaptiveContentWidth()
      }
    }
    .sheet(isPresented: $showingRuleEditor) {
      SupplementRuleEditor(
        rule: editingRule,
        currency: data.currency,
        onSave: { savedRule in
          if let existingIndex = data.supplementRules.firstIndex(where: { $0.id == savedRule.id }) {
            data.supplementRules[existingIndex] = savedRule
          } else {
            data.supplementRules.append(savedRule)
          }
          showingRuleEditor = false
        },
        onCancel: {
          showingRuleEditor = false
        }
      )
    }
  }

  private var scrollContent: some View {
    VStack(spacing: 0) {
      // Back button (if provided)
      if let onBack {
        backButton(onBack)
      }

      Spacer()
        .frame(height: onBack != nil ? 24 : 60)

      header

      Spacer()
        .frame(height: 32)

      // Supplement rules list
      if !data.supplementRules.isEmpty {
        rulesList

        Spacer()
          .frame(height: 16)
      }

      addRuleButton

      // Info text when no rules
      if data.supplementRules.isEmpty {
        Spacer()
          .frame(height: 24)

        Text(.onboardingSupplementsHint)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Spacing.xl)
          .adaptiveContentWidth()
      }

      Spacer()
        .frame(height: 48)
    }
  }

  private func backButton(_ onBack: @escaping () -> Void) -> some View {
    HStack {
      Button(action: {
        Haptics.play(.light)
        onBack()
      }) {
        HStack(spacing: Spacing.xxs) {
          Image(systemName: "chevron.left")
            .font(.tidexButton)
            .accessibilityHidden(true)
          Text(.commonBack)
            .font(.tidexBody)
        }
        .foregroundColor(.tidexBlueText)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Spacer()
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.md)
    .adaptiveContentWidth()
  }

  private var header: some View {
    VStack(spacing: Spacing.sm) {
      Text(.onboardingSupplementsTitle)
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      Text(.onboardingSupplementsSubtitle)
        .font(.tidexBody)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, Spacing.xl)
    .adaptiveContentWidth()
  }

  private var rulesList: some View {
    VStack(spacing: Spacing.sm) {
      ForEach(data.supplementRules) { rule in
        SupplementRuleCard(
          rule: rule,
          locale: Locale.current,
          currency: data.currency,
          onEdit: {
            editingRule = rule
            showingRuleEditor = true
          },
          onDelete: {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
              data.supplementRules.removeAll { $0.id == rule.id }
            }
          }
        )
      }
    }
    .padding(.horizontal, Spacing.lg)
    .adaptiveContentWidth()
  }

  private var addRuleButton: some View {
    Button(action: {
      Haptics.play(.medium)
      editingRule = nil
      showingRuleEditor = true
    }) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "plus.circle.fill")
          .font(.title3)
          .accessibilityHidden(true)
        Text(.onboardingSupplementsAddRule)
          .font(.tidexBodyMedium)
          .multilineTextAlignment(.center)
      }
      .foregroundColor(.tidexBlueText)
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.xs)
      .frame(minHeight: 56)
      .background(Color.tidexBlue.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(Color.tidexBlue.opacity(0.3), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .padding(.horizontal, Spacing.lg)
    .adaptiveContentWidth()
  }
}

// MARK: - Supplement Rule Card

private struct SupplementRuleCard: View {
  let rule: OnboardingSupplementRule
  let locale: Locale
  let currency: String
  let onEdit: () -> Void
  let onDelete: () -> Void

  private var ruleSummary: String {
    "\(rule.spokenDaysDescription), \(rule.timeDescription)"
  }

  var body: some View {
    HStack(spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(rule.daysDescription)
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)

        HStack(spacing: Spacing.xs) {
          Text(rule.timeDescription)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)

          Text("•")
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextMuted)
            .accessibilityHidden(true)

          Text(rule.valueDescription(locale: locale, currency: currency))
            .font(.tidexLabel)
            .foregroundColor(.tidexSuccess)
        }
      }
      .accessibilityElement(children: .combine)

      Spacer()

      // Edit button
      Button(action: {
        Haptics.play(.light)
        onEdit()
      }) {
        Image(systemName: "pencil")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexBlueText)
          .accessibilityHidden(true)
          .frame(width: 36, height: 36)
          .background(Color.tidexBlue.opacity(0.1))
          .clipShape(Circle())
          .overlay(
            Circle()
              .stroke(Color.tidexBlue.opacity(0.3), lineWidth: 1)
          )
          .contentShape(Rectangle())
          .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.supplementsEditRuleAccessibility(ruleSummary)))

      // Delete button
      Button(action: {
        Haptics.play(.medium)
        onDelete()
      }) {
        Image(systemName: "trash")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexError)
          .accessibilityHidden(true)
          .frame(width: 36, height: 36)
          .background(Color.tidexError.opacity(0.1))
          .clipShape(Circle())
          .contentShape(Rectangle())
          .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.supplementsDeleteRuleAccessibility(ruleSummary)))
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

#Preview {
  SupplementsScreen(
    data: OnboardingData(),
    onContinue: {}
  )
}
