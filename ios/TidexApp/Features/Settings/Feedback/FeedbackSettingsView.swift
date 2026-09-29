import SwiftUI

/// Feedback settings view
/// Allows users to submit feedback and view their feedback history with responses
struct FeedbackSettingsView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var viewModel = FeedbackSettingsViewModel()

  var body: some View {
    Form {
      Group {
        if let error = viewModel.errorMessage {
          Section {
            ErrorBanner(message: error, onDismiss: { viewModel.clearError() })
          }
        }

        if viewModel.showSuccess {
          successSection
        } else {
          feedbackFormSection
          submitSection
        }

        if !viewModel.feedbackHistory.isEmpty {
          feedbackHistorySection
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle(String(localized: .feedbackTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadData()
    }
  }

  // MARK: - Success

  private var successSection: some View {
    Section {
      Label {
        Text(.feedbackSuccess)
          .foregroundColor(.tidexTextPrimary)
      } icon: {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.tidexSuccess)
      }
      .announcesToVoiceOver(String(localized: .feedbackSuccess))

      Button {
        viewModel.resetSuccess()
      } label: {
        Text(.feedbackSubmitAnother)
          .foregroundColor(.tidexBlueText)
      }
    }
  }

  // MARK: - Form

  private var feedbackFormSection: some View {
    Section {
      TextField(
        String(localized: .feedbackPlaceholder),
        text: $viewModel.message,
        axis: .vertical
      )
      .lineLimit(6...)
      .accessibilityLabel(Text(.feedbackTitle))
      .font(.tidexBody)
      .foregroundColor(.tidexTextPrimary)
      .disabled(viewModel.isSubmitting)
    } footer: {
      HStack {
        if viewModel.isOfflineUnavailable {
          Text(.feedbackOfflineSubmitUnavailable)
        }

        Spacer()

        HStack(spacing: Spacing.xxs) {
          if viewModel.isOverLimit {
            Image(systemName: "exclamationmark.circle.fill")
              .accessibilityHidden(true)
          }
          Text(viewModel.characterCountText)
            .monospacedDigit()
        }
        .foregroundColor(viewModel.isOverLimit ? .tidexError : .tidexTextMuted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          viewModel.isOverLimit
            ? Text(.settingsAccessibilityFeedbackOverLimit(viewModel.characterCountText))
            : Text(verbatim: viewModel.characterCountText)
        )
      }
    }
  }

  private var submitSection: some View {
    Section {
      Button {
        Task {
          await viewModel.submitFeedback()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          Text(viewModel.isSubmitting ? .feedbackSending : .feedbackSubmit)
            .font(.tidexButton)
            .foregroundColor(viewModel.canSubmit ? .tidexBlueText : .tidexTextMuted)

          if viewModel.isSubmitting {
            ProgressView()
          }
        }
        .frame(maxWidth: .infinity)
      }
      .disabled(!viewModel.canSubmit)
    }
  }

  // MARK: - History

  private var feedbackHistorySection: some View {
    Section {
      ForEach(viewModel.feedbackHistory, id: \.id) { item in
        DisclosureGroup(
          isExpanded: Binding(
            get: { viewModel.expandedItemId == item.id },
            set: { _ in
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.toggleExpanded(item.id)
              }
            }
          )
        ) {
          feedbackHistoryDetail(item)
        } label: {
          feedbackHistoryLabel(item)
        }
        .tint(.tidexTextMuted)
      }
    } header: {
      Text(.feedbackHistoryTitle)
    }
  }

  private func feedbackHistoryLabel(_ item: FeedbackItem) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Spacing.xs) {
          historyDate(item)
          historyStatus(item)
        }

        VStack(alignment: .leading, spacing: Spacing.xxs) {
          historyDate(item)
          historyStatus(item)
        }
      }

      Text(item.message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)
    }
  }

  private func historyDate(_ item: FeedbackItem) -> some View {
    Text(
      "\(String(localized: .feedbackHistorySubmittedOn)) \(item.formattedDate(locale: Locale.current))"
    )
    .font(.tidexCaptionRegular)
    .foregroundColor(.tidexTextMuted)
  }

  private func historyStatus(_ item: FeedbackItem) -> some View {
    Label {
      Text(item.response != nil ? .feedbackHistoryRespondedOn : .feedbackHistoryNoResponse)
    } icon: {
      Image(systemName: item.response != nil ? "checkmark.circle.fill" : "clock")
    }
    .labelStyle(.titleAndIcon)
    .font(.tidexMicro)
    .foregroundColor(item.response != nil ? .tidexSuccess : .tidexTextMuted)
  }

  @ViewBuilder
  private func feedbackHistoryDetail(_ item: FeedbackItem) -> some View {
    Text(item.message)
      .font(.tidexSubheadline)
      .foregroundColor(.tidexTextPrimary)
      .textSelection(.enabled)

    if let response = item.response {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        HStack(spacing: Spacing.xs) {
          Label(String(localized: .feedbackHistoryResponse), systemImage: "message.fill")
            .font(.tidexFootnoteMedium)

          if let responseDate = item.formattedResponseDate(locale: Locale.current) {
            Text(responseDate)
              .font(.tidexCaptionRegular)
          }
        }
        .foregroundColor(.tidexSuccess)

        Text(response)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)
          .textSelection(.enabled)
      }
    }
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    FeedbackSettingsView()
  }
}
