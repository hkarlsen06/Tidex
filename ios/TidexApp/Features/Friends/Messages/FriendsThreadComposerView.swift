import ExyteChat
import PhotosUI
import SwiftUI
import UIKit

enum FriendsThreadComposerMode: Equatable {
  case normal
  case reply
  case edit
}

struct FriendsThreadComposerConfiguration: Equatable {
  let mode: FriendsThreadComposerMode
  let draftText: String
  let replyPreview: FriendsChatReplyPreviewModel?
  let stagedAttachment: FriendsComposerAttachmentDraft?
  let isThreadReadOnly: Bool
  let sendErrorMessage: String?
  let placeholder: String
  let canSendShiftSnapshots: Bool
  let focusRequestToken: Int
}

@MainActor
final class FriendsThreadComposerBridge: ObservableObject {
  @Published private(set) var mode: FriendsThreadComposerMode = .normal
  @Published private(set) var draftText: String = ""
  @Published private(set) var replyPreview: FriendsChatReplyPreviewModel?
  @Published private(set) var stagedAttachment: FriendsComposerAttachmentDraft?
  @Published private(set) var isThreadReadOnly = false
  @Published private(set) var sendErrorMessage: String?
  @Published private(set) var placeholder: String = ""
  @Published private(set) var canSendShiftSnapshots = false
  @Published private(set) var focusRequestToken = 0

  var onDraftChanged: ((String) -> Void)?
  var onStagedAttachmentChanged: ((FriendsComposerAttachmentDraft?) -> Void)?
  var onCancelMode: (() -> Void)?
  var onSend: ((String) async -> Bool)?
  var onSaveEdit: ((String) async -> Bool)?
  var onPrepareShiftSnapshotAttachment:
    (
      (ShiftWithComputations) async
        -> FriendsComposerAttachmentDraft?
    )?
  var onHeightChanged: ((CGFloat) -> Void)?
  var onAttachmentDrawerOpenChanged: ((Bool) -> Void)?

  private var isApplyingExternalDraft = false
  private var isApplyingExternalAttachment = false

  var draftBinding: Binding<String> {
    Binding(
      get: { self.draftText },
      set: { [weak self] newValue in
        self?.updateDraftText(newValue)
      }
    )
  }

  func apply(configuration: FriendsThreadComposerConfiguration) {
    mode = configuration.mode
    replyPreview = configuration.replyPreview
    isThreadReadOnly = configuration.isThreadReadOnly
    sendErrorMessage = configuration.sendErrorMessage
    placeholder = configuration.placeholder
    canSendShiftSnapshots = configuration.canSendShiftSnapshots
    focusRequestToken = configuration.focusRequestToken

    if draftText != configuration.draftText {
      isApplyingExternalDraft = true
      draftText = configuration.draftText
      isApplyingExternalDraft = false
    }

    if stagedAttachment != configuration.stagedAttachment {
      isApplyingExternalAttachment = true
      stagedAttachment = configuration.stagedAttachment
      isApplyingExternalAttachment = false
    }
  }

  func cancelMode() {
    onCancelMode?()
  }

  func send(content: String) async -> Bool {
    guard let onSend else { return false }
    return await onSend(content)
  }

  func saveEdit(content: String) async -> Bool {
    guard let onSaveEdit else { return false }
    return await onSaveEdit(content)
  }

  func reportHeight(_ height: CGFloat) {
    onHeightChanged?(height)
  }

  func reportAttachmentDrawerOpen(_ isOpen: Bool) {
    onAttachmentDrawerOpenChanged?(isOpen)
  }

  func stageImageAttachment(_ image: ImageAttachment) {
    updateStagedAttachment(.image(image))
  }

  func prepareAndStageShiftAttachment(from shift: ShiftWithComputations) async -> Bool {
    guard let onPrepareShiftSnapshotAttachment else { return false }
    guard let attachment = await onPrepareShiftSnapshotAttachment(shift) else { return false }
    updateStagedAttachment(attachment)
    return true
  }

  func removeStagedAttachment() {
    updateStagedAttachment(nil)
  }

  private func updateDraftText(_ newValue: String) {
    guard draftText != newValue else { return }
    draftText = newValue
    guard !isApplyingExternalDraft else { return }
    onDraftChanged?(newValue)
  }

  private func updateStagedAttachment(_ newValue: FriendsComposerAttachmentDraft?) {
    guard stagedAttachment != newValue else { return }
    stagedAttachment = newValue
    guard !isApplyingExternalAttachment else { return }
    onStagedAttachmentChanged?(newValue)
  }
}

