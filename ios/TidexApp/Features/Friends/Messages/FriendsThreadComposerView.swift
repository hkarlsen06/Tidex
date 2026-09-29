import ExyteChat
import PhotosUI
import SwiftUI
import UIKit

private enum FriendsThreadComposerAccessibilityID {
  static let textField = "friends-thread-composer.text-field"
  static let sendButton = "friends-thread-composer.send-button"
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
final class FriendsThreadComposerBridge {
  var onDraftChanged: ((String) -> Void)?
  var onStagedAttachmentsChanged: (([FriendsComposerAttachmentDraft]) -> Void)?
  var stagedAttachmentsProvider: (() -> [FriendsComposerAttachmentDraft])?
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
    DispatchQueue.main.async {
      self.onFocusChanged?(isFocused)
    }
  }

  func reportAttachmentDrawerOpen(_ isOpen: Bool) {
    DispatchQueue.main.async {
      self.onAttachmentDrawerOpenChanged?(isOpen)
    }
  }

  func currentStagedAttachments() -> [FriendsComposerAttachmentDraft] {
    stagedAttachmentsProvider?() ?? []
  }

  func addImageAttachments(
    _ images: [ImageAttachment],
    to existingAttachments: [FriendsComposerAttachmentDraft]
  ) -> [FriendsComposerAttachmentDraft] {
    guard !images.isEmpty else { return existingAttachments }

    let existingImages = existingAttachments.imageAttachments
    let appendedImages = (existingImages + images).prefix(
      FriendsComposerAttachmentLimits.maxImagesPerMessage)
    return normalizedStagedAttachments(appendedImages.map(FriendsComposerAttachmentDraft.image))
  }

  func prepareShiftAttachment(
    from shift: ShiftWithComputations
  ) async -> FriendsComposerAttachmentDraft? {
    guard let onPrepareShiftSnapshotAttachment else { return nil }
    return await onPrepareShiftSnapshotAttachment(shift)
  }

