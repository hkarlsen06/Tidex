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
    // Rows above the field sit outside the scroll view. A scroll view lays its
    // content out from the top, so a row appearing inside it would shift the
    // field and drawer for a frame before they settle.
    VStack(alignment: .leading, spacing: Spacing.xs) {
      modeBanner

      stagedAttachmentPreview

      readOnlyNotice

      composerMeta

      composerScrollView
    }
    // The preview row grows and shrinks the composer, so ease it in and out
    // instead of snapping.
    .animation(
      reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86),
      value: configuration.stagedAttachments
    )
    // Size every row to its content. The chat overlay offers the full screen height.
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
    .onChange(of: configuration.stagedAttachments) { _, stagedAttachments in
      // A thumbnail removed or a message sent also clears the photo's checkmark.
      deselectUnstagedPhotos(in: stagedAttachments)
    }
    .photosPicker(
      isPresented: $attachmentController.isShowingPhotoLibrary,
      selection: $selectedPhotoItems,
      maxSelectionCount: max(1, photoPickerSelectionLimit),
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

  /// A drag down on the field or drawer drives the interactive keyboard dismissal
  /// the same way a drag on the message list does, and a pull up focuses the field.
  private var composerScrollView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        composerField

        attachmentDrawer
      }
      .animation(
        reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86),
        value: attachmentController.isDrawerOpen
      )
      .fixedSize(horizontal: false, vertical: true)
      .visualEffect { content, proxy in
        // Cancel the scroll so only the keyboard follows the finger.
        content.offset(y: -proxy.frame(in: .scrollView).minY)
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y > FriendsThreadChatViewportResolver.pullUpToFocusThreshold
    } action: { _, isPulledUp in
      if isPulledUp, !isComposerFocused {
        composerFocusTrigger += 1
      }
    }
    .scrollBounceBehavior(.always, axes: .vertical)
    .scrollIndicators(.hidden)
    .scrollClipDisabled()
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private var stagedAttachmentPreview: some View {
    if !configuration.stagedAttachments.isEmpty {
      FriendsThreadComposerAttachmentPreview(
        attachments: configuration.stagedAttachments,
        onRemove: removeStagedAttachment(at:)
      )
      .padding(.horizontal, Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .transition(
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .bottom))
      )
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
        photoPickerSelectionLimit: max(1, photoPickerSelectionLimit),
        canUsePhotoPicker: canUsePhotoPicker,
        isProcessingAttachment: attachmentController.isProcessingAttachment,
        showsShiftCalendarAction: configuration.canSendShiftSnapshots,
        stagedAttachments: configuration.stagedAttachments,
        canAddMoreImages: canAddMoreImages,
        onOpenPhotoLibrary: {
          guard canUsePhotoPicker else { return }
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
      // Match the unfocused field row so the panel lines up with the plus button.
      .padding(.horizontal, MonthPickerLayout.horizontalPadding)
      .padding(.bottom, Spacing.sm)
      .transition(
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Spacing.lg))
      )
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

  /// How many photos the picker may hold: the image limit minus the images that did not
  /// come from the picker, such as camera shots and restored drafts.
  private var photoPickerSelectionLimit: Int {
    let pickedAttachmentIDs = Set(attachmentController.pickedAttachmentIDs.values)
    let otherImageCount = configuration.stagedAttachments.imageAttachments
      .filter { !pickedAttachmentIDs.contains($0.id) }
      .count
    return FriendsComposerAttachmentLimits.maxImagesPerMessage - otherImageCount
  }

  private var canUsePhotoPicker: Bool {
    !hasShiftSnapshotAttachment && photoPickerSelectionLimit > 0
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

  /// The picker selection mirrors the photos in the draft: a newly selected photo is
  /// attached, and a deselected one is removed.
  private func handleSelectedPhotoItems(_ items: [PhotosPickerItem]) async {
    let shouldRestoreFocus = isComposerFocused
    let deselectedAttachmentIDs = attachmentController.releaseDeselectedPhotos(
      selectedPickerItemIDs: Set(items.compactMap(\.itemIdentifier))
    )
    let newItems = items.filter { item in
      guard let pickerItemID = item.itemIdentifier else { return true }
      return attachmentController.pickedAttachmentIDs[pickerItemID] == nil
    }

    var pickedImages: [(pickerItemID: String?, image: ImageAttachment)] = []
    var itemsToDeselect: [PhotosPickerItem] = []
    for item in newItems {
      guard let image = await attachmentController.makeImageAttachment(from: item) else {
        itemsToDeselect.append(item)
        continue
      }
      pickedImages.append((item.itemIdentifier, image))
    }
    // Another run may have deselected a photo while it loaded. Attaching it anyway
    // would put a photo in the draft that shows no checkmark.
    pickedImages.removeAll { picked in
      guard let pickerItemID = picked.pickerItemID else { return false }
      return !selectedPhotoItems.contains { $0.itemIdentifier == pickerItemID }
    }

    if !deselectedAttachmentIDs.isEmpty || !pickedImages.isEmpty {
      stagePickedImages(pickedImages, removingAttachmentIDs: deselectedAttachmentIDs)
    }

    itemsToDeselect += newItems.filter { $0.itemIdentifier == nil }
    if !itemsToDeselect.isEmpty {
      selectedPhotoItems.removeAll { itemsToDeselect.contains($0) }
    }

    if !pickedImages.isEmpty {
      attachmentController.completeAttachmentSelection(shouldCloseDrawer: false)
      restoreComposerFocusIfNeeded(shouldRestoreFocus)
    }
  }

  private func stagePickedImages(
    _ pickedImages: [(pickerItemID: String?, image: ImageAttachment)],
    removingAttachmentIDs removedAttachmentIDs: Set<String>
  ) {
    var stagedAttachments = bridge.currentStagedAttachments()
    stagedAttachments.removeAll { attachment in
      attachment.imageAttachment.map { removedAttachmentIDs.contains($0.id) } ?? false
    }
    for picked in pickedImages {
      // A photo without a library identifier can't stay selected, so it is only attached.
      guard let pickerItemID = picked.pickerItemID else { continue }
      attachmentController.recordPickedAttachment(picked.image.id, forPickerItemID: pickerItemID)
    }
    let updatedAttachments = bridge.addImageAttachments(
      pickedImages.map(\.image),
      to: stagedAttachments
    )
    bridge.onStagedAttachmentsChanged?(updatedAttachments)
    // Duplicates and photos over the limit are dropped, so deselect them too.
    deselectUnstagedPhotos(in: updatedAttachments)
  }

  private func deselectUnstagedPhotos(in stagedAttachments: [FriendsComposerAttachmentDraft]) {
    let unstagedPickerItemIDs = attachmentController.releaseUnstagedPhotos(
      stagedAttachmentIDs: Set(stagedAttachments.imageAttachments.map(\.id))
    )
    guard !unstagedPickerItemIDs.isEmpty else { return }
    selectedPhotoItems.removeAll { item in
      item.itemIdentifier.map { unstagedPickerItemIDs.contains($0) } ?? false
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
        .foregroundColor(isDisabled ? .tidexTextMuted : (isOpen ? .tidexBlueText : .tidexTextPrimary))
        .rotationEffect(.degrees(isOpen ? 45 : 0))
        .frame(width: Spacing.buttonHeight, height: Spacing.buttonHeight)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .tidexGlass(shape: .circle, tint: isOpen ? .tidexBlue.opacity(0.35) : nil, interactive: !isDisabled)
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
    static let previewHeight: CGFloat = 168
    static let panelCornerRadius: CGFloat = 28
  }

  @Binding var selectedPhotoItems: [PhotosPickerItem]
  let photoPickerSelectionLimit: Int
  let canUsePhotoPicker: Bool
  let isProcessingAttachment: Bool
  let showsShiftCalendarAction: Bool
  let stagedAttachments: [FriendsComposerAttachmentDraft]
  let canAddMoreImages: Bool
  let onOpenPhotoLibrary: () -> Void
  let onOpenCamera: () -> Void
  let onOpenShiftCalendar: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var actionIconSize: CGFloat = 20

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
      photoCarousel

      actionButtons
    }
    .padding(Spacing.sm)
    // Glass sits behind the panel instead of wrapping it, so the embedded photo
    // picker is not rendered inside the glass effect.
    .background {
      Color.clear.tidexGlass(shape: .rect(cornerRadius: Layout.panelCornerRadius))
    }
  }

  private var actionButtons: some View {
    // At accessibility sizes the tiles become full-width rows so the labels
    // keep their width and the drawer stays short enough to fit on screen.
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Spacing.xs))
      : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.xs))

    return layout {
      actionButton(
        systemName: "photo.on.rectangle.angled",
        title: String(localized: .friendsChatComposerPhotoLibrary),
        isActive: hasImageAttachments,
        isDisabled: !canUsePhotoPicker,
        action: onOpenPhotoLibrary
      )

      actionButton(
        systemName: "camera",
        title: String(localized: .friendsChatComposerCamera),
        isActive: false,
        isDisabled: !canAddMoreImages,
        action: onOpenCamera
      )

      if showsShiftCalendarAction {
        actionButton(
          systemName: "calendar",
          title: String(localized: .friendsChatComposerShiftCalendar),
          isActive: hasShiftSnapshotAttachment,
          isDisabled: !canStageShiftSnapshot,
          action: onOpenShiftCalendar
        )
      }
    }
  }

  private var photoCarousel: some View {
    // With the accessories hidden there is no Add button, so each tap has to
    // update the selection right away.
    // The shared library gives each item an identifier, which lets the selection stay
    // in sync with the draft. It does not ask for Photos access.
    PhotosPicker(
      selection: $selectedPhotoItems,
      maxSelectionCount: photoPickerSelectionLimit,
      selectionBehavior: .continuous,
      matching: .images,
      photoLibrary: .shared()
    ) {
      EmptyView()
    }
    .photosPickerStyle(.compact)
    .photosPickerAccessoryVisibility(.hidden, edges: .all)
    .disabled(isProcessingAttachment || !canUsePhotoPicker)
    .opacity(isProcessingAttachment || !canUsePhotoPicker ? 0.55 : 1)
    .frame(maxWidth: .infinity)
    .frame(height: Layout.previewHeight)
    .clipShape(
      RoundedRectangle(cornerRadius: Layout.panelCornerRadius - Spacing.sm, style: .continuous)
    )
    .overlay {
      FriendsChatGestureTargetSurface(targetKind: .attachmentPhotoCarousel)
        .allowsHitTesting(false)
    }
  }

  private func actionButton(
    systemName: String,
    title: String,
    isActive: Bool,
    isDisabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    let isUnavailable = isProcessingAttachment || isDisabled
    let tileShape = RoundedRectangle(
      cornerRadius: Layout.panelCornerRadius - Spacing.sm, style: .continuous)

    let isRow = dynamicTypeSize.isAccessibilitySize
    let contentLayout =
      isRow
      ? AnyLayout(HStackLayout(spacing: Spacing.xs))
      : AnyLayout(VStackLayout(spacing: Spacing.xxs))

    return Button(action: action) {
      contentLayout {
        Image(systemName: systemName)
          .font(.system(size: actionIconSize, weight: .semibold))
          .accessibilityHidden(true)

        Text(title)
          .font(.tidexFootnote)
          .multilineTextAlignment(isRow ? .leading : .center)
          .lineLimit(isRow ? 1 : 2)
          .minimumScaleFactor(isRow ? 0.8 : 1)
      }
      .foregroundColor(
        isUnavailable ? .tidexTextMuted : (isActive ? .tidexBlueText : .tidexTextPrimary)
      )
      .frame(
        maxWidth: .infinity, minHeight: isRow ? 44 : 64, alignment: isRow ? .leading : .center
      )
      .padding(.horizontal, isRow ? Spacing.sm : Spacing.xxs)
      .padding(.vertical, Spacing.xs)
      .background(
        tileShape.fill(
          isActive && !isUnavailable
            ? Color.tidexBlue.opacity(0.16)
            : Color.tidexTextPrimary.opacity(isUnavailable ? 0.03 : 0.07)
        )
      )
      .contentShape(tileShape)
    }
    .buttonStyle(.plain)
    .disabled(isUnavailable)
    .accessibilityAddTraits(isActive ? .isSelected : [])
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
    .frame(width: sideLength, height: sideLength)
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
    .tidexGlass(shape: .rect(cornerRadius: CornerRadius.card))
    .overlay(alignment: .topTrailing) {
      FriendsThreadComposerCloseButton(
        diameter: 28,
        accessibilityLabel: Text(.friendsAccessibilityCancelReply),
        action: onCancel
      )
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
      .tidexGlass(shape: .rect(cornerRadius: CornerRadius.card))
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
    FriendsThreadComposerCloseButton(
      diameter: 32,
      accessibilityLabel: Text(accessibilityLabel),
      action: onDismiss
    )
  }
}

private struct FriendsThreadComposerEditBanner: View {
  let onCancel: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: Spacing.xs) {
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

      FriendsThreadComposerCloseButton(
        diameter: 32,
        accessibilityLabel: Text(.friendsChatComposerCancelEdit),
        action: onCancel
      )
    }
    .padding(.leading, Spacing.md)
    .padding(.trailing, Spacing.xs)
    .padding(.vertical, Spacing.xs)
    .tidexGlass(shape: .rect(cornerRadius: CornerRadius.card))
  }
}

private struct FriendsThreadComposerCloseButton: View {
  let diameter: CGFloat
  let accessibilityLabel: Text
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.tidexCaptionStrong)
        .foregroundColor(.tidexTextSecondary)
        .frame(width: diameter, height: diameter)
        .background(Circle().fill(Color.tidexTextPrimary.opacity(0.08)))
        // The visible circle stays small. The tap area is at least 44pt.
        .contentShape(Rectangle().inset(by: -8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct FriendsThreadComposerHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
