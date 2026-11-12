import ExyteChat
import ImageIO
import SwiftUI
import UIKit

struct FriendsChatMessageRowContent: View {
  private static let minimumBubbleWidthForTimestamp: CGFloat = 92
  private static let maximumTextBubbleWidth: CGFloat = 360
  private static let reactionHorizontalOffset: CGFloat = 12
  private static let reactionVerticalOffset: CGFloat = 12
  private static let avatarSize: CGFloat = AvatarView.Size.small
  private static let replySwipeResetAnimationDuration: TimeInterval = 0.18

  let message: FriendMessage
  let quotedPreview: FriendsChatReplyPreviewModel?
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  let counterpartAvatarUrl: String?
  let counterpartAvatarInitials: String
  let isHighlighted: Bool
  let highlightedAttachmentId: String?
  let visibleMessageText: String
  let senderFirstName: String?
  let separatorDate: Date?
  let showsSenderLabel: Bool
  let showsTimestamp: Bool
  let messageStatus: FriendsChatMessageStatus?
  let stackingOrder: Double
  let onRetry: () -> Void
  let onShowReactionMenu: (String?) -> Void
  let onTapQuotedMessage: () -> Void
  let onOpenImageAttachment: (FriendMessageAttachment) -> Void
  let onImageReactionPressChanged: (FriendMessageAttachment, Bool) -> Void
  let onPrepareImageReaction: (FriendMessageAttachment) -> Void
  let onOpenShiftSnapshot: (FriendShiftSnapshot) -> Void
  let onReplySwipe: (() -> Void)?
  @Binding var timestampRevealOffset: CGFloat
  let messageFrame: Binding<CGRect>?
  /// Name VoiceOver reads for the sender ("You" for the user's own messages). Omitted when nil.
  var accessibilitySenderName: String?
  /// Reply, copy, edit, forward, delete, report and quick reactions, as VoiceOver actions.
  var accessibilityActions: [FriendsChatAccessibilityAction] = []

  @Environment(\.openURL) private var openURL
  @State private var replySwipeOffset: CGFloat = 0
  @State private var activeReplySwipePayloadId: String?
  @State private var hasTriggeredReplySwipeHaptic: Bool = false
  @State private var rowFrame: CGRect = .zero
  @State private var payloadFrame: CGRect = .zero

  private struct PayloadLayout {
    let isShowingAttachmentReactionTarget: Bool
    let hasMessageText: Bool
    let imageAttachments: [FriendMessageAttachment]
    let shiftSnapshot: FriendShiftSnapshot?
    let fallbackPreviewText: String?
    let showsFallbackBubble: Bool
    let showsReplyPreview: Bool
    let payloadCount: Int
    let usesStandalonePayloadGrouping: Bool
    let imagePayloadStartIndex: Int
    let bubblePayloadIndex: Int
    let showsMetadataRow: Bool
  }