struct FriendsThreadComposerHostedView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var bridge: FriendsThreadComposerBridge
  let text: Binding<String>
  @StateObject private var attachmentController = FriendsComposerAttachmentController()
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var isSubmitting = false
  @State private var composerFocusTrigger = 0
  @State private var isComposerFocused = false
  @State private var isApplyingExternalDraft = false

  private let attachmentCollapseCharacterThreshold = 18

  private var canSend: Bool {
    let normalizedDraft = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return (!normalizedDraft.isEmpty || bridge.stagedAttachment != nil)
      && !bridge.isThreadReadOnly
      && !isSubmitting
      && !attachmentController.isProcessingAttachment
  }

  private var isPreparingAttachmentDrawer: Bool {
    attachmentController.isDrawerOpen && attachmentController.recentPhotosState == .loading
  }

  private var shouldHidePlusButton: Bool {
    guard !attachmentController.isDrawerOpen else { return false }
    guard bridge.stagedAttachment == nil else { return false }
    guard isComposerFocused else { return false }

    let draftLength = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).count
    return draftLength >= attachmentCollapseCharacterThreshold
      || text.wrappedValue.contains("\n")
  }

  var body: some View {
    VStack(spacing: Spacing.xs) {
      if bridge.mode == .reply, let replyPreview = bridge.replyPreview {
        FriendsThreadComposerReplyBanner(
          preview: replyPreview,
          onCancel: bridge.cancelMode
        )
        .padding(.horizontal, Spacing.md)
      } else if bridge.mode == .edit {
        FriendsThreadComposerEditBanner(onCancel: bridge.cancelMode)
          .padding(.horizontal, Spacing.md)
      }

      if let stagedAttachment = bridge.stagedAttachment {
        FriendsThreadComposerAttachmentPreview(
          attachment: stagedAttachment,
          onRemove: bridge.removeStagedAttachment
        )
        .padding(.horizontal, Spacing.md)
      }

      if bridge.isThreadReadOnly {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "hand.raised.fill")
            .foregroundColor(.tidexWarning)

          Text(.friendsChatBlockedReadOnly)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)

          Spacer()
        }
        .padding(.horizontal, Spacing.md)
      }

      if let sendErrorMessage = bridge.sendErrorMessage {
        HStack(spacing: Spacing.xs) {
          Text(sendErrorMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)

          Spacer()
        }
        .padding(.horizontal, Spacing.md)
      }

      composerField

      if attachmentController.isDrawerOpen {
        FriendsThreadComposerAttachmentDrawer(
          recentPhotosState: attachmentController.recentPhotosState,
          recentPhotos: attachmentController.recentPhotos,
          isProcessingAttachment: attachmentController.isProcessingAttachment,
          showsShiftCalendarAction: bridge.canSendShiftSnapshots,
          stagedAttachment: bridge.stagedAttachment,
          onOpenPhotoLibrary: {
            attachmentController.isShowingPhotoLibrary = true
          },
          onOpenCamera: {
            attachmentController.isShowingCamera = true
          },
          onOpenShiftCalendar: {
            attachmentController.openShiftCalendar()
          },
          onSelectRecentPhoto: { photo in
            Task {
              await handleRecentPhotoSelection(photo)
            }
          }
        )
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(
      .spring(response: 0.26, dampingFraction: 0.86), value: attachmentController.isDrawerOpen
    )
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .bottom)
    .background(Color.tidexBackground)
    .background(
      GeometryReader { geometry in
        Color.clear.preference(
          key: FriendsThreadComposerHeightPreferenceKey.self,
          value: geometry.size.height
        )
      }
    )
    .onPreferenceChange(FriendsThreadComposerHeightPreferenceKey.self) { height in
      bridge.reportHeight(height)
    }
    .onAppear {
      syncTextFromBridgeIfNeeded()
    }
    .onChange(of: attachmentController.isDrawerOpen) { _, isOpen in
      bridge.reportAttachmentDrawerOpen(isOpen)
    }
    .onChange(of: bridge.draftText) { _, _ in
      syncTextFromBridgeIfNeeded()
    }
    .onChange(of: text.wrappedValue) { _, newValue in
      guard !isApplyingExternalDraft else { return }
      bridge.onDraftChanged?(newValue)
    }
    .onChange(of: bridge.focusRequestToken) { _, _ in
      composerFocusTrigger += 1
    }
    .onChange(of: bridge.mode) { _, newMode in
      if newMode == .edit {
        attachmentController.closeDrawer()
      }
    }
    .onChange(of: selectedPhotoItem) { _, newItem in
      Task {
        await handleSelectedPhotoItem(newItem)
      }
    }
    .photosPicker(
      isPresented: $attachmentController.isShowingPhotoLibrary,
      selection: $selectedPhotoItem,
      matching: .images,
      photoLibrary: .shared()
    )
    .fullScreenCover(isPresented: $attachmentController.isShowingCamera) {
      CameraPicker { image in
        Task {
          await handleCapturedImage(image)
        }
      }
      .ignoresSafeArea()
    }
    .sheet(isPresented: $attachmentController.isShowingShiftCalendar) {
      FriendsComposerShiftCalendarPicker { shift in
        await handleShiftSelection(shift)
      }
    }
  }

  private var composerField: some View {
    ChatComposerField(
      text: text,
      placeholder: bridge.placeholder,
      disabled: bridge.isThreadReadOnly || attachmentController.isProcessingAttachment,
      isSending: isSubmitting,
      canPerformAction: canSend,
      actionAccessibilityLabel: bridge.mode == .edit
        ? String(localized: "friends.chat.composer.save_edit", table: "Localizable")
        : String(localized: "Send message"),
      focusTrigger: composerFocusTrigger,
      onFocusChanged: { isComposerFocused = $0 },
      horizontalPadding: MonthPickerLayout.horizontalPadding,
      focusedHorizontalPadding: Spacing.xs,
      topPadding: Spacing.xs,
      bottomPadding: MonthPickerLayout.bottomPadding,
      onAction: sendMessage
    ) {
      if !shouldHidePlusButton {
        FriendsThreadComposerPlusButton(
          isOpen: attachmentController.isDrawerOpen,
          isDisabled: bridge.isThreadReadOnly || attachmentController.isProcessingAttachment
            || isPreparingAttachmentDrawer
            || bridge.mode == .edit,
          isPreparing: isPreparingAttachmentDrawer,
          action: toggleAttachmentDrawer
        )
        .transition(.move(edge: .leading).combined(with: .opacity))
      }
    }
    .animation(
      reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.9),
      value: shouldHidePlusButton
    )
  }

  private func sendMessage() {
    guard canSend else { return }

    if bridge.mode == .edit {
      isSubmitting = true

      Task {
        let didSave = await bridge.saveEdit(
          content: text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        await MainActor.run {
          isSubmitting = false
          if didSave {
            attachmentController.closeDrawer()
          }
        }
      }
      return
    }

    isSubmitting = true
    attachmentController.closeDrawer()

    Task {
      let didSend = await bridge.send(
        content: text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
      )
      await MainActor.run {
        isSubmitting = false
        guard didSend else { return }
      }
    }
  }

  private func handleSelectedPhotoItem(_ item: PhotosPickerItem?) async {
    let shouldRestoreFocus = isComposerFocused
    guard let imageAttachment = await attachmentController.makeImageAttachment(from: item) else {
      await MainActor.run {
        selectedPhotoItem = nil
      }
      return
    }

    bridge.stageImageAttachment(imageAttachment)
    await MainActor.run {
      selectedPhotoItem = nil
      attachmentController.completeAttachmentSelection()
      restoreComposerFocusIfNeeded(shouldRestoreFocus)
    }
  }

  private func handleRecentPhotoSelection(_ photo: FriendsComposerRecentPhoto) async {
    let shouldRestoreFocus = isComposerFocused
    guard let imageAttachment = await attachmentController.makeImageAttachment(from: photo) else {
      return
    }

    bridge.stageImageAttachment(imageAttachment)
    attachmentController.completeAttachmentSelection()
    restoreComposerFocusIfNeeded(shouldRestoreFocus)
  }

  private func handleCapturedImage(_ image: UIImage) async {
    let shouldRestoreFocus = isComposerFocused
    guard let imageAttachment = await attachmentController.makeImageAttachment(from: image) else {
      return
    }

    bridge.stageImageAttachment(imageAttachment)
    attachmentController.completeAttachmentSelection()
    restoreComposerFocusIfNeeded(shouldRestoreFocus)
  }

  private func handleShiftSelection(_ shift: ShiftWithComputations) async -> Bool {
    guard attachmentController.beginProcessingAttachment() else { return false }

    let shouldRestoreFocus = isComposerFocused
    defer {
      attachmentController.finishProcessingAttachment()
    }

    let didStageAttachment = await bridge.prepareAndStageShiftAttachment(from: shift)
    if didStageAttachment {
      attachmentController.completeAttachmentSelection()
      restoreComposerFocusIfNeeded(shouldRestoreFocus)
    }
    return didStageAttachment
  }

  private func restoreComposerFocusIfNeeded(_ shouldRestoreFocus: Bool) {
    guard shouldRestoreFocus else { return }
    DispatchQueue.main.async {
      composerFocusTrigger += 1
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
      composerFocusTrigger += 1
    }
  }

  private func toggleAttachmentDrawer() {
    let shouldRestoreFocus = isComposerFocused
    Task {
      await attachmentController.toggleDrawer()
      await MainActor.run {
        restoreComposerFocusIfNeeded(shouldRestoreFocus)
      }
    }
  }

  private func syncTextFromBridgeIfNeeded() {
    guard text.wrappedValue != bridge.draftText else { return }
    isApplyingExternalDraft = true
    text.wrappedValue = bridge.draftText
    isApplyingExternalDraft = false
  }
}