  func removeStagedAttachment(
    at index: Int,
    from attachments: [FriendsComposerAttachmentDraft]
  ) -> [FriendsComposerAttachmentDraft] {
    guard attachments.indices.contains(index) else { return attachments }
    var updatedAttachments = attachments
    updatedAttachments.remove(at: index)
    return normalizedStagedAttachments(updatedAttachments)
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

extension FriendsThreadComposerConfiguration {
  private static let characterCountDisplayThresholdFraction = 0.8

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
}

struct FriendsThreadComposerHostedView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let configuration: FriendsThreadComposerConfiguration
  let bridge: FriendsThreadComposerBridge
  let text: Binding<String>
  @State private var attachmentController = FriendsComposerAttachmentController()
  private let orientationTracker = OrientationTracker.shared
  @State private var selectedPhotoItems: [PhotosPickerItem] = []
  @State private var isSubmitting = false
  @State private var composerFocusTrigger = 0
  @State private var isComposerFocused = false

  private let attachmentCollapseCharacterThreshold = 18

  private var isIPadLandscape: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && orientationTracker.isLandscape
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      modeBanner

      if !configuration.stagedAttachments.isEmpty {
        FriendsThreadComposerAttachmentPreview(
          attachments: configuration.stagedAttachments,
          onRemove: removeStagedAttachment(at:)
        )
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      readOnlyNotice

      composerMeta

      composerField

      attachmentDrawer
    }
    .animation(
      reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86),
      value: attachmentController.isDrawerOpen
    )
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: isIPadLandscape ? AdaptiveMaxWidth.tabContent : .infinity)
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
    .task(id: configuration.draftText) {
      syncTextFromConfigurationIfNeeded()
    }
    .onChange(of: attachmentController.isDrawerOpen) { _, isOpen in
      bridge.reportAttachmentDrawerOpen(isOpen)
    }
    .onChange(of: configuration.focusRequestToken) { _, _ in
      composerFocusTrigger += 1
    }
    .onChange(of: configuration.mode) { _, newMode in
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

  @ViewBuilder
  private var modeBanner: some View {
    if configuration.mode == .reply,
      let replyPreview = configuration.replyPreview
    {
      FriendsThreadComposerReplyBanner(
        preview: replyPreview,
        onCancel: bridge.cancelMode
      )
      .padding(.horizontal, Spacing.md)
    } else if configuration.mode == .edit {
      FriendsThreadComposerEditBanner(onCancel: bridge.cancelMode)
        .padding(.horizontal, Spacing.md)
    }
  }

  @ViewBuilder
  private var readOnlyNotice: some View {
    if configuration.isThreadReadOnly {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "hand.raised.fill")
          .foregroundColor(.tidexWarning)
          .accessibilityHidden(true)

        Text(.friendsChatBlockedReadOnly)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)

        Spacer()
      }
      .padding(.horizontal, Spacing.md)
    }
  }

  @ViewBuilder
  private var composerMeta: some View {
    if shouldShowComposerMeta {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
        if let sendErrorMessage = configuration.sendErrorMessage {
          Text(sendErrorMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)
            .announcesToVoiceOver(sendErrorMessage)
        } else if let composerValidationMessage = configuration.composerValidationMessage {
          Text(composerValidationMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)
            .announcesToVoiceOver(composerValidationMessage)
        }

        Spacer(minLength: 0)

        if configuration.shouldShowCharacterCount {
          Text("\(configuration.draftCharacterCount)/\(configuration.draftCharacterLimit)")
            .font(.tidexFootnote)
            .foregroundColor(
              configuration.isDraftOverCharacterLimit ? .tidexError : .tidexTextMuted
            )
            .monospacedDigit()
        }
      }
      .padding(.horizontal, Spacing.md)
    }
  }

  @ViewBuilder
  private var attachmentDrawer: some View {
    if attachmentController.isDrawerOpen {
      FriendsThreadComposerAttachmentDrawer(
        selectedPhotoItems: $selectedPhotoItems,
        remainingImageSelectionCapacity: remainingImageSelectionCapacity,
        isProcessingAttachment: attachmentController.isProcessingAttachment,
        showsShiftCalendarAction: configuration.canSendShiftSnapshots,
        stagedAttachments: configuration.stagedAttachments,
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
        }
      )
      .padding(.horizontal, Spacing.md)
      .padding(.bottom, Spacing.sm)
      .transition(MotionTokens.mirroredMoveTransition(edge: .bottom, reduceMotion: reduceMotion))
    }
  }

  private var composerField: some View {
    ChatComposerField(
      text: composerTextBinding,
      placeholder: configuration.placeholder,
      disabled: configuration.isThreadReadOnly || attachmentController.isProcessingAttachment,
      isSending: isSubmitting,
      canPerformAction: canSend,
      actionAccessibilityLabel: configuration.mode == .edit
        ? String(localized: .friendsChatComposerSaveEdit)
        : String(localized: .commonSendMessage),
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
          isDisabled: configuration.isThreadReadOnly || attachmentController.isProcessingAttachment
            || configuration.mode == .edit,
          action: toggleAttachmentDrawer
        )
        .transition(
          MotionTokens.mirroredMoveTransition(edge: .leading, reduceMotion: reduceMotion))
      }
    }
    .animation(
      reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.9),
      value: shouldHidePlusButton
    )
  }

  private var shouldShowComposerMeta: Bool {
    configuration.sendErrorMessage != nil
      || configuration.composerValidationMessage != nil
      || configuration.shouldShowCharacterCount
  }
}

extension FriendsThreadComposerHostedView {
  private var composerText: String {
    text.wrappedValue
  }

  private var composerTextBinding: Binding<String> {
    Binding(
      get: { composerText },
      set: { newValue in
        if text.wrappedValue != newValue {
          text.wrappedValue = newValue
        }
        if configuration.draftText != newValue {
          bridge.onDraftChanged?(newValue)
        }
      }
    )
  }

