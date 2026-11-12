import Observation
import SwiftUI

/// Asks before sharing the user's shifts with whoever sent an invite link. Nothing is shared
/// until the server has said who that is and the user taps Share.
@MainActor
@Observable
internal final class InviteConfirmationModel: Identifiable {
  internal enum Phase: Equatable {
    case loading
    /// Offline, or a server without `sharing:invitePreview`. Never offers to share.
    case loadFailed
    case ownLink
    /// No such user, or one of the two blocked the other.
    case unavailable
    case alreadySharing(InvitePreview)
    case confirm(InvitePreview, ShareAttempt)
    case shared(InvitePreview)
  }

  internal enum ShareAttempt: Equatable {
    case idle
    case sharing
    case failed(String)
  }

  internal let inviterId: String
  internal let viewerId: String
  internal private(set) var phase: Phase = .loading
  internal var showEarnings = false

  private let loadPreview: @MainActor (String) async throws -> InvitePreview?
  private let share: @MainActor (_ inviterId: String, _ showEarnings: Bool) async throws -> Void

  internal init(
    inviterId: String,
    viewerId: String,
    loadPreview: @escaping @MainActor (String) async throws -> InvitePreview? = {
      try await SharingService.shared.invitePreview(userId: $0)
    },
    share: @escaping @MainActor (String, Bool) async throws -> Void = {
      try await SharingService.shared.shareBack(recipientId: $0, showEarnings: $1)
    }
  ) {
    self.inviterId = inviterId
    self.viewerId = viewerId
    self.loadPreview = loadPreview
    self.share = share
  }

  internal func load() async {
    guard inviterId != viewerId else {
      phase = .ownLink
      return
    }
    phase = .loading
    do {
      guard let preview = try await loadPreview(inviterId) else {
        phase = .unavailable
        return
      }
      phase = preview.alreadySharing ? .alreadySharing(preview) : .confirm(preview, .idle)
    } catch {
      guard !ErrorTranslations.isCancellation(error) else { return }
      phase = .loadFailed
    }
  }

  /// Shares the user's shifts with the inviter. Returns whether a share started.
  @discardableResult
  internal func confirm() async -> Bool {
    guard case .confirm(let preview, let attempt) = phase, attempt != .sharing else {
      return false
    }
    phase = .confirm(preview, .sharing)
    do {
      try await share(inviterId, showEarnings)
    } catch SharingServiceError.shareRejected(.exists) {
      phase = .alreadySharing(preview)
      return false
    } catch {
      let message = ErrorTranslations.translate(error, fallback: .sharingInviteShareFailed)
      phase = .confirm(preview, message.map(ShareAttempt.failed) ?? .idle)
      return false
    }
    phase = .shared(preview)
    return true
  }
}

