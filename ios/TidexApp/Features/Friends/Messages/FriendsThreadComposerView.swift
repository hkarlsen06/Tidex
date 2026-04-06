import ExyteChat
import PhotosUI
import SwiftUI
import UIKit

private enum FriendsThreadComposerAccessibilityID {
  static let textField = "friends-thread-composer.text-field"
  static let sendButton = "friends-thread-composer.send-button"
  static let replyBanner = "friends-thread-composer.reply-banner"
  static let replyCancelButton = "friends-thread-composer.reply-cancel"
  static let attachmentToggleButton = "friends-thread-composer.attachment-toggle"
}

enum FriendsThreadComposerMode: Equatable {
  case normal
  case reply
  case edit
}

struct FriendsThreadComposerConfiguration: Equatable {
  let mode: FriendsThreadComposerMode
  let draftText: String
  let replyPreview: FriendsChatReplyPreviewModel?
  let stagedAttachments: [FriendsComposerAttachmentDraft]
  let isThreadReadOnly: Bool
  let sendErrorMessage: String?
  let composerValidationMessage: String?
  let draftCharacterCount: Int
  let draftCharacterLimit: Int
  let placeholder: String
  let canSendShiftSnapshots: Bool
  let focusRequestToken: Int
}

@MainActor
final class FriendsThreadComposerBridge: ObservableObject {
  private static let characterCountDisplayThresholdFraction = 0.8

  @Published private(set) var mode: FriendsThreadComposerMode = .normal
  @Published private(set) var draftText: String = ""
  @Published private(set) var replyPreview: FriendsChatReplyPreviewModel?
  @Published private(set) var stagedAttachments: [FriendsComposerAttachmentDraft] = []
  @Published private(set) var isThreadReadOnly = false
  @Published private(set) var sendErrorMessage: String?
  @Published private(set) var composerValidationMessage: String?
  @Published private(set) var draftCharacterCount = 0
  @Published private(set) var draftCharacterLimit = 0
  @Published private(set) var placeholder: String = ""
  @Published private(set) var canSendShiftSnapshots = false
  @Published private(set) var focusRequestToken = 0

  var onDraftChanged: ((String) -> Void)?
  var onStagedAttachmentsChanged: (([FriendsComposerAttachmentDraft]) -> Void)?
  var onCancelMode: (() -> Void)?
  var onSend: ((String) async -> Bool)?
  var onSaveEdit: ((String) async -> Bool)?
  var onPrepareShiftSnapshotAttachment:
    (
      (ShiftWithComputations) async
        -> FriendsComposerAttachmentDraft?
    )?
  var onFocusChanged: ((Bool) -> Void)?
  var onHeightChanged: ((CGFloat) -> Void)?
  var onAttachmentDrawerOpenChanged: ((Bool) -> Void)?

  private var isApplyingExternalDraft = false
  private var isApplyingExternalAttachments = false

  var isDraftOverCharacterLimit: Bool {
    draftCharacterCount > draftCharacterLimit
  }

  var shouldShowCharacterCount: Bool {
    guard draftCharacterCount > 0, draftCharacterLimit > 0 else { return false }
    return isDraftOverCharacterLimit
      || draftCharacterCount
        >= Int(
          Double(draftCharacterLimit) * Self.characterCountDisplayThresholdFraction
        )
  }

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
    composerValidationMessage = configuration.composerValidationMessage
    draftCharacterCount = configuration.draftCharacterCount
    draftCharacterLimit = configuration.draftCharacterLimit
    placeholder = configuration.placeholder
    canSendShiftSnapshots = configuration.canSendShiftSnapshots
    focusRequestToken = configuration.focusRequestToken

    if draftText != configuration.draftText {
      isApplyingExternalDraft = true
      draftText = configuration.draftText
      isApplyingExternalDraft = false
    }