  private var canSend: Bool {
    let normalizedDraft = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    return (!normalizedDraft.isEmpty || !configuration.stagedAttachments.isEmpty)
      && !configuration.isThreadReadOnly
      && !configuration.isDraftOverCharacterLimit
      && !isSubmitting
      && !attachmentController.isProcessingAttachment
  }

  private var shouldHidePlusButton: Bool {
    guard configuration.mode == .normal else { return false }
    guard !attachmentController.isDrawerOpen else { return false }
    guard configuration.stagedAttachments.isEmpty else { return false }
    guard isComposerFocused else { return false }

    let draftLength = composerText.trimmingCharacters(in: .whitespacesAndNewlines).count
    return draftLength >= attachmentCollapseCharacterThreshold
      || composerText.contains("\n")
  }

  private var stagedImageCount: Int {
    configuration.stagedAttachments.imageAttachments.count
  }

  private var hasShiftSnapshotAttachment: Bool {
    configuration.stagedAttachments.hasShiftSnapshot
  }

  private var canAddMoreImages: Bool {
    !hasShiftSnapshotAttachment
      && stagedImageCount < FriendsComposerAttachmentLimits.maxImagesPerMessage
  }

  private var remainingImageSelectionCapacity: Int {
    max(1, FriendsComposerAttachmentLimits.maxImagesPerMessage - stagedImageCount)
  }

  private func sendMessage() {
    guard canSend else { return }

    if configuration.mode == .edit {
      isSubmitting = true

      Task {
        let didSave = await bridge.saveEdit(
          content: composerText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        content: composerText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    let updatedAttachments = bridge.addImageAttachments(
      imageAttachments,
      to: bridge.currentStagedAttachments()
    )
    bridge.onStagedAttachmentsChanged?(updatedAttachments)
    await MainActor.run {
      selectedPhotoItems = []
      attachmentController.completeAttachmentSelection(shouldCloseDrawer: false)
      restoreComposerFocusIfNeeded(shouldRestoreFocus)
    }
  }

  private func handleCapturedImage(_ image: UIImage) async {
    guard canAddMoreImages else { return }
    let shouldRestoreFocus = isComposerFocused
    guard let imageAttachment = await attachmentController.makeImageAttachment(from: image) else {
      return
    }

    let updatedAttachments = bridge.addImageAttachments(
      [imageAttachment],
      to: bridge.currentStagedAttachments()
    )
    bridge.onStagedAttachmentsChanged?(updatedAttachments)
    attachmentController.completeAttachmentSelection(shouldCloseDrawer: false)
    restoreComposerFocusIfNeeded(shouldRestoreFocus)
  }

  private func handleShiftSelection(_ shift: ShiftWithComputations) async -> Bool {
    guard attachmentController.beginProcessingAttachment() else { return false }

    let shouldRestoreFocus = isComposerFocused
    defer {
      attachmentController.finishProcessingAttachment()
    }

    guard let attachment = await bridge.prepareShiftAttachment(from: shift) else {
      return false
    }

    bridge.onStagedAttachmentsChanged?([attachment])
    attachmentController.completeAttachmentSelection()
    restoreComposerFocusIfNeeded(shouldRestoreFocus)
    return true
  }

  private func removeStagedAttachment(at index: Int) {
    let updatedAttachments = bridge.removeStagedAttachment(
      at: index,
      from: configuration.stagedAttachments
    )
    guard updatedAttachments != configuration.stagedAttachments else { return }
    bridge.onStagedAttachmentsChanged?(updatedAttachments)
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
    if !attachmentController.isDrawerOpen {
      dismissKeyboard()
    }
    attachmentController.toggleDrawer()
  }

  private func syncTextFromConfigurationIfNeeded() {
    guard text.wrappedValue != configuration.draftText else { return }
    text.wrappedValue = configuration.draftText
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
  @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 20

  let isOpen: Bool
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: iconSize, weight: .semibold))
        .foregroundColor(isDisabled ? .tidexTextMuted : .tidexBlueText)
        .rotationEffect(.degrees(isOpen ? 45 : 0))
        .frame(minWidth: 44, minHeight: 44)
        .background(
          Circle()
            .fill(isOpen ? Color.tidexBlue.opacity(0.28) : Color.tidexBlue.opacity(0.2))
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
    static let previewHeight: CGFloat = 192
  }

  @Binding var selectedPhotoItems: [PhotosPickerItem]
  let remainingImageSelectionCapacity: Int
  let isProcessingAttachment: Bool
  let showsShiftCalendarAction: Bool
  let stagedAttachments: [FriendsComposerAttachmentDraft]
  let canAddMoreImages: Bool
  let onOpenPhotoLibrary: () -> Void
  let onOpenCamera: () -> Void
  let onOpenShiftCalendar: () -> Void

  @ScaledMetric(relativeTo: .body) private var actionIconSize: CGFloat = 18

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
      actionButtons

      photoCarousel
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .stroke(Color.tidexBorder, lineWidth: 1)
    )
  }