internal struct InviteConfirmationSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var model: InviteConfirmationModel

  /// Runs after the user shared and closed the sheet.
  private let onShared: () -> Void

  internal init(model: InviteConfirmationModel, onShared: @escaping () -> Void = {}) {
    _model = State(wrappedValue: model)
    self.onShared = onShared
  }

  internal var body: some View {
    NavigationStack {
      ScrollView {
        content
          .multilineTextAlignment(.center)
          .frame(maxWidth: AdaptiveMaxWidth.tabContent)
          .padding(.horizontal, Spacing.lg)
          .padding(.vertical, Spacing.xl)
          .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      .safeAreaInset(edge: .bottom) {
        actions
          .frame(maxWidth: AdaptiveMaxWidth.tabContent)
          .padding(.horizontal, Spacing.lg)
          .padding(.bottom, Spacing.md)
          .frame(maxWidth: .infinity)
          .background(Color.tidexBackground)
      }
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: .sharingInviteTitle))
      .navigationBarTitleDisplayMode(.inline)
      .motionAnimation(.subtle, value: model.phase, reduceMotion: reduceMotion)
    }
    .task { await model.load() }
  }

  // MARK: - Content

  @ViewBuilder private var content: some View {
    switch model.phase {
    case .loading:
      ProgressView(String(localized: .commonLoading))
        .padding(.top, Spacing.xxl)

    case .loadFailed:
      message(
        symbol: "wifi.exclamationmark", title: Text(.sharingInviteLoadFailedTitle),
        body: Text(.sharingInviteLoadFailedBody))

    case .ownLink:
      message(
        symbol: "link", title: Text(.sharingInviteOwnLinkTitle),
        body: Text(.sharingInviteOwnLinkBody))

    case .unavailable:
      message(
        symbol: "person.crop.circle.badge.questionmark",
        title: Text(.sharingInviteUnavailableTitle), body: Text(.sharingInviteUnavailableBody))

    case .alreadySharing(let preview):
      VStack(spacing: Spacing.md) {
        identity(preview)
        Text(.sharingInviteAlreadySharing(preview.displayName))
          .font(.tidexBody)
          .foregroundStyle(Color.tidexTextSecondary)
      }

    case .confirm(let preview, let attempt):
      confirmation(preview, attempt: attempt)

    case .shared(let preview):
      shared(preview)
    }
  }

  private func shared(_ preview: InvitePreview) -> some View {
    VStack(spacing: Spacing.md) {
      identity(preview)
      Label {
        Text(.sharingSharedWith(preview.displayName))
      } icon: {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Color.tidexSuccess)
      }
      .font(.tidexHeadline)
      .foregroundStyle(Color.tidexTextPrimary)
      Text(.sharingAskedToShareBack)
        .font(.tidexBody)
        .foregroundStyle(Color.tidexTextSecondary)
    }
  }

  private func confirmation(_ preview: InvitePreview, attempt: InviteConfirmationModel.ShareAttempt)
    -> some View
  {
    VStack(spacing: Spacing.lg) {
      identity(preview)
      confirmationText(preview)
      earningsChoice(isDisabled: attempt == .sharing)

      if case .failed(let reason) = attempt {
        Text(reason)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexError)
          .announcesToVoiceOver(reason)
      }
    }
  }

  private func confirmationText(_ preview: InvitePreview) -> some View {
    VStack(spacing: Spacing.sm) {
      VStack(spacing: Spacing.xs) {
        Text(.sharingInviteConfirmTitle(preview.displayName))
          .font(.tidexTitle)
          .foregroundStyle(Color.tidexTextPrimary)
        Text(.sharingInviteWhatIsShared)
          .font(.tidexBody)
          .foregroundStyle(Color.tidexTextSecondary)
      }

      if !preview.hasName {
        Label {
          Text(.sharingInviteNoName)
            .foregroundStyle(Color.tidexTextPrimary)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.tidexWarning)
        }
        .font(.tidexSubheadline)
        .multilineTextAlignment(.leading)
      }
    }
  }

  private func earningsChoice(isDisabled: Bool) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Toggle(String(localized: .sharingShowEarnings), isOn: $model.showEarnings)
        .tint(.tidexBlue)
        .disabled(isDisabled)
      Text(model.showEarnings ? .sharingInviteEarningsShown : .sharingInviteEarningsHidden)
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextMuted)
    }
    .multilineTextAlignment(.leading)
    .padding(Spacing.md)
    .tidexRowSurface(cornerRadius: CornerRadius.card, fillColor: .tidexSurfacePrimary)
  }

  private func identity(_ preview: InvitePreview) -> some View {
    VStack(spacing: Spacing.xs) {
      AvatarView(
        url: preview.person.avatarUrl, initials: preview.hasName ? preview.person.initials : "?",
        size: 72)
      Text(preview.displayName)
        .font(.tidexHeadline)
        .foregroundStyle(Color.tidexTextPrimary)
      if let contactInfo = preview.person.contactInfo {
        Text(contactInfo)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextMuted)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func message(symbol: String, title: Text, body: Text) -> some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: symbol)
        .font(.largeTitle)
        .foregroundStyle(Color.tidexTextMuted)
        .accessibilityHidden(true)
      title
        .font(.tidexTitle)
        .foregroundStyle(Color.tidexTextPrimary)
      body
        .font(.tidexBody)
        .foregroundStyle(Color.tidexTextSecondary)
    }
    .padding(.top, Spacing.xl)
  }

  // MARK: - Actions

  private var actions: some View {
    VStack(spacing: Spacing.xs) {
      actionButtons
    }
  }

  @ViewBuilder private var actionButtons: some View {
    switch model.phase {
    case .loading:
      secondaryButton(.sharingInviteNotNow) { dismiss() }

    case .loadFailed:
      PrimaryButton(title: String(localized: .commonRetry)) {
        Task { await model.load() }
      }
      secondaryButton(.sharingInviteNotNow) { dismiss() }

    case .ownLink:
      PrimaryButton(title: String(localized: .sharingInviteAction)) {
        dismiss()
        FriendInvite.presentShareSheet(for: model.viewerId)
      }
      secondaryButton(.sharingInviteNotNow) { dismiss() }

    case .unavailable, .alreadySharing:
      PrimaryButton(title: String(localized: .commonDone)) { dismiss() }

    case .confirm(_, let attempt):
      PrimaryButton(
        title: String(localized: .sharingInviteShare), action: share,
        isLoading: attempt == .sharing)
      secondaryButton(.sharingInviteNotNow) { dismiss() }
        .disabled(attempt == .sharing)

    case .shared:
      PrimaryButton(title: String(localized: .commonDone)) {
        dismiss()
        onShared()
      }
    }
  }

  private func share() {
    Task {
      guard await model.confirm() else { return }
      Haptics.play(.success)
      FriendInvite.didStartSharing()
    }
  }

  private func secondaryButton(_ title: LocalizedStringResource, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Text(title)
        .font(.tidexButton)
        .foregroundStyle(Color.tidexBlueText)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Spacing.buttonHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

extension InvitePreview {
  /// The inviter as a friend row, for its avatar, initials and username line.
  fileprivate var person: SharedUser {
    SharedUser(
      id: id, email: nil, phone: nil, firstName: firstName, profilePictureUrl: profilePictureUrl,
      oauthAvatarUrl: oauthAvatarUrl, sharedAt: "", showEarnings: false, hidden: false,
      username: username)
  }

  fileprivate var displayName: String {
    hasName ? person.displayName : String(localized: .sharingInviteUnnamed)
  }
}