private struct FriendsThreadComposerPlusButton: View {
  let isOpen: Bool
  let isDisabled: Bool
  let isPreparing: Bool
  let action: () -> Void

  var body: some View {
    Group {
      if isPreparing {
        ProgressView()
          .progressViewStyle(.circular)
          .tint(.tidexBlue)
      } else {
        Image(systemName: "plus")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(isDisabled ? .tidexTextMuted : .tidexBlue)
          .rotationEffect(.degrees(isOpen ? 45 : 0))
      }
    }
    .frame(width: 44, height: 44)
    .background(
      Circle()
        .fill(isOpen ? Color.tidexBlue.opacity(0.18) : Color.tidexBlue.opacity(0.12))
    )
    .contentShape(Circle())
    .onTapGesture {
      guard !isDisabled else { return }
      action()
    }
    .accessibilityAddTraits(.isButton)
    .accessibilityRespondsToUserInteraction(!isDisabled)
    .accessibilityLabel(
      Text(
        LocalizedStringResource(
          isOpen
            ? "friends.chat.composer.close_attachments"
            : "friends.chat.composer.open_attachments",
          table: "Localizable"
        )
      )
    )
  }
}

private struct FriendsThreadComposerAttachmentDrawer: View {
  private enum Layout {
    static let previewWidth: CGFloat = 144
    static let previewHeight: CGFloat = 192
  }

