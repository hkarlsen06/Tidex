import SwiftUI

struct SendShiftToChatResult {
  let threadId: String
}

@MainActor
private final class SendShiftToChatViewModel: ObservableObject {
  @Published var recipients: [ShareRecipient] = []
  @Published var recipientSelection = ShareRecipientSelectionState()
  @Published var isLoading = true
  @Published var isSubmitting = false
  @Published var errorMessage: String?

  private let viewerUserId: String
  private let buildDraft: (ShareRecipient) throws -> ComposerShiftSnapshotDraft
  private let service: FriendsMessagingServiceProviding
  private let composerDraftStore: FriendsComposerDraftStore
  private let capabilities: any FriendsMessagingCapabilityProviding
  private var hasLoaded = false

  init(
    viewerUserId: String,
    buildDraft: @escaping (ShareRecipient) throws -> ComposerShiftSnapshotDraft,
    service: FriendsMessagingServiceProviding,
    composerDraftStore: FriendsComposerDraftStore,
    capabilities: any FriendsMessagingCapabilityProviding
  ) {
    self.viewerUserId = viewerUserId
    self.buildDraft = buildDraft
    self.service = service
    self.composerDraftStore = composerDraftStore
    self.capabilities = capabilities
  }

  var canContinue: Bool {
    selectedRecipient != nil && !isLoading && !isSubmitting
  }

  var selectedRecipient: ShareRecipient? {
    recipientSelection.selectedRecipient(in: recipients)
  }

  func beginSubmitting() -> Bool {
    guard !isSubmitting else { return false }
    isSubmitting = true
    errorMessage = nil
    return true
  }

  func loadIfNeeded() async {
    guard !hasLoaded else { return }
    hasLoaded = true
    await load()
  }

  func load() async {
    isLoading = true
    errorMessage = nil

    do {
      recipients = try await ShareExtensionMessagingClient.fetchRecipients()
      recipientSelection = ShareRecipientSelectionState()
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoading = false
  }

  func continueToChat() async -> SendShiftToChatResult? {
    guard let recipient = selectedRecipient else { return nil }
    guard beginSubmitting() else { return nil }
    return await continueToChat(recipient: recipient, beganSubmission: true)
  }

  func continueToChat(recipient: ShareRecipient, beganSubmission: Bool = false) async
    -> SendShiftToChatResult?
  {
    if !beganSubmission, !beginSubmitting() {
      return nil
    }
    defer { isSubmitting = false }

    do {
      guard capabilities.canSendShiftSnapshots else {
        errorMessage = String(
          localized: "friends.chat.shift_snapshot_send_unavailable", table: "Localizable")
        return nil
      }

      let thread = try await service.getOrCreateDirectThread(otherUserId: recipient.id)
      let draft = try buildDraft(recipient)
      await composerDraftStore.saveAttachmentDraft(
        .shiftSnapshot(draft),
        threadId: thread.id,
        viewerUserId: viewerUserId
      )
      return SendShiftToChatResult(threadId: thread.id)
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }
}

struct SendShiftToChatSheet: View {
  let viewerUserId: String
  let buildDraft: (ShareRecipient) throws -> ComposerShiftSnapshotDraft
  let onCompleted: (SendShiftToChatResult) -> Void

  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: SendShiftToChatViewModel

  @MainActor
  init(
    viewerUserId: String,
    buildDraft: @escaping (ShareRecipient) throws -> ComposerShiftSnapshotDraft,
    onCompleted: @escaping (SendShiftToChatResult) -> Void
  ) {
    self.viewerUserId = viewerUserId
    self.buildDraft = buildDraft
    self.onCompleted = onCompleted
    _viewModel = StateObject(
      wrappedValue: SendShiftToChatViewModel(
        viewerUserId: viewerUserId,
        buildDraft: buildDraft,
        service: FriendsMessagingService.shared,
        composerDraftStore: .shared,
        capabilities: FriendsMessagingCapabilities.shared
      )
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        content
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, Spacing.md)
      }
      .navigationTitle(String(localized: "friends.chat.send_to_chat", table: "Localizable"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .foregroundColor(.tidexBlue)
        }

        ToolbarItem(placement: .topBarTrailing) {
          if viewModel.isSubmitting {
            ProgressView()
          }
        }
      }
    }
    .task {
      await viewModel.loadIfNeeded()
    }
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.isLoading {
      VStack(spacing: Spacing.md) {
        ProgressView()
        Text(LocalizedStringResource("friends.chat.send_to_chat.loading", table: "Localizable"))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if viewModel.recipients.isEmpty {
      VStack(spacing: Spacing.md) {
        Image(systemName: "person.2.slash")
          .font(.system(size: 32, weight: .medium))
          .foregroundColor(.tidexTextMuted)

        Text(LocalizedStringResource("friends.chat.send_to_chat.empty_title", table: "Localizable"))
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

        Text(
          LocalizedStringResource("friends.chat.send_to_chat.empty_message", table: "Localizable")
        )
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
        .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text(LocalizedStringResource("friends.chat.send_to_chat.prompt", table: "Localizable"))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)

        if let errorMessage = viewModel.errorMessage {
          Text(errorMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)
        }

        ShareRecipientPickerList(
          recipients: viewModel.recipients,
          selectionState: Binding(
            get: { viewModel.recipientSelection },
            set: { viewModel.recipientSelection = $0 }
          ),
          onRecipientTap: { recipient in
            guard viewModel.beginSubmitting() else { return }

            Task {
              guard
                let result = await viewModel.continueToChat(
                  recipient: recipient,
                  beganSubmission: true
                )
              else { return }
              onCompleted(result)
            }
          }
        )
        .disabled(viewModel.isSubmitting)
      }
    }
  }
}
