import SwiftUI

/// Feedback settings view
/// Allows users to submit feedback and view their feedback history with responses
struct FeedbackSettingsView: View {
  @State private var viewModel = FeedbackSettingsViewModel()
  @State private var historyAnimated = false

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.lg) {
        // Error message
        if let error = viewModel.errorMessage {
          ErrorBanner(message: error, onDismiss: { viewModel.clearError() })
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
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .feedbackTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadData()
    }
  }

  // MARK: - Success Card

  private var successCard: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 48))
        .foregroundColor(.tidexSuccess)

      Text(.feedbackSuccess)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)

      Button {
        viewModel.resetSuccess()
      } label: {
        Text(.feedbackSubmitAnother)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
      }
      .padding(.top, Spacing.xs)
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.lg)
  }

  // MARK: - Feedback Form Section

  private var feedbackFormSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Text editor
      TextEditor(text: $viewModel.message)
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 160)
        .padding(Spacing.sm)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(CornerRadius.lg)
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.lg)
            .stroke(Color.tidexBorder, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
          if viewModel.message.isEmpty {
            Text(.feedbackPlaceholder)
              .font(.tidexBody)
              .foregroundColor(.tidexTextMuted)
              .padding(.horizontal, Spacing.md)
              .padding(.vertical, Spacing.mlg)
              .allowsHitTesting(false)
          }
        }
        .disabled(viewModel.isSubmitting)

      // Character count and error
      HStack {
        if viewModel.isOfflineUnavailable {
          Text(.feedbackOfflineSubmitUnavailable)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }

        Spacer()

        Text(viewModel.characterCountText)
          .font(.tidexCaptionRegular)
          .foregroundColor(viewModel.isOverLimit ? .tidexError : .tidexTextMuted)
      }

      // Submit button
      Button {
        Task {
          await viewModel.submitFeedback()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          if viewModel.isSubmitting {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
              .frame(width: 16, height: 16)
          }

          Text(
            viewModel.isSubmitting
              ? String(localized: .feedbackSending)
              : String(localized: .feedbackSubmit)
          )
          .font(.tidexButton)
        }
        .foregroundColor(.tidexTextOnBrand)
        .frame(maxWidth: .infinity)
        .frame(height: Spacing.buttonHeight)
        .background(viewModel.canSubmit ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
        .cornerRadius(CornerRadius.lg)
      }
      .disabled(!viewModel.canSubmit)
    }
  }

  // MARK: - Feedback History Section

  private var feedbackHistorySection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Section header
      Text(.feedbackHistoryTitle)
        .font(.tidexButton)
        .foregroundColor(.tidexTextPrimary)

      // History items
      VStack(spacing: Spacing.xs) {
        ForEach(Array(viewModel.feedbackHistory.enumerated()), id: \.element.id) { index, item in
          feedbackHistoryItem(item)
            .offset(y: historyAnimated ? 0 : -20)
            .opacity(historyAnimated ? 1 : 0)
            .animation(
              .spring(response: 0.4, dampingFraction: 0.8)
                .delay(Double(index) * 0.08),
              value: historyAnimated
            )
        }
      }
      .onAppear {
        historyAnimated = true
      }
    }
  }

  private func feedbackHistoryItem(_ item: FeedbackItem) -> some View {
    let isExpanded = viewModel.expandedItemId == item.id
    let locale = Locale.current

    return VStack(spacing: 0) {
      // Header row (always visible)
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          viewModel.toggleExpanded(item.id)
        }
      } label: {
        HStack(spacing: Spacing.sm) {
          // Content
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Date and status row
            HStack(spacing: Spacing.xs) {
              Text(
                "\(String(localized: .feedbackHistorySubmittedOn)) \(item.formattedDate(locale: locale))"
              )
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextMuted)

              // Response status badge
              if item.response != nil {
                HStack(spacing: Spacing.xxs) {
                  Image(systemName: "checkmark.circle.fill")
                    .font(.tidexMicro)
                  Text(.feedbackHistoryRespondedOn)
                    .font(.tidexMicro)
                }
                .foregroundColor(.tidexSuccess)
              } else {
                HStack(spacing: Spacing.xxs) {
                  Image(systemName: "clock")
                    .font(.tidexMicro)
                  Text(.feedbackHistoryNoResponse)
                    .font(.tidexMicro)
                }
                .foregroundColor(.tidexTextMuted)
              }
            }

            // Message preview
            Text(truncateMessage(item.message))
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextPrimary)
              .lineLimit(1)
          }

          Spacer()

          // Chevron
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.tidexCaption)
            .foregroundColor(.tidexTextMuted)
        }
        .padding(Spacing.sm)
      }
      .buttonStyle(.plain)

      // Expanded content
      if isExpanded {
        VStack(alignment: .leading, spacing: Spacing.sm) {
          // Full message
          Text(item.message)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextPrimary)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tidexSurfaceSecondary)
            .cornerRadius(CornerRadius.sm)

          // Response (if any)
          if let response = item.response {
            VStack(alignment: .leading, spacing: Spacing.xs) {
              HStack(spacing: Spacing.xs) {
                Image(systemName: "message.fill")
                  .font(.tidexCaptionRegular)
                  .foregroundColor(.tidexSuccess)

                Text(.feedbackHistoryResponse)
                  .font(.tidexFootnoteMedium)
                  .foregroundColor(.tidexSuccess)

                if let responseDate = item.formattedResponseDate(locale: locale) {
                  Text("(\(responseDate))")
                    .font(.tidexCaptionRegular)
                    .foregroundColor(.tidexSuccess.opacity(0.8))
                }
              }

              Text(response)
                .font(.tidexSubheadline)
                .foregroundColor(.tidexTextPrimary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tidexSuccess.opacity(0.1))
            .overlay(
              RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Color.tidexSuccess.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(CornerRadius.sm)
          }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
      }
    }
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.lg)
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
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
}