  let recentPhotosState: FriendsComposerRecentPhotosState
  let recentPhotos: [FriendsComposerRecentPhoto]
  let isProcessingAttachment: Bool
  let showsShiftCalendarAction: Bool
  let stagedAttachment: FriendsComposerAttachmentDraft?
  let onOpenPhotoLibrary: () -> Void
  let onOpenCamera: () -> Void
  let onOpenShiftCalendar: () -> Void
  let onSelectRecentPhoto: (FriendsComposerRecentPhoto) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(spacing: Spacing.sm) {
        actionButton(
          systemName: "photo.on.rectangle.angled",
          isActive: stagedAttachment?.imageAttachment != nil,
          accessibilityLabel: String(
            localized: "friends.chat.composer.photo_library",
            table: "Localizable"
          ),
          action: onOpenPhotoLibrary
        )

        actionButton(
          systemName: "camera",
          isActive: false,
          accessibilityLabel: String(
            localized: "friends.chat.composer.camera",
            table: "Localizable"
          ),
          action: onOpenCamera
        )

        if showsShiftCalendarAction {
          actionButton(
            systemName: "calendar",
            isActive: stagedAttachment?.shiftSnapshot != nil,
            accessibilityLabel: String(
              localized: "friends.chat.composer.shift_calendar",
              table: "Localizable"
            ),
            action: onOpenShiftCalendar
          )
        }
      }

      Group {
        switch recentPhotosState {
        case .idle, .loading:
          HStack {
            Spacer()
            ProgressView()
              .padding(.vertical, Spacing.md)
            Spacer()
          }
        case .loaded:
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
              ForEach(recentPhotos) { photo in
                Button {
                  onSelectRecentPhoto(photo)
                } label: {
                  Image(uiImage: photo.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Layout.previewWidth, height: Layout.previewHeight)
                    .clipShape(
                      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessingAttachment)
              }
            }
            .padding(.horizontal, Spacing.md)
          }
          .frame(height: Layout.previewHeight)
          .scrollBounceBehavior(.always, axes: .horizontal)
          .scrollBounceBehavior(.basedOnSize, axes: .vertical)
          .padding(.horizontal, -Spacing.md)
        case .empty:
          drawerMessage(
            String(
              localized: "friends.chat.composer.recent_photos.empty",
              table: "Localizable"
            )
          )
        case .denied:
          drawerMessage(
            String(
              localized: "friends.chat.composer.recent_photos.denied",
              table: "Localizable"
            )
          )
        case .failed:
          drawerMessage(
            String(
              localized: "friends.chat.composer.recent_photos.empty",
              table: "Localizable"
            )
          )
        }
      }
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .stroke(Color.tidexBorder.opacity(0.4), lineWidth: 1)
    )
  }

  @ViewBuilder
  private func drawerMessage(_ message: String) -> some View {
    HStack {
      Text(message)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
      Spacer()
    }
    .padding(.vertical, Spacing.sm)
  }

  private func actionButton(
    systemName: String,
    isActive: Bool,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(isActive ? .tidexBlue : .tidexTextPrimary)
        .frame(width: 40, height: 40)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .fill(isActive ? Color.tidexBlue.opacity(0.14) : Color.tidexSurfaceSecondary)
        )
    }
    .buttonStyle(.plain)
    .disabled(isProcessingAttachment)
    .accessibilityLabel(Text(accessibilityLabel))
  }
}