  private var actionButtons: some View {
    HStack(spacing: Spacing.sm) {
      actionButton(
        systemName: "photo.on.rectangle.angled",
        isActive: hasImageAttachments,
        isDisabled: !canAddMoreImages,
        accessibilityLabel: String(localized: .friendsChatComposerPhotoLibrary),
        action: onOpenPhotoLibrary
      )

      actionButton(
        systemName: "camera",
        isActive: false,
        isDisabled: !canAddMoreImages,
        accessibilityLabel: String(localized: .friendsChatComposerCamera),
        action: onOpenCamera
      )

      if showsShiftCalendarAction {
        actionButton(
          systemName: "calendar",
          isActive: hasShiftSnapshotAttachment,
          isDisabled: !canStageShiftSnapshot,
          accessibilityLabel: String(localized: .friendsChatComposerShiftCalendar),
          action: onOpenShiftCalendar
        )
      }
    }
  }

  private var photoCarousel: some View {
    PhotosPicker(
      selection: $selectedPhotoItems,
      maxSelectionCount: remainingImageSelectionCapacity,
      matching: .images
    ) {
      EmptyView()
    }
    .photosPickerStyle(.compact)
    .photosPickerAccessoryVisibility(.hidden, edges: .all)
    .disabled(isProcessingAttachment || !canAddMoreImages)
    .opacity(isProcessingAttachment || !canAddMoreImages ? 0.55 : 1)
    .frame(maxWidth: .infinity)
    .frame(height: Layout.previewHeight)
    .overlay {
      FriendsChatGestureTargetSurface(targetKind: .attachmentPhotoCarousel)
        .allowsHitTesting(false)
    }
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
        .font(.system(size: actionIconSize, weight: .semibold))
        .foregroundColor(
          isDisabled ? .tidexTextMuted : (isActive ? .tidexBlueText : .tidexTextPrimary)
        )
        .frame(minWidth: 40, minHeight: 40)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .fill(
              isDisabled
                ? Color.tidexSurfaceSecondary.opacity(0.65)
                : (isActive ? Color.tidexBlue.opacity(0.14) : Color.tidexSurfaceSecondary)
            )
        )
        .contentShape(Rectangle().inset(by: -2))
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
      ForEach(Array(attachments.enumerated()), id: \.element.id) { position, attachment in
        FriendsThreadComposerImageThumbnail(
          image: attachment.image,
          sideLength: tileSize,
          position: position + 1,
          total: attachments.count,
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
  @ScaledMetric(relativeTo: .caption2) private var removeIconSize: CGFloat = 10

  let image: ImageAttachment
  let sideLength: CGFloat
  let position: Int
  let total: Int
  let onRemove: () -> Void

  /// "Photo 2 of 3", or just "Photo" when it is the only one.
  private var photoLabel: String {
    let photo = String(localized: .friendsChatPreviewImage)
    guard total > 1 else { return photo }
    return FriendsChatMessageAccessibility.join([
      photo, String(localized: .friendsAccessibilityPosition(position, total)),
    ])
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      thumbnailContent

      VStack {
        HStack {
          Spacer(minLength: 0)

          removeButton
        }

        Spacer(minLength: 0)
      }
      .padding(6)

      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.tidexBorder, lineWidth: 1)

    }
  }