    if stagedAttachments != configuration.stagedAttachments {
      isApplyingExternalAttachments = true
      stagedAttachments = configuration.stagedAttachments
      isApplyingExternalAttachments = false
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

  func reportFocusChanged(_ isFocused: Bool) {
    onFocusChanged?(isFocused)
  }

  func reportAttachmentDrawerOpen(_ isOpen: Bool) {
    onAttachmentDrawerOpenChanged?(isOpen)
  }

  func addImageAttachments(_ images: [ImageAttachment]) {
    guard !images.isEmpty else { return }

    let existingImages = stagedAttachments.imageAttachments
    let appendedImages = (existingImages + images).prefix(
      FriendsComposerAttachmentLimits.maxImagesPerMessage)
    updateStagedAttachments(appendedImages.map(FriendsComposerAttachmentDraft.image))
  }

  func prepareAndStageShiftAttachment(from shift: ShiftWithComputations) async -> Bool {
    guard let onPrepareShiftSnapshotAttachment else { return false }
    guard let attachment = await onPrepareShiftSnapshotAttachment(shift) else { return false }
    updateStagedAttachments([attachment])
    return true
  }

  func removeStagedAttachment(at index: Int) {
    guard stagedAttachments.indices.contains(index) else { return }
    var updatedAttachments = stagedAttachments
    updatedAttachments.remove(at: index)
    updateStagedAttachments(updatedAttachments)
  }

  private func updateDraftText(_ newValue: String) {
    guard draftText != newValue else { return }
    draftText = newValue
    guard !isApplyingExternalDraft else { return }
    onDraftChanged?(newValue)
  }

  private func updateStagedAttachments(_ newValue: [FriendsComposerAttachmentDraft]) {
    let normalizedAttachments = normalizedStagedAttachments(newValue)
    guard stagedAttachments != normalizedAttachments else { return }
    stagedAttachments = normalizedAttachments
    guard !isApplyingExternalAttachments else { return }
    onStagedAttachmentsChanged?(normalizedAttachments)
  }

  private func normalizedStagedAttachments(_ attachments: [FriendsComposerAttachmentDraft])
    -> [FriendsComposerAttachmentDraft]
  {
    if let shiftSnapshotDraft = attachments.shiftSnapshotDraft {
      return [.shiftSnapshot(shiftSnapshotDraft)]
    }

    return attachments.imageAttachments
      .uniquePayloads()
      .prefix(FriendsComposerAttachmentLimits.maxImagesPerMessage)
      .map(FriendsComposerAttachmentDraft.image)
  }
}

struct FriendsThreadComposerHostedView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var bridge: FriendsThreadComposerBridge
  let text: Binding<String>
  @StateObject private var attachmentController = FriendsComposerAttachmentController()
  @State private var selectedPhotoItems: [PhotosPickerItem] = []
  @State private var isSubmitting = false
  @State private var composerFocusTrigger = 0
  @State private var isComposerFocused = false
  @State private var isApplyingExternalDraft = false

  private let attachmentCollapseCharacterThreshold = 18

  private var canSend: Bool {
    let normalizedDraft = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return (!normalizedDraft.isEmpty || !bridge.stagedAttachments.isEmpty)
      && !bridge.isThreadReadOnly
      && !bridge.isDraftOverCharacterLimit
      && !isSubmitting
      && !attachmentController.isProcessingAttachment
  }

  private var isPreparingAttachmentDrawer: Bool {
    attachmentController.isDrawerOpen && attachmentController.recentPhotosState == .loading
  }