private struct FriendsThreadComposerAttachmentPreview: View {
  let attachment: FriendsComposerAttachmentDraft
  let onRemove: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Group {
        switch attachment {
        case .image(let image):
          FriendsThreadComposerImageAttachmentCard(image: image)
        case .shiftSnapshot(let draft):
          ChatShiftSnapshotCard(
            snapshot: draft.snapshot,
            isCurrentUser: false,
            isHighlighted: false
          )
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      removeButton
    }
  }

  private var removeButton: some View {
    Button(action: onRemove) {
      Image(systemName: "xmark")
        .font(.tidexCaptionStrong)
        .foregroundColor(.tidexTextMuted)
        .frame(width: 32, height: 32)
        .background(
          Circle()
            .fill(Color.tidexSurfacePrimary.opacity(0.96))
        )
        .overlay(
          Circle()
            .stroke(Color.tidexBorder.opacity(0.45), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(.friendsChatComposerRemoveAttachment))
  }
}

private struct FriendsThreadComposerImageAttachmentCard: View {
  let image: ImageAttachment

  var body: some View {
    HStack(spacing: Spacing.sm) {
      if let uiImage = UIImage(data: image.data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(width: 72, height: 72)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfaceSecondary)
          .frame(width: 72, height: 72)
          .overlay {
            Image(systemName: "photo")
              .font(.tidexTitle2)
              .foregroundColor(.tidexTextMuted)
          }
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(.friendsChatPreviewImage)
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextPrimary)

        Text(ByteCountFormatter.string(fromByteCount: Int64(image.data.count), countStyle: .file))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .stroke(Color.tidexBorder.opacity(0.4), lineWidth: 1)
    )
  }
}

private struct FriendsThreadComposerReplyBanner: View {
  let preview: FriendsChatReplyPreviewModel
  let onCancel: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      HStack(alignment: .top, spacing: Spacing.xs) {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
          .fill(Color.tidexBlue.opacity(0.7))
          .frame(width: 3, height: 30)

        VStack(alignment: .leading, spacing: 3) {
          Text(preview.senderName)
            .font(.tidexCaptionStrong)
            .foregroundColor(.tidexBlue)

          HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
            if let iconSystemName = preview.iconPreviewKind?.friendsChatReplyIconSystemName {
              Image(systemName: iconSystemName)
                .font(.tidexCaptionRegular)
                .foregroundColor(.tidexTextMuted)
            }

            Text(preview.snippet)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfaceSecondary.opacity(0.72))
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(Color.tidexBorder.opacity(0.4), lineWidth: 1)
      )

      Button(action: onCancel) {
        Image(systemName: "xmark")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 32, height: 32)
          .background(
            Circle()
              .fill(Color.tidexSurfaceSecondary)
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: .commonCancel)))
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .stroke(Color.tidexBorder.opacity(0.45), lineWidth: 1)
    )
  }
}

private struct FriendsThreadComposerEditBanner: View {
  let onCancel: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: Spacing.sm) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "pencil")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexBlue)

        Text(
          String(localized: "friends.chat.composer.editing_message", table: "Localizable")
        )
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextPrimary)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfaceSecondary.opacity(0.72))
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(Color.tidexBorder.opacity(0.4), lineWidth: 1)
      )

      Button(action: onCancel) {
        Image(systemName: "xmark")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 32, height: 32)
          .background(
            Circle()
              .fill(Color.tidexSurfaceSecondary)
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        Text(String(localized: "friends.chat.composer.cancel_edit", table: "Localizable"))
      )
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .stroke(Color.tidexBorder.opacity(0.45), lineWidth: 1)
    )
  }
}

private struct FriendsThreadComposerHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