  private var removeButton: some View {
    Button(action: onRemove) {
      Image(systemName: "xmark")
        .font(.system(size: removeIconSize, weight: .bold))
        .foregroundColor(.white)
        .frame(minWidth: 24, minHeight: 24)
        .background(
          Circle()
            .fill(Color.black.opacity(0.46))
        )
        .overlay(
          Circle()
            .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        // The visible circle stays 24pt. The tap area is 44pt.
        .contentShape(Rectangle().inset(by: -10))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      FriendsChatMessageAccessibility.join([
        String(localized: .friendsChatComposerRemoveAttachment), photoLabel,
      ])
    )
  }

  @ViewBuilder
  private var thumbnailContent: some View {
    if let uiImage = UIImage(data: image.data) {
      Image(uiImage: uiImage)
        .resizable()
        .scaledToFill()
        .frame(width: sideLength, height: sideLength)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .accessibilityLabel(photoLabel)
        .accessibilityAddTraits(.isImage)
    } else {
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .fill(Color.tidexSurfaceSecondary)
        .frame(width: sideLength, height: sideLength)
        .overlay {
          Image(systemName: "photo")
            .font(.tidexTitle2)
            .foregroundColor(.tidexTextMuted)
            .accessibilityLabel(photoLabel)
        }
    }
  }
}

private struct FriendsThreadComposerReplyBanner: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let preview: FriendsChatReplyPreviewModel
  let onCancel: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.xs) {
      RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
        .fill(Color.tidexBlue)
        .frame(width: 3)

      FriendsChatReplyPreviewContent(
        preview: preview,
        isCurrentUser: false,
        accentColor: .tidexBlueText,
        textColor: .tidexTextMuted,
        snippetLineLimit: dynamicTypeSize.isAccessibilitySize ? 3 : 1,
        thumbnailSize: CGSize(width: 56, height: 56),
        hidesImageOnlySnippet: true
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        FriendsChatMessageAccessibility.join([
          "\(String(localized: .friendsChatReplyTo)) \(preview.senderName)", preview.snippet,
        ])
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
        .stroke(Color.tidexBorder, lineWidth: 1)
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
              .stroke(Color.tidexBorder, lineWidth: 1)
          )
          .contentShape(Rectangle().inset(by: -8))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.friendsAccessibilityCancelReply))
      .accessibilityIdentifier(FriendsThreadComposerAccessibilityID.replyCancelButton)
      .padding(Spacing.xs)
    }
  }
}

private struct FriendsThreadComposerDismissibleCard<Content: View>: View {
  let onDismiss: () -> Void
  let accessibilityLabel: String
  var dismissAccessibilityIdentifier: String?
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
          .stroke(Color.tidexBorder, lineWidth: 1)
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
            .stroke(Color.tidexBorder, lineWidth: 1)
        )
        .contentShape(Rectangle().inset(by: -6))
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
          .foregroundColor(.tidexBlueText)
          .accessibilityHidden(true)

        Text(
          String(localized: .friendsChatComposerEditingMessage)
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
          .stroke(Color.tidexBorder, lineWidth: 1)
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
          .contentShape(Rectangle().inset(by: -6))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        Text(.friendsChatComposerCancelEdit)
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
        .stroke(Color.tidexBorder, lineWidth: 1)
    )
  }
}

private struct FriendsThreadComposerHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