  private var shouldHidePlusButton: Bool {
    guard !attachmentController.isDrawerOpen else { return false }
    guard bridge.stagedAttachments.isEmpty else { return false }
    guard isComposerFocused else { return false }

    let draftLength = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).count
    return draftLength >= attachmentCollapseCharacterThreshold
      || text.wrappedValue.contains("\n")
  }

  private var stagedImageCount: Int {
    bridge.stagedAttachments.imageAttachments.count
  }

  private var hasShiftSnapshotAttachment: Bool {
    bridge.stagedAttachments.hasShiftSnapshot
  }

  private var canAddMoreImages: Bool {
    !hasShiftSnapshotAttachment
      && stagedImageCount < FriendsComposerAttachmentLimits.maxImagesPerMessage
  }

  private var remainingImageSelectionCapacity: Int {
    max(1, FriendsComposerAttachmentLimits.maxImagesPerMessage - stagedImageCount)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if bridge.mode == .reply,
        let replyPreview = bridge.replyPreview
      {
        FriendsThreadComposerReplyBanner(
          preview: replyPreview,
          onCancel: bridge.cancelMode
        )
        .padding(.horizontal, Spacing.md)
      } else if bridge.mode == .edit {
        FriendsThreadComposerEditBanner(onCancel: bridge.cancelMode)
          .padding(.horizontal, Spacing.md)
      }

      if !bridge.stagedAttachments.isEmpty {
        FriendsThreadComposerAttachmentPreview(
          attachments: bridge.stagedAttachments,
          onRemove: bridge.removeStagedAttachment(at:)
        )
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
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

      if shouldShowComposerMeta {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
          if let sendErrorMessage = bridge.sendErrorMessage {
            Text(sendErrorMessage)
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
          } else if let composerValidationMessage = bridge.composerValidationMessage {
            Text(composerValidationMessage)
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
          }

          Spacer(minLength: 0)

          if bridge.shouldShowCharacterCount {
            Text("\(bridge.draftCharacterCount)/\(bridge.draftCharacterLimit)")
              .font(.tidexFootnote)
              .foregroundColor(bridge.isDraftOverCharacterLimit ? .tidexError : .tidexTextMuted)
              .monospacedDigit()
          }
        }
        .padding(.horizontal, Spacing.md)
      }

      composerField

      if attachmentController.isDrawerOpen {
        FriendsThreadComposerAttachmentDrawer(
          recentPhotosState: attachmentController.recentPhotosState,
          recentPhotos: attachmentController.recentPhotos,
          isLoadingMoreRecentPhotos: attachmentController.isLoadingMoreRecentPhotos,
          isProcessingAttachment: attachmentController.isProcessingAttachment,
          showsShiftCalendarAction: bridge.canSendShiftSnapshots,
          stagedAttachments: bridge.stagedAttachments,
          canAddMoreImages: canAddMoreImages,
          onOpenPhotoLibrary: {
            guard canAddMoreImages else { return }
            attachmentController.isShowingPhotoLibrary = true
          },
          onOpenCamera: {
            guard canAddMoreImages else { return }
            attachmentController.isShowingCamera = true
          },
          onOpenShiftCalendar: {
            attachmentController.openShiftCalendar()
          },
          onSelectRecentPhoto: { photo in
            Task {
              await handleRecentPhotoSelection(photo)
            }
          },
          onRecentPhotoAppear: { photo in
            Task {
              await attachmentController.loadMoreRecentPhotosIfNeeded(currentPhotoID: photo.id)
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
    .onChange(of: selectedPhotoItems) { _, newItems in
      Task {
        await handleSelectedPhotoItems(newItems)
      }
    }
    .photosPicker(
      isPresented: $attachmentController.isShowingPhotoLibrary,
      selection: $selectedPhotoItems,
      maxSelectionCount: remainingImageSelectionCapacity,
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
      textFieldAccessibilityIdentifier: FriendsThreadComposerAccessibilityID.textField,
      actionButtonAccessibilityIdentifier: FriendsThreadComposerAccessibilityID.sendButton,
      submitLabel: .return,
      focusTrigger: composerFocusTrigger,
      onFocusChanged: {
        isComposerFocused = $0
        if $0, attachmentController.isDrawerOpen {
          attachmentController.closeDrawer()
        }
        bridge.reportFocusChanged($0)
      },
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

  private var shouldShowComposerMeta: Bool {
    bridge.sendErrorMessage != nil
      || bridge.composerValidationMessage != nil
      || bridge.shouldShowCharacterCount
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

  private func handleSelectedPhotoItems(_ items: [PhotosPickerItem]) async {
    guard !items.isEmpty else { return }
    let shouldRestoreFocus = isComposerFocused
    var imageAttachments: [ImageAttachment] = []

    for item in items.prefix(remainingImageSelectionCapacity) {
      guard let imageAttachment = await attachmentController.makeImageAttachment(from: item) else {
        continue
      }
      imageAttachments.append(imageAttachment)
    }

    guard !imageAttachments.isEmpty else {
      await MainActor.run {
        selectedPhotoItems = []
      }
      return
    }

    bridge.addImageAttachments(imageAttachments)
    await MainActor.run {
      selectedPhotoItems = []
      attachmentController.completeAttachmentSelection(shouldCloseDrawer: false)
      restoreComposerFocusIfNeeded(shouldRestoreFocus)
    }
  }

  private func handleRecentPhotoSelection(_ photo: FriendsComposerRecentPhoto) async {
    guard canAddMoreImages else { return }
    let shouldRestoreFocus = isComposerFocused
    guard let imageAttachment = await attachmentController.makeImageAttachment(from: photo) else {
      return
    }

    bridge.addImageAttachments([imageAttachment])
    attachmentController.completeAttachmentSelection(shouldCloseDrawer: false)
    restoreComposerFocusIfNeeded(shouldRestoreFocus)
  }

  private func handleCapturedImage(_ image: UIImage) async {
    guard canAddMoreImages else { return }
    let shouldRestoreFocus = isComposerFocused
    guard let imageAttachment = await attachmentController.makeImageAttachment(from: image) else {
      return
    }

    bridge.addImageAttachments([imageAttachment])
    attachmentController.completeAttachmentSelection(shouldCloseDrawer: false)
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
    Task {
      if !attachmentController.isDrawerOpen {
        await MainActor.run {
          dismissKeyboard()
        }
      }
      await attachmentController.toggleDrawer()
    }
  }

  private func syncTextFromBridgeIfNeeded() {
    guard text.wrappedValue != bridge.draftText else { return }
    isApplyingExternalDraft = true
    text.wrappedValue = bridge.draftText
    isApplyingExternalDraft = false
  }

  private func dismissKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}

private struct FriendsThreadComposerPlusButton: View {
  let isOpen: Bool
  let isDisabled: Bool
  let isPreparing: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
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
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
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
    .accessibilityIdentifier(FriendsThreadComposerAccessibilityID.attachmentToggleButton)
  }
}

private struct FriendsThreadComposerAttachmentDrawer: View {
  private enum Layout {
    static let previewWidth: CGFloat = 144
    static let previewHeight: CGFloat = 192
  }

  let recentPhotosState: FriendsComposerRecentPhotosState
  let recentPhotos: [FriendsComposerRecentPhoto]
  let isLoadingMoreRecentPhotos: Bool
  let isProcessingAttachment: Bool
  let showsShiftCalendarAction: Bool
  let stagedAttachments: [FriendsComposerAttachmentDraft]
  let canAddMoreImages: Bool
  let onOpenPhotoLibrary: () -> Void
  let onOpenCamera: () -> Void
  let onOpenShiftCalendar: () -> Void
  let onSelectRecentPhoto: (FriendsComposerRecentPhoto) -> Void
  let onRecentPhotoAppear: (FriendsComposerRecentPhoto) -> Void

  private var hasShiftSnapshotAttachment: Bool {
    stagedAttachments.hasShiftSnapshot
  }

  private var hasImageAttachments: Bool {
    stagedAttachments.hasImageAttachments
  }

  private var canStageShiftSnapshot: Bool {
    !hasImageAttachments
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(spacing: Spacing.sm) {
        actionButton(
          systemName: "photo.on.rectangle.angled",
          isActive: hasImageAttachments,
          isDisabled: !canAddMoreImages,
          accessibilityLabel: String(
            localized: "friends.chat.composer.photo_library",
            table: "Localizable"
          ),
          action: onOpenPhotoLibrary
        )

        actionButton(
          systemName: "camera",
          isActive: false,
          isDisabled: !canAddMoreImages,
          accessibilityLabel: String(
            localized: "friends.chat.composer.camera",
            table: "Localizable"
          ),
          action: onOpenCamera
        )

        if showsShiftCalendarAction {
          actionButton(
            systemName: "calendar",
            isActive: hasShiftSnapshotAttachment,
            isDisabled: !canStageShiftSnapshot,
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
                .disabled(isProcessingAttachment || !canAddMoreImages)
                .onAppear {
                  onRecentPhotoAppear(photo)
                }
              }

              if isLoadingMoreRecentPhotos {
                VStack {
                  ProgressView()
                    .controlSize(.regular)
                }
                .frame(width: Layout.previewWidth, height: Layout.previewHeight)
                .background(
                  RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(Color.tidexSurfaceSecondary)
                )
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
      .frame(maxWidth: .infinity)
      .frame(height: Layout.previewHeight)
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
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  private func actionButton(
    systemName: String,
    isActive: Bool,
    isDisabled: Bool,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(
          isDisabled ? .tidexTextMuted : (isActive ? .tidexBlue : .tidexTextPrimary)
        )
        .frame(width: 40, height: 40)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .fill(
              isDisabled
                ? Color.tidexSurfaceSecondary.opacity(0.65)
                : (isActive ? Color.tidexBlue.opacity(0.14) : Color.tidexSurfaceSecondary)
            )
        )
    }
    .buttonStyle(.plain)
    .disabled(isProcessingAttachment || isDisabled)
    .accessibilityLabel(Text(accessibilityLabel))
  }
}

private struct FriendsThreadComposerAttachmentPreview: View {
  let attachments: [FriendsComposerAttachmentDraft]
  let onRemove: (Int) -> Void

  var body: some View {
    if attachments.count == 1, let attachment = attachments.first, attachment.shiftSnapshot != nil {
      Group {
        switch attachment {
        case .shiftSnapshot(let draft):
          FriendsThreadComposerDismissibleCard(
            onDismiss: { onRemove(0) },
            accessibilityLabel: String(localized: .friendsChatComposerRemoveAttachment)
          ) {
            ChatShiftSnapshotCard(
              snapshot: draft.snapshot,
              isCurrentUser: false
            )
          }
        case .image:
          EmptyView()
        }
      }
    } else {
      FriendsThreadComposerImageAttachmentsCard(
        attachments: attachments.enumerated().compactMap { index, attachment in
          guard let image = attachment.imageAttachment else { return nil }
          return FriendsThreadComposerIndexedImageAttachment(index: index, image: image)
        },
        onRemove: onRemove
      )
    }
  }
}

private struct FriendsThreadComposerIndexedImageAttachment: Identifiable {
  let index: Int
  let image: ImageAttachment

  var id: String {
    image.id
  }
}

private struct FriendsThreadComposerImageAttachmentsCard: View {
  private enum Layout {
    static let maxTileSize: CGFloat = 88
  }

  let attachments: [FriendsThreadComposerIndexedImageAttachment]
  let onRemove: (Int) -> Void

  var body: some View {
    let tileSize = resolvedTileSize(for: maxPreviewRowWidth)
    let rowWidth = resolvedRowWidth(for: tileSize)

    HStack(spacing: Spacing.sm) {
      ForEach(attachments) { attachment in
        FriendsThreadComposerImageThumbnail(
          image: attachment.image,
          sideLength: tileSize,
          onRemove: { onRemove(attachment.index) }
        )
      }
    }
    .frame(width: rowWidth, alignment: .leading)
    .fixedSize(horizontal: true, vertical: false)
  }

  private var maxPreviewRowWidth: CGFloat {
    max(Layout.maxTileSize, currentWindowWidth - (Spacing.md * 2))
  }

  private var currentWindowWidth: CGFloat {
    let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = windowScenes.flatMap(\.windows)

    if let keyWindowWidth = windows.first(where: \.isKeyWindow)?.bounds.width {
      return keyWindowWidth
    }

    if let windowWidth = windows.first?.bounds.width {
      return windowWidth
    }

    return windowScenes.first?.screen.bounds.width ?? Layout.maxTileSize
  }

  private func resolvedTileSize(for availableWidth: CGFloat) -> CGFloat {
    guard !attachments.isEmpty else { return Layout.maxTileSize }

    let spacing = Spacing.sm * CGFloat(max(attachments.count - 1, 0))
    let rawTileSize = (availableWidth - spacing) / CGFloat(attachments.count)
    return min(Layout.maxTileSize, max(56, floor(rawTileSize)))
  }

  private func resolvedRowWidth(for tileSize: CGFloat) -> CGFloat {
    guard !attachments.isEmpty else { return tileSize }
    return (tileSize * CGFloat(attachments.count))
      + (Spacing.sm * CGFloat(max(attachments.count - 1, 0)))
  }
}

private struct FriendsThreadComposerImageThumbnail: View {
  let image: ImageAttachment
  let sideLength: CGFloat
  let onRemove: () -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      thumbnailContent

      VStack {
        HStack {
          Spacer(minLength: 0)

          Button(action: onRemove) {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .bold))
              .foregroundColor(.white)
              .frame(width: 24, height: 24)
              .background(
                Circle()
                  .fill(Color.black.opacity(0.46))
              )
              .overlay(
                Circle()
                  .stroke(Color.white.opacity(0.16), lineWidth: 1)
              )
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(.friendsChatComposerRemoveAttachment))
        }

        Spacer(minLength: 0)
      }
      .padding(6)

      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.tidexBorder.opacity(0.28), lineWidth: 1)

    }
  }

  @ViewBuilder
  private var thumbnailContent: some View {
    if let uiImage = UIImage(data: image.data) {
      Image(uiImage: uiImage)
        .resizable()
        .scaledToFill()
        .frame(width: sideLength, height: sideLength)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    } else {
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .fill(Color.tidexSurfaceSecondary)
        .frame(width: sideLength, height: sideLength)
        .overlay {
          Image(systemName: "photo")
            .font(.tidexTitle2)
            .foregroundColor(.tidexTextMuted)
        }
    }
  }
}

private struct FriendsThreadComposerReplyBanner: View {
  let preview: FriendsChatReplyPreviewModel
  let onCancel: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.xs) {
      RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
        .fill(Color.tidexBlue.opacity(0.7))
        .frame(width: 3)

      FriendsChatReplyPreviewContent(
        preview: preview,
        isCurrentUser: false,
        accentColor: .tidexBlue,
        textColor: .tidexTextMuted,
        snippetLineLimit: 1,
        thumbnailSize: CGSize(width: 56, height: 56),
        hidesImageOnlySnippet: true
      )

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
    .overlay(alignment: .topTrailing) {
      Button(action: onCancel) {
        Image(systemName: "xmark")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 28, height: 28)
          .background(
            Circle()
              .fill(Color.tidexSurfaceSecondary)
          )
          .overlay(
            Circle()
              .stroke(Color.tidexBorder.opacity(0.4), lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: .commonCancel)))
      .accessibilityIdentifier(FriendsThreadComposerAccessibilityID.replyCancelButton)
      .padding(Spacing.xs)
    }
    .accessibilityIdentifier(FriendsThreadComposerAccessibilityID.replyBanner)
  }
}

private struct FriendsThreadComposerDismissibleCard<Content: View>: View {
  let onDismiss: () -> Void
  let accessibilityLabel: String
  var dismissAccessibilityIdentifier: String? = nil
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .padding(.trailing, 40)
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
      .overlay(alignment: .topTrailing) {
        dismissButton
          .padding(Spacing.xs)
      }
  }

  @ViewBuilder
  private var dismissButton: some View {
    if let dismissAccessibilityIdentifier {
      dismissButtonBody
        .accessibilityIdentifier(dismissAccessibilityIdentifier)
    } else {
      dismissButtonBody
    }
  }

  private var dismissButtonBody: some View {
    Button(action: onDismiss) {
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
    .accessibilityLabel(Text(accessibilityLabel))
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