  private var payloadLayout: PayloadLayout {
    let menuAttachmentId: String? =
      messageFrame != nil
      ? FriendsThreadAttachmentReactionMenuTarget.attachmentId(for: message.id)
      : nil
    let targetAttachmentId: String? = menuAttachmentId ?? highlightedAttachmentId
    let isShowingAttachmentReactionTarget: Bool = messageFrame != nil && targetAttachmentId != nil
    let hasMessageText: Bool =
      !isShowingAttachmentReactionTarget
      && !visibleMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let allImageAttachments: [FriendMessageAttachment] = message.attachments.filter { attachment in
      attachment.kind == .image
    }
    let imageAttachments: [FriendMessageAttachment] =
      if isShowingAttachmentReactionTarget, let targetAttachmentId {
        allImageAttachments.filter { $0.id == targetAttachmentId }
      } else {
        allImageAttachments
      }
    let shiftSnapshot: FriendShiftSnapshot? = message.shiftSnapshot
    let fallbackPreviewText: String? = message.previewText
    let showsFallbackBubble: Bool =
      !hasMessageText && imageAttachments.isEmpty && shiftSnapshot == nil
      && fallbackPreviewText != nil
    let showsReplyPreview: Bool = !isShowingAttachmentReactionTarget && quotedPreview != nil
    let showsBubblePayload: Bool = showsFallbackBubble || hasMessageText
    let payloadCount: Int =
      (showsReplyPreview ? 1 : 0) + imageAttachments.count + (showsBubblePayload ? 1 : 0)
    let imagePayloadStartIndex: Int = showsReplyPreview ? 1 : 0
    return PayloadLayout(
      isShowingAttachmentReactionTarget: isShowingAttachmentReactionTarget,
      hasMessageText: hasMessageText,
      imageAttachments: imageAttachments,
      shiftSnapshot: shiftSnapshot,
      fallbackPreviewText: fallbackPreviewText,
      showsFallbackBubble: showsFallbackBubble,
      showsReplyPreview: showsReplyPreview,
      payloadCount: payloadCount,
      usesStandalonePayloadGrouping: showsReplyPreview || !imageAttachments.isEmpty,
      imagePayloadStartIndex: imagePayloadStartIndex,
      bubblePayloadIndex: imagePayloadStartIndex + imageAttachments.count,
      showsMetadataRow: !isShowingAttachmentReactionTarget
        && (inlineMetadataStatus != nil || message.editedAt != nil)
    )
  }

  private func payloadGroupContext(
    at index: Int,
    layout: PayloadLayout
  ) -> FriendsChatMessageGroupContext {
    payloadGroupContext(
      index: index,
      count: layout.payloadCount,
      usesStandalonePayloadGrouping: layout.usesStandalonePayloadGrouping
    )
  }

  var body: some View {
    let layout = payloadLayout
    let topPadding: CGFloat = groupContext.joinsPrevious ? Spacing.micro : Spacing.xxs
    let bottomPadding: CGFloat =
      if layout.showsMetadataRow {
        Spacing.xxxs
      } else if groupContext.joinsNext {
        Spacing.micro
      } else {
        Spacing.xxs
      }

    return VStack(spacing: Spacing.xs) {
      if let separatorDate {
        FriendsChatDateSeparator(date: separatorDate)
      }

      timestampRevealContainer {
        gestureRow {
          HStack(alignment: .top, spacing: Spacing.xs) {
            if !isCurrentUser {
              avatarSlot
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 3) {
              senderLabel

              payloadStack(layout)

              if layout.showsMetadataRow {
                metadataRow
              }
            }
          }
        }
      }
      .zIndex(bubbleEdgeBadgeStackingOrder)
      .padding(.top, topPadding)
      .padding(.bottom, bottomPadding)
      .background(
        Rectangle()
          .fill(shouldHighlightWholeMessage ? Color.tidexBlue.opacity(0.12) : Color.clear)
      )
    }
    .motionProbe("reply-swipe", renderedReplySwipeOffset)
  }

  @ViewBuilder
  private var senderLabel: some View {
    if showsSenderLabel, let senderFirstName, !senderFirstName.isEmpty {
      Text(senderFirstName)
        .font(.tidexCaptionRegular)
        .foregroundStyle(Color.tidexTextMuted)
        .padding(.horizontal, CornerRadius.bubble)
    }
  }

