import SwiftUI
import UIKit

/// Screen for configuring custom supplement rules
/// Only shown for custom wage users
struct SupplementsScreen: View {
  @Bindable var data: OnboardingData
  let onContinue: () -> Void
  let onSkip: () -> Void
  var onBack: (() -> Void)? = nil

  @State private var showingRuleEditor = false
  @State private var editingRule: OnboardingSupplementRule?

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 0) {
            // Back button (if provided)
            if let onBack = onBack {
              HStack {
                Button(action: {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                  onBack()
                }) {
                  HStack(spacing: Spacing.xxs) {
                    Image(systemName: "chevron.left")
                      .font(.tidexButton)
                    Text(.commonBack)
                      .font(.tidexBody)
                  }
                  .foregroundColor(.tidexBlue)
                }
                .buttonStyle(.plain)
                Spacer()
              }
              .padding(.horizontal, Spacing.lg)
              .padding(.top, Spacing.md)
              .adaptiveContentWidth()
            }

            Spacer()
              .frame(height: onBack != nil ? 24 : 60)

            // Header
            VStack(spacing: Spacing.sm) {
              Text(.onboardingSupplementsTitle)
                .font(.tidexScreenTitle)
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)

              Text(.onboardingSupplementsSubtitle)
                .font(.tidexBody)
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 32)

            // Supplement rules list
            if !data.supplementRules.isEmpty {
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
                      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        data.supplementRules.removeAll { $0.id == rule.id }
                      }
                    }
                  )
                }
              }
              .padding(.horizontal, Spacing.lg)
              .adaptiveContentWidth()

              Spacer()
                .frame(height: 16)
            }

            // Add rule button
            Button(action: {
              UIImpactFeedbackGenerator(style: .medium).impactOccurred()
              editingRule = nil
              showingRuleEditor = true
            }) {
              HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                  .font(.system(size: 20))
                Text(.onboardingSupplementsAddRule)
                  .font(.tidexBodyMedium)
              }
              .foregroundColor(.tidexBlue)
              .frame(maxWidth: .infinity)
              .frame(height: 56)
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

        // Bottom buttons
        VStack(spacing: Spacing.sm) {
          OnboardingButton(
            title: String(localized: .commonContinue),
            action: {
              UINotificationFeedbackGenerator().notificationOccurred(.success)
              onContinue()
            }
          )

          Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSkip()
          }) {
            Text(.onboardingSupplementsSkip)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextSecondary)
          }
        }
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
}

// MARK: - Supplement Rule Card

private struct SupplementRuleCard: View {
  let rule: OnboardingSupplementRule
  let locale: Locale
  let currency: String
  let onEdit: () -> Void
  let onDelete: () -> Void

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

          Text(rule.valueDescription(locale: locale, currency: currency))
            .font(.tidexLabel)
            .foregroundColor(.tidexSuccess)
        }
      }

      Spacer()

      // Edit button
      Button(action: {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onEdit()
      }) {
        Image(systemName: "pencil")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexBlue)
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

      // Delete button
      Button(action: {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onDelete()
      }) {
        Image(systemName: "trash")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexError)
          .frame(width: 36, height: 36)
          .background(Color.tidexError.opacity(0.1))
          .clipShape(Circle())
          .contentShape(Rectangle())
          .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

#Preview {
  SupplementsScreen(
    data: OnboardingData(),
    onContinue: {},
    onSkip: {}
  )
}
