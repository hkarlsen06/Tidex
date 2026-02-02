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
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text(.commonBack)
                                            .font(.system(size: 16))
                                    }
                                    .foregroundColor(.tidexBlue)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .adaptiveContentWidth()
                        }

                        Spacer()
                            .frame(height: onBack != nil ? 24 : 60)

                        // Header
                        VStack(spacing: 12) {
                            Text(.onboardingSupplementsTitle)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.tidexTextPrimary)
                                .multilineTextAlignment(.center)

                            Text(.onboardingSupplementsSubtitle)
                                .font(.system(size: 17))
                                .foregroundColor(.tidexTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        .adaptiveContentWidth()

                        Spacer()
                            .frame(height: 32)

                        // Supplement rules list
                        if !data.supplementRules.isEmpty {
                            VStack(spacing: 12) {
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
                            .padding(.horizontal, 24)
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
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                Text(.onboardingSupplementsAddRule)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(.tidexBlue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.tidexBlue.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.tidexBlue.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                        .adaptiveContentWidth()

                        // Info text when no rules
                        if data.supplementRules.isEmpty {
                            Spacer()
                                .frame(height: 24)

                            Text(.onboardingSupplementsHint)
                                .font(.system(size: 14))
                                .foregroundColor(.tidexTextMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .adaptiveContentWidth()
                        }

                        Spacer()
                            .frame(height: 48)
                    }
                }

                // Bottom buttons
                VStack(spacing: 12) {
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
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexTextSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.daysDescription)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                HStack(spacing: 8) {
                    Text(rule.timeDescription)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)

                    Text("•")
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextMuted)

                    Text(rule.valueDescription(locale: locale, currency: currency))
                        .font(.system(size: 14, weight: .medium))
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
                    .font(.system(size: 14))
                    .foregroundColor(.tidexBlue)
                    .frame(width: 36, height: 36)
                    .background(Color.tidexBlue.opacity(0.1))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.tidexBlue.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onDelete()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexError)
                    .frame(width: 36, height: 36)
                    .background(Color.tidexError.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    SupplementsScreen(
        data: OnboardingData(),
        onContinue: {},
        onSkip: {}
    )
}