  private func payloadStack(_ layout: PayloadLayout) -> some View {
    VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Spacing.xxs) {
      if layout.showsReplyPreview, let quotedPreview {
        FriendsChatMessageReplyPreview(
          preview: quotedPreview,
          isCurrentUser: isCurrentUser,
          groupContext: payloadGroupContext(at: 0, layout: layout),
          isHighlighted: false,
          maxWidth: resolvedMaximumTextBubbleWidth,
          onTap: onTapQuotedMessage
        )
      }

      ForEach(Array(layout.imageAttachments.enumerated()), id: \.element.id) {
        index, attachment in
        imagePayload(attachment, index: index, layout: layout)
      }

      if let shiftSnapshot = layout.shiftSnapshot {
        shiftSnapshotPayload(shiftSnapshot, layout: layout)
      }

      if layout.showsFallbackBubble, let fallbackPreviewText = layout.fallbackPreviewText {
        fallbackBubblePayload(fallbackPreviewText, layout: layout)
      }

      if layout.hasMessageText {
        textBubblePayload(layout)
      }
    }
  }

  @ViewBuilder
  private func imagePayload(
    _ attachment: FriendMessageAttachment,
    index: Int,
    layout: PayloadLayout
  ) -> some View {
    if attachment.kind == .image {
      replySwipeContainer(id: "image-\(attachment.id)") {
        FriendsChatImageView(
          messageId: message.id,
          attachment: attachment,
          isCurrentUser: isCurrentUser,
          groupContext: payloadGroupContext(
            at: layout.imagePayloadStartIndex + index, layout: layout),
          canOpenAttachment: canOpenAttachment,
          canReact: message.canReact,
          isHighlighted: false,
          onOpenImageAttachment: onOpenImageAttachment,
          onShowReactionMenu: onShowReactionMenu,
          onReactionPressChanged: onImageReactionPressChanged,
          onPrepareReaction: onPrepareImageReaction
        )
      }
      .chatMessageAccessibility(
        label: imageAccessibilityLabel(index: index, layout: layout),
        isImage: true,
        actions: messageAccessibilityActions,
        onActivate: canOpenAttachment ? { onOpenImageAttachment(attachment) } : nil
      )
      .friendsChatMessageFrame(
        !layout.hasMessageText && layout.shiftSnapshot == nil
          && index == layout.imageAttachments.count - 1
          ? messageFrame : nil
      )
      .overlay(alignment: reactionAlignment) {
        imageReactionOverlay(attachment, index: index, layout: layout)
      }
    }
  }

  @ViewBuilder
  private func imageReactionOverlay(
    _ attachment: FriendMessageAttachment,
    index: Int,
    layout: PayloadLayout
  ) -> some View {
    if !layout.hasMessageText, !layout.showsFallbackBubble, layout.shiftSnapshot == nil {
      let reactionTarget:
        (
          reactions: [FriendMessageReaction],
          attachmentId: String?
        ) = imageReactionTarget(
          for: attachment,
          index: index,
          imageCount: layout.imageAttachments.count,
          allowsMessageFallback: !layout.isShowingAttachmentReactionTarget
        )
      reactionStrip(
        for: reactionTarget.reactions,
        attachmentId: reactionTarget.attachmentId
      )
    }
  }

  private func shiftSnapshotPayload(
    _ shiftSnapshot: FriendShiftSnapshot,
    layout: PayloadLayout
  ) -> some View {
    replySwipeContainer(id: "shift-\(message.id)") {
      ChatShiftSnapshotCard(
        snapshot: shiftSnapshot,
        isCurrentUser: isCurrentUser,
        showsOwnerHeader: shiftSnapshot.ownerUserId != message.senderUserId,
        topInset: layout.imageAttachments.isEmpty ? 0 : Spacing.xs,
        onTap: messageFrame == nil
          ? {
            onOpenShiftSnapshot(shiftSnapshot)
          } : nil
      )
    }
    .chatMessageAccessibility(
      label: shiftAccessibilityLabel(shiftSnapshot, layout: layout),
      actions: messageAccessibilityActions,
      onActivate: messageFrame == nil ? { onOpenShiftSnapshot(shiftSnapshot) } : nil
    )
    .friendsChatMessageFrame(
      layout.hasMessageText || !layout.imageAttachments.isEmpty ? nil : messageFrame
    )
    .overlay(alignment: reactionAlignment) {
      if !layout.hasMessageText, layout.imageAttachments.isEmpty {
        reactionStrip(for: message.reactions)
      }
    }
    .highPriorityGesture(messageMenuDoubleTapGesture)
  }

  private func fallbackBubblePayload(_ fallbackPreviewText: String, layout: PayloadLayout)
    -> some View
  {
    FriendsChatReactionAnchoredBubbleCard(
      isCurrentUser: isCurrentUser,
      groupContext: payloadGroupContext(at: layout.bubblePayloadIndex, layout: layout),
      minWidth: Self.minimumBubbleWidthForTimestamp,
      maxWidth: resolvedMaximumTextBubbleWidth,
      messageFrame: messageFrame,
      replySwipe: textBubbleReplySwipeConfiguration(id: "fallback-\(message.id)")
    ) {
      Text(fallbackPreviewText)
        .font(.tidexBody)
        .foregroundStyle(isCurrentUser ? Color.tidexTextOnBrand : Color.tidexTextPrimary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    } reaction: {
      reactionStrip(for: message.reactions)
    }
    .chatMessageAccessibility(
      label: textAccessibilityLabel(fallbackPreviewText),
      actions: messageAccessibilityActions
    )
    .highPriorityGesture(messageMenuDoubleTapGesture)
  }

  private func textBubblePayload(_ layout: PayloadLayout) -> some View {
    FriendsChatReactionAnchoredBubbleCard(
      isCurrentUser: isCurrentUser,
      groupContext: payloadGroupContext(at: layout.bubblePayloadIndex, layout: layout),
      minWidth: Self.minimumBubbleWidthForTimestamp,
      maxWidth: resolvedMaximumTextBubbleWidth,
      messageFrame: messageFrame,
      replySwipe: textBubbleReplySwipeConfiguration(id: "text-\(message.id)")
    ) {
      FriendsChatLinkedMessageText(
        text: visibleMessageText,
        isCurrentUser: isCurrentUser
      )
    } reaction: {
      reactionStrip(for: message.reactions)
    }
    .chatMessageAccessibility(
      label: textAccessibilityLabel(visibleMessageText),
      actions: messageAccessibilityActions
    )
    .highPriorityGesture(messageMenuDoubleTapGesture)
  }

  // MARK: - VoiceOver

  private var canOpenAttachment: Bool {
    messageFrame == nil
  }

  private var messageReactions: [FriendMessageReaction] {
    message.reactions + message.attachments.flatMap(\.reactions)
  }

  /// Time, delivery state, edit mark and reactions. Only the last payload of a message says them.
  private var accessibilityDetails: String {
    FriendsChatMessageAccessibility.detailsLabel(
      time: message.createdAt.toHourMinuteString(),
      status: inlineMetadataStatus,
      isEdited: message.editedAt != nil,
      reactions: messageReactions
    )
  }

  private func textAccessibilityLabel(_ text: String) -> String {
    FriendsChatMessageAccessibility.join([accessibilitySenderName, text, accessibilityDetails])
  }

  private func imageAccessibilityLabel(index: Int, layout: PayloadLayout) -> String {
    let photo = FriendsChatMessageAccessibility.photoLabel(
      senderName: accessibilitySenderName,
      isCurrentUser: isCurrentUser && accessibilitySenderName != nil,
      index: index,
      count: layout.imageAttachments.count
    )
    let isLastPayload =
      index == layout.imageAttachments.count - 1 && !layout.hasMessageText
      && !layout.showsFallbackBubble && layout.shiftSnapshot == nil
    return FriendsChatMessageAccessibility.join([photo, isLastPayload ? accessibilityDetails : nil])
  }

  private func shiftAccessibilityLabel(_ snapshot: FriendShiftSnapshot, layout: PayloadLayout)
    -> String
  {
    let isLastPayload = !layout.hasMessageText && !layout.showsFallbackBubble
    return FriendsChatMessageAccessibility.join([
      accessibilitySenderName,
      FriendsChatMessageAccessibility.shiftSummary(snapshot),
      isLastPayload ? accessibilityDetails : nil,
    ])
  }

  /// Every payload of a message carries the same actions, so they work wherever VoiceOver focus is.
  private var messageAccessibilityActions: [FriendsChatAccessibilityAction] {
    guard messageFrame == nil else { return [] }
    var actions = accessibilityActions
    // The links sit inside the combined element, so VoiceOver's Links rotor can't reach them.
    if !visibleMessageText.isEmpty {
      for link in FriendsChatMessageLinkifier.links(in: visibleMessageText) {
        actions.append(
          FriendsChatAccessibilityAction(
            name: String(localized: .friendsAccessibilityOpenLink(link.text))
          ) {
            if AppDeepLinkResolver.resolve(link.url) != nil {
              AppCoordinator.shared.handleDeepLink(link.url)
            } else {
              openURL(link.url)
            }
          })
      }
    }
    if message.canReact {
      actions.append(
        FriendsChatAccessibilityAction(name: String(localized: .friendsAccessibilityReact)) {
          onShowReactionMenu(nil)
        })
    }
    return actions
  }

  private var metadataRow: some View {
    HStack(spacing: Spacing.xxs) {
      if isCurrentUser {
        if let inlineMetadataStatus {
          statusView(inlineMetadataStatus)
        }

        if message.editedAt != nil {
          editedLabel
        }

      } else {
        if message.editedAt != nil {
          editedLabel
        }

        if let inlineMetadataStatus {
          statusView(inlineMetadataStatus)
        }
      }
    }
    .font(.tidexMicro)
    .foregroundStyle(Color.tidexTextMuted)
    .fixedSize(horizontal: true, vertical: false)
  }

  private var editedLabel: some View {
    Text(.friendsChatEdited)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      // The message label already says it was edited.
      .accessibilityHidden(true)
  }

  private var shouldHighlightWholeMessage: Bool {
    isHighlighted && highlightedAttachmentId == nil
      && !message.attachments.contains { attachment in
        attachment.kind == .image
      }
  }

  private var resolvedMaximumTextBubbleWidth: CGFloat {
    FriendsChatTimestampRevealResolver.contentMaxWidth(
      baseWidth: Self.maximumTextBubbleWidth,
      isCurrentUser: isCurrentUser
    )
  }

  private func payloadGroupContext(
    index: Int,
    count: Int,
    usesStandalonePayloadGrouping: Bool
  ) -> FriendsChatMessageGroupContext {
    guard usesStandalonePayloadGrouping else {
      return groupContext
    }

    let joinsPrevious: Bool = groupContext.joinsPrevious || index > 0
    let joinsNext: Bool = index < count - 1 || groupContext.joinsNext

    let position: FriendsChatMessageGroupPosition =
      switch (joinsPrevious, joinsNext) {
      case (false, false):
        .standalone

      case (false, true):
        .leading

      case (true, true):
        .middle

      case (true, false):
        .trailing
      }

    return FriendsChatMessageGroupContext(position: position, isCurrentUser: isCurrentUser)
  }

  private func timestampRevealContainer<Content: View>(
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    ZStack(alignment: .trailing) {
      timestampRevealColumn
      content()
        .offset(x: timestampRevealContentOffset)
    }
    .friendsChatMessageFrame($rowFrame)
    .overlay(alignment: timestampRevealSurfaceAlignment) {
      timestampRevealSurface
    }
    .onPreferenceChange(FriendsChatReplyPayloadFramePreferenceKey.self) { frames in
      payloadFrame = Self.unionFrame(frames.values)
    }
  }

  private func gestureRow<Content: View>(
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    HStack {
      VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Spacing.xxs) {
        content()
      }
    }
    .padding(.horizontal, Spacing.sm)
    .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
  }

  private var timestampRevealColumn: some View {
    HStack {
      Spacer(minLength: 0)

      Text(message.createdAt.toHourMinuteString())
        .font(.tidexMicro)
        .foregroundStyle(Color.tidexTextMuted)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: FriendsChatTimestampRevealResolver.revealWidth, alignment: .trailing)
        .padding(.trailing, Spacing.sm)
        .opacity(timestampRevealOpacity)
    }
    .allowsHitTesting(false)
    // The time only shows while swiping, so VoiceOver gets it from the message label instead.
    .accessibilityHidden(true)
  }

  private var timestampRevealOpacity: Double {
    let progress: CGFloat = timestampRevealOffset / FriendsChatTimestampRevealResolver.revealWidth
    return min(max(Double(progress), 0), 1)
  }

  private var timestampRevealContentOffset: CGFloat {
    isCurrentUser ? -timestampRevealOffset : 0
  }

  private var timestampRevealSurfaceAlignment: Alignment {
    isCurrentUser ? .leading : .trailing
  }

  private var timestampRevealSurface: some View {
    FriendsChatHorizontalPanSurface(
      targetKind: .timestampRevealGutter,
      minimumDistance: FriendsChatTimestampRevealResolver.minimumDistance,
      direction: .left,
      onChanged: handleTimestampRevealChanged,
      onEnded: handleTimestampRevealEnded
    )
    .frame(width: timestampRevealSurfaceWidth, height: timestampRevealSurfaceHeight)
  }

  private var timestampRevealSurfaceWidth: CGFloat {
    guard rowFrame.width > 0 else {
      return isCurrentUser ? Spacing.xxxl : 0
    }

    guard isCurrentUser else {
      return rowFrame.width
    }

    guard payloadFrame.width > 0 else {
      return Spacing.xxxl
    }

    let emptyWidth: CGFloat = payloadFrame.minX - rowFrame.minX
    return max(min(emptyWidth, rowFrame.width), 0)
  }

  private var timestampRevealSurfaceHeight: CGFloat {
    max(rowFrame.height, 1)
  }

  private var messageMenuDoubleTapGesture: some Gesture {
    TapGesture(count: 2)
      .onEnded {
        onShowReactionMenu(nil)
      }
  }

  private static func unionFrame(_ frames: Dictionary<String, CGRect>.Values) -> CGRect {
    let union: CGRect =
      frames
      .filter { !$0.isNull && !$0.isEmpty }
      .reduce(CGRect.null) { partialResult, frame in
        partialResult.union(frame)
      }
    return union.isNull ? .zero : union
  }

  private func handleTimestampRevealChanged(_ value: FriendsChatReplyDragValue) {
    guard
      let newOffset = FriendsChatTimestampRevealResolver.clampedRevealOffset(
        horizontal: value.translation.width,
        vertical: value.translation.height
      )
    else {
      return
    }

    timestampRevealOffset = newOffset
  }

  private func handleTimestampRevealEnded(_ value: FriendsChatReplyDragValue) {
    handleTimestampRevealChanged(value)

    guard timestampRevealOffset != 0 else {
      return
    }
    withAnimation(.easeOut(duration: Self.replySwipeResetAnimationDuration)) {
      timestampRevealOffset = 0
    }
  }

  @ViewBuilder
  private func replySwipeContainer<Content: View>(
    id: String,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    if onReplySwipe != nil {
      FriendsChatReplySwipeContainer(
        id: id,
        isCurrentUser: isCurrentUser,
        offset: renderedReplySwipeOffset,
        actionAlignment: replySwipeActionAlignment,
        onChanged: { handleReplySwipeChanged(id: id, value: $0) },
        onEnded: { handleReplySwipeEnded(id: id, value: $0) }
      ) {
        content()
      } actionLabel: {
        replySwipeActionLabel
          .opacity(replySwipeActionOpacity(for: id))
      }
      .sensoryFeedback(.impact(weight: .medium), trigger: hasTriggeredReplySwipeHaptic) {
        _, newValue in
        newValue
      }
    } else {
      content()
    }
  }

  private var replySwipeActionLabel: some View {
    ZStack {
      Capsule()
        .fill(Color.tidexBlue)

      Image(systemName: "arrowshape.turn.up.left.fill")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color.tidexTextOnBrand)
        .accessibilityHidden(true)
    }
    .frame(width: 44, height: 32)
    .scaleEffect(replySwipeActionScale)
  }

  private var replySwipeDirection: FriendsChatReplySwipeDirection {
    isCurrentUser ? .left : .right
  }

  private var replySwipeActionAlignment: Alignment {
    isCurrentUser ? .trailing : .leading
  }

  private var replySwipeActionXOffset: CGFloat {
    isCurrentUser ? 48 : -48
  }

  private func replySwipeActionOpacity(for id: String) -> Double {
    guard activeReplySwipePayloadId == id else {
      return 0
    }
    return min(
      Double(abs(replySwipeOffset)) / Double(FriendsChatReplySwipeResolver.actionWidth * 0.6),
      1
    )
  }

  private var replySwipeActionScale: CGFloat {
    let progress: CGFloat = min(
      abs(replySwipeOffset) / FriendsChatReplySwipeResolver.actionWidth, 1)
    return 0.7 + (progress * 0.3)
  }

  private var renderedReplySwipeOffset: CGFloat {
    replySwipeOffset
  }

  private func textBubbleReplySwipeConfiguration(id: String) -> FriendsChatReplySwipeConfiguration?
  {
    guard onReplySwipe != nil else {
      return nil
    }
    return FriendsChatReplySwipeConfiguration(
      id: id,
      isCurrentUser: isCurrentUser,
      offset: renderedReplySwipeOffset,
      actionAlignment: replySwipeActionAlignment,
      actionLabel: AnyView(
        replySwipeActionLabel
          .offset(x: replySwipeActionXOffset)
          .opacity(replySwipeActionOpacity(for: id))
      ),
      onChanged: { handleReplySwipeChanged(id: id, value: $0) },
      onEnded: { handleReplySwipeEnded(id: id, value: $0) }
    )
  }

  private func handleReplySwipeChanged(id: String, value: FriendsChatReplyDragValue) {
    guard
      let newOffset = clampedReplySwipeOffset(
        horizontal: value.translation.width,
        vertical: value.translation.height
      )
    else {
      return
    }

    if newOffset == 0 {
      if activeReplySwipePayloadId == id {
        activeReplySwipePayloadId = nil
      }
    } else {
      activeReplySwipePayloadId = id
    }
    replySwipeOffset = newOffset

    let crossedThreshold: Bool = FriendsChatReplySwipeResolver.crossedThreshold(
      offset: replySwipeOffset
    )
    if crossedThreshold, !hasTriggeredReplySwipeHaptic {
      hasTriggeredReplySwipeHaptic = true
    }
  }

  private func handleReplySwipeEnded(id: String, value: FriendsChatReplyDragValue) {
    let finalOffset: CGFloat = replySwipeOffset
    hasTriggeredReplySwipeHaptic = false

    guard finalOffset != 0 else {
      if activeReplySwipePayloadId == id {
        activeReplySwipePayloadId = nil
      }
      return
    }

    let outcome: FriendsChatReplySwipeOutcome = replySwipeOutcome(
      offset: finalOffset,
      velocity: value.velocity.width
    )

    withAnimation(
      .easeOut(duration: Self.replySwipeResetAnimationDuration), completionCriteria: .removed
    ) {
      replySwipeOffset = 0
    } completion: {
      guard activeReplySwipePayloadId == id else { return }
      activeReplySwipePayloadId = nil
      if outcome == .trigger, let onReplySwipe {
        Haptics.play(.medium)
        onReplySwipe()
      }
    }
  }

  private func clampedReplySwipeOffset(horizontal: CGFloat, vertical: CGFloat) -> CGFloat? {
    FriendsChatReplySwipeResolver.clampedOffset(
      horizontal: horizontal,
      vertical: vertical,
      allowedDirection: replySwipeDirection
    )
  }

  private func replySwipeOutcome(offset: CGFloat, velocity: CGFloat) -> FriendsChatReplySwipeOutcome
  {
    FriendsChatReplySwipeResolver.outcome(
      offset: offset,
      velocity: velocity,
      allowedDirection: replySwipeDirection
    )
  }

  @ViewBuilder
  private func statusView(_ messageStatus: FriendsChatMessageStatus) -> some View {
    switch messageStatus {
    case .sending:
      HStack(spacing: 3) {
        ProgressView()
          .controlSize(.mini)

        Text(.friendsChatStatusSending)
          .lineLimit(1)
          .minimumScaleFactor(0.9)
          .fixedSize(horizontal: true, vertical: false)
      }
      // The message label already says the delivery state.
      .accessibilityHidden(true)

    case .delivered:
      HStack(spacing: 3) {
        Image(systemName: "checkmark")
          .font(.tidexMicro.weight(.semibold))
          .accessibilityHidden(true)

        Text(.friendsChatStatusDelivered)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .accessibilityHidden(true)

    case .read:
      HStack(spacing: 3) {
        Image(systemName: "checkmark.circle.fill")
          .font(.tidexMicro.weight(.semibold))
          .foregroundStyle(Color.tidexBlueText)
          .accessibilityHidden(true)

        Text(.friendsChatStatusRead)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .accessibilityHidden(true)

    case .failed:
      HStack(spacing: 4) {
        Image(systemName: "exclamationmark.circle.fill")
          .font(.tidexMicro.weight(.semibold))
          .foregroundStyle(Color.tidexError)
          .accessibilityHidden(true)

        Text(.friendsChatStatusFailed)
          .foregroundStyle(Color.tidexError)
          .lineLimit(1)
          .minimumScaleFactor(0.9)
          .fixedSize(horizontal: true, vertical: false)
          // The message label says "Failed". The Retry button stays reachable for Voice Control.
          .accessibilityHidden(true)

        Button {
          onRetry()
        } label: {
          Text(.commonRetry)
            .foregroundStyle(Color.tidexBlueText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var inlineMetadataStatus: FriendsChatMessageStatus? {
    guard let messageStatus else {
      return nil
    }
    switch messageStatus {
    case .sending, .delivered, .read:
      return messageStatus

    case .failed:
      return .failed
    }
  }

  private var bubbleEdgeBadgeStackingOrder: Double {
    inlineMetadataStatus != nil ? stackingOrder : 0
  }

  @ViewBuilder
  private func reactionStrip(
    for reactions: [FriendMessageReaction],
    attachmentId: String? = nil
  ) -> some View {
    Group {
      if !reactions.isEmpty {
        reactionButtons(for: reactions, attachmentId: attachmentId)
          .alignmentGuide(.leading) { dimensions in
            isCurrentUser ? dimensions[.trailing] : dimensions[.leading]
          }
          .offset(
            x: isCurrentUser ? Self.reactionHorizontalOffset : Self.reactionHorizontalOffset,
            y: -Self.reactionVerticalOffset
          )
          .zIndex(2)
          // Reactions are in the message label, and the React action opens the picker.
          .accessibilityHidden(messageFrame == nil)
      }
    }
  }

  private func reactionButtons(
    for reactions: [FriendMessageReaction],
    attachmentId: String?
  ) -> some View {
    HStack(spacing: Spacing.xxxs) {
      ForEach(reactions) { reaction in
        Button {
          onShowReactionMenu(attachmentId)
        } label: {
          HStack(spacing: 4) {
            FriendsChatEmojiGlyph(emoji: reaction.emoji, size: 22)

            if reaction.count > 1 {
              Text("\(reaction.count)")
                .font(.tidexCaptionRegular)
                .foregroundStyle(Color.tidexTextSecondary)
            }
          }
          .padding(.horizontal, 2)
          .padding(.vertical, 1)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!message.canReact)
      }
    }
  }

  private func imageReactionTarget(
    for attachment: FriendMessageAttachment,
    index: Int,
    imageCount: Int,
    allowsMessageFallback: Bool
  ) -> (reactions: [FriendMessageReaction], attachmentId: String?) {
    if !attachment.reactions.isEmpty {
      return (attachment.reactions, attachment.id)
    }

    if allowsMessageFallback, index == imageCount - 1 {
      return (message.reactions, nil)
    }

    return ([], attachment.id)
  }

  private var reactionAlignment: Alignment {
    isCurrentUser ? .topLeading : .topTrailing
  }

  @ViewBuilder
  private var avatarSlot: some View {
    if groupContext.showsAvatar {
      AvatarView(
        url: counterpartAvatarUrl,
        initials: counterpartAvatarInitials,
        size: Self.avatarSize
      )
      .padding(.top, 2)
      .accessibilityHidden(true)
    } else {
      Color.clear
        .frame(width: Self.avatarSize, height: Self.avatarSize)
    }
  }
}

enum FriendsChatMessageStatus: Equatable {
  case sending
  case delivered
  case read
  case failed
}
