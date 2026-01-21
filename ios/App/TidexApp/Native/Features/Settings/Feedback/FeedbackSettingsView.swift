import SwiftUI

/// Feedback settings view
/// Allows users to submit feedback and view their feedback history with responses
struct FeedbackSettingsView: View {
    @Environment(\.localization) private var localization
    @StateObject private var viewModel = FeedbackSettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Error message
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                // Feedback form or success state
                if viewModel.showSuccess {
                    successCard
                } else {
                    feedbackFormSection
                }

                // Feedback history
                if !viewModel.feedbackHistory.isEmpty {
                    feedbackHistorySection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color.tidexBackground)
        .navigationTitle(localization.string("feedback.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.tidexBackground, for: .navigationBar)
        .task {
            await viewModel.loadData()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.string("feedback.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.tidexTextPrimary)

            Text(localization.string("feedback.subtitle"))
                .font(.subheadline)
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.tidexError)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextPrimary)

            Spacer()

            Button {
                viewModel.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .padding(12)
        .background(Color.tidexError.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Success Card

    private var successCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.tidexSuccess)

            Text(localization.string("feedback.success"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.resetSuccess()
            } label: {
                Text(localization.string("feedback.submitAnother"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexBlue)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(12)
    }

    // MARK: - Feedback Form Section

    private var feedbackFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Text editor
            TextEditor(text: $viewModel.message)
                .font(.system(size: 16))
                .foregroundColor(.tidexTextPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
                .padding(12)
                .background(Color.tidexSurfacePrimary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.tidexBorder, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.message.isEmpty {
                        Text(localization.string("feedback.placeholder"))
                            .font(.system(size: 16))
                            .foregroundColor(.tidexTextMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .disabled(viewModel.isSubmitting)

            // Character count and error
            HStack {
                Spacer()

                Text(viewModel.characterCountText)
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.isOverLimit ? .tidexError : .tidexTextMuted)
            }

            // Submit button
            Button {
                Task {
                    await viewModel.submitFeedback()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 16, height: 16)
                    }

                    Text(viewModel.isSubmitting
                         ? localization.string("feedback.sending")
                         : localization.string("feedback.submit"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Spacing.buttonHeight)
                .background(viewModel.canSubmit ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
                .cornerRadius(12)
            }
            .disabled(!viewModel.canSubmit)
        }
    }

    // MARK: - Feedback History Section

    private var feedbackHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(localization.string("feedback.history.title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            // History items
            VStack(spacing: 8) {
                ForEach(viewModel.feedbackHistory) { item in
                    feedbackHistoryItem(item)
                }
            }
        }
    }

    private func feedbackHistoryItem(_ item: FeedbackItem) -> some View {
        let isExpanded = viewModel.expandedItemId == item.id
        let locale = localization.currentLocale

        return VStack(spacing: 0) {
            // Header row (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleExpanded(item.id)
                }
            } label: {
                HStack(spacing: 12) {
                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        // Date and status row
                        HStack(spacing: 8) {
                            Text("\(localization.string("feedback.history.submittedOn")) \(item.formattedDate(locale: locale))")
                                .font(.system(size: 12))
                                .foregroundColor(.tidexTextMuted)

                            // Response status badge
                            if item.response != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                    Text(localization.string("feedback.history.respondedOn"))
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(.tidexSuccess)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10))
                                    Text(localization.string("feedback.history.noResponse"))
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(.tidexTextMuted)
                            }
                        }

                        // Message preview
                        Text(truncateMessage(item.message))
                            .font(.system(size: 14))
                            .foregroundColor(.tidexTextPrimary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.tidexTextMuted)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Full message
                    Text(item.message)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.tidexSurfaceSecondary)
                        .cornerRadius(8)

                    // Response (if any)
                    if let response = item.response {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.tidexSuccess)

                                Text(localization.string("feedback.history.response"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.tidexSuccess)

                                if let responseDate = item.formattedResponseDate(locale: locale) {
                                    Text("(\(responseDate))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.tidexSuccess.opacity(0.8))
                                }
                            }

                            Text(response)
                                .font(.system(size: 14))
                                .foregroundColor(.tidexTextPrimary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.tidexSuccess.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.tidexSuccess.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tidexBorder, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func truncateMessage(_ message: String, maxLength: Int = 80) -> String {
        if message.count <= maxLength {
            return message
        }
        return String(message.prefix(maxLength)) + "..."
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FeedbackSettingsView()
    }
    .environment(\.localization, LocalizationManager.shared)
}
