import ExyteChat
import ImageIO
import SwiftUI
import UIKit

struct FriendsChatReplyPreviewModel: Equatable {
  let senderName: String
  let previewKind: FriendLastMessagePreviewKind
  let iconPreviewKind: FriendLastMessagePreviewKind?
  let snippet: String
  let imageAttachments: [FriendMessageAttachment]

  init(senderName: String, message: FriendMessage) {
    self.senderName = senderName
    previewKind = message.previewKind
    iconPreviewKind = message.replyIconPreviewKind
    snippet = message.previewText ?? String(localized: .friendsChatPreviewUnsupported)
    imageAttachments = message.attachments
      .filter { $0.kind == .image }
      .sorted { $0.attachmentIndex < $1.attachmentIndex }
  }
}

enum FriendsChatMessageStatus: Equatable {
  case sending
  case delivered
  case read
  case failed
}

@MainActor
enum FriendsThreadAttachmentReactionMenuTarget {
  private struct Target {
    let messageId: String
    let attachmentId: String
    let createdAt: Date
  }

  private static var target: Target?
  private static let expirationInterval: TimeInterval = 10

  static func set(messageId: String, attachmentId: String) {
    target = Target(messageId: messageId, attachmentId: attachmentId, createdAt: .now)
  }

  static func clear(messageId: String? = nil, attachmentId: String? = nil) {
    guard let current = target else { return }
    if let messageId, current.messageId != messageId { return }
    if let attachmentId, current.attachmentId != attachmentId { return }
    target = nil
  }

  static func attachmentId(for messageId: String, now: Date = .now) -> String? {
    guard let current = target else { return nil }
    guard current.messageId == messageId else { return nil }
    guard now.timeIntervalSince(current.createdAt) <= expirationInterval else {
      target = nil
      return nil
    }
    return current.attachmentId
  }
}

@MainActor
private enum FriendsThreadAttachmentTapSuppressor {
  private static var targets: [String: Date] = [:]
  private static let expirationInterval: TimeInterval = 10

  static func suppressNextTap(messageId: String, attachmentId: String) {
    let key = key(messageId: messageId, attachmentId: attachmentId)
    targets[key] = .now
  }

  static func consumeSuppressedTap(
    messageId: String,
    attachmentId: String,
    now: Date = .now
  ) -> Bool {
    pruneExpired(now: now)

    let key = key(messageId: messageId, attachmentId: attachmentId)
    guard targets.removeValue(forKey: key) != nil else { return false }
    return true
  }

  private static func pruneExpired(now: Date) {
    targets = targets.filter { _, createdAt in
      now.timeIntervalSince(createdAt) <= expirationInterval
    }
  }

  private static func key(messageId: String, attachmentId: String) -> String {
    "\(messageId)#\(attachmentId)"
  }
}

struct FriendsChatDetectedLink: Equatable {
  let range: NSRange
  let text: String
  let url: URL
}

enum FriendsChatMessageLinkifier {
  private static let detector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue)
  private static let tidexSchemePattern = #"(?i)\btidex://[^\s<>()\[\]{}"']+"#
  private static let bareDomainPattern =
    #"(?i)(?<![@\w.-])(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}(?:/[^\s<>()\[\]{}"']*)?"#
  private static let trailingURLCharacters: Set<Character> = [
    ".", ",", "!", "?", ";", ":", ")", "]", "}",
  ]

  static func attributedString(
    for text: String,
    foregroundColor: Color,
    linkColor: Color
  ) -> AttributedString {
    var result = AttributedString(text)
    result.foregroundColor = foregroundColor

    for link in links(in: text) {
      guard
        let stringRange = Range(link.range, in: text),
        let lowerBound = AttributedString.Index(stringRange.lowerBound, within: result),
        let upperBound = AttributedString.Index(stringRange.upperBound, within: result)
      else {
        continue
      }

      let attributedRange = lowerBound..<upperBound
      result[attributedRange].link = link.url
      result[attributedRange].foregroundColor = linkColor
      result[attributedRange].underlineStyle = .single
    }

    return result
  }

  static func links(in text: String) -> [FriendsChatDetectedLink] {
    guard !text.isEmpty else { return [] }

    var links: [FriendsChatDetectedLink] = []
    links.append(contentsOf: detectedURLLinks(in: text))
    links.append(contentsOf: regexLinks(in: text, pattern: tidexSchemePattern))
    links.append(contentsOf: regexLinks(in: text, pattern: bareDomainPattern))

    return nonOverlappingLinks(links)
  }

  private static func detectedURLLinks(in text: String) -> [FriendsChatDetectedLink] {
    guard let detector else { return [] }

    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    return detector.matches(in: text, options: [], range: nsRange).compactMap { match in
      guard let matchRange = trimmedRange(match.range, in: text) else { return nil }
      let displayText = substring(in: matchRange, text: text)
      guard let url = normalizedURL(for: displayText, detectedURL: match.url) else { return nil }
      return FriendsChatDetectedLink(range: matchRange, text: displayText, url: url)
    }
  }

  private static func regexLinks(in text: String, pattern: String) -> [FriendsChatDetectedLink] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: nsRange).compactMap { match in
      guard let matchRange = trimmedRange(match.range, in: text) else { return nil }
      let displayText = substring(in: matchRange, text: text)
      guard let url = normalizedURL(for: displayText, detectedURL: nil) else { return nil }
      return FriendsChatDetectedLink(range: matchRange, text: displayText, url: url)
    }
  }

  private static func nonOverlappingLinks(_ links: [FriendsChatDetectedLink])
    -> [FriendsChatDetectedLink]
  {
    links
      .sorted {
        if $0.range.location == $1.range.location {
          return $0.range.length > $1.range.length
        }
        return $0.range.location < $1.range.location
      }
      .reduce(into: [FriendsChatDetectedLink]()) { result, link in
        guard !result.contains(where: { NSIntersectionRange($0.range, link.range).length > 0 })
        else {
          return
        }
        result.append(link)
      }
  }

  private static func normalizedURL(for text: String, detectedURL: URL?) -> URL? {
    if hasURLScheme(text) {
      return URL(string: text) ?? detectedURL
    }

    if let detectedURL, hasURLScheme(detectedURL.absoluteString) {
      return detectedURL.scheme?.lowercased() == "http"
        ? URL(string: "https://\(text)") ?? detectedURL
        : detectedURL
    }

    return URL(string: "https://\(text)")
  }

  private static func hasURLScheme(_ text: String) -> Bool {
    text.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
  }

  private static func trimmedRange(_ nsRange: NSRange, in text: String) -> NSRange? {
    guard var range = Range(nsRange, in: text) else { return nil }

    while range.lowerBound < range.upperBound,
      let last = text[range].last,
      trailingURLCharacters.contains(last)
    {
      range = range.lowerBound..<text.index(before: range.upperBound)
    }

    guard range.lowerBound < range.upperBound else { return nil }
    return NSRange(range, in: text)
  }

  private static func substring(in nsRange: NSRange, text: String) -> String {
    guard let range = Range(nsRange, in: text) else { return "" }
    return String(text[range])
  }
}

private struct FriendsChatLinkedMessageText: View {
  let text: String
  let isCurrentUser: Bool

  var body: some View {
    Text(
      FriendsChatMessageLinkifier.attributedString(
        for: text,
        foregroundColor: foregroundColor,
        linkColor: linkColor
      )
    )
    .font(.tidexBody)
    .multilineTextAlignment(.leading)
    .fixedSize(horizontal: false, vertical: true)
    .environment(
      \.openURL,
      OpenURLAction { url in
        if AppDeepLinkResolver.resolve(url) != nil {
          AppCoordinator.shared.handleDeepLink(url)
          return .handled
        }

        return .systemAction(url)
      })
  }

  private var foregroundColor: Color {
    isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary
  }

  private var linkColor: Color {
    isCurrentUser ? .tidexTextOnBrand : .tidexBlue
  }
}

struct FriendsChatMessageRowContent: View {
  private static let minimumBubbleWidthForTimestamp: CGFloat = 92
  private static let maximumTextBubbleWidth: CGFloat = 360
  private static let reactionHorizontalOffset: CGFloat = 12
  private static let reactionVerticalOffset: CGFloat = 12
  private static let avatarSize = AvatarView.Size.small
  private static let replySwipeResetAnimationDuration: TimeInterval = 0.18

  private enum ReplySwipeHaptics {
    static let impact = UIImpactFeedbackGenerator(style: .medium)
    static let selection = UISelectionFeedbackGenerator()
    private static var isPrepared = false

    static func prepareIfNeeded() {
      guard !isPrepared else { return }
      isPrepared = true
      impact.prepare()
      selection.prepare()
    }
  }

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

  @State private var replySwipeOffset: CGFloat = 0
  @State private var activeReplySwipePayloadId: String?
  @State private var hasTriggeredReplySwipeHaptic = false
  @State private var rowFrame: CGRect = .zero
  @State private var payloadFrame: CGRect = .zero

  var body: some View {
    let menuAttachmentId =
      messageFrame != nil
      ? FriendsThreadAttachmentReactionMenuTarget.attachmentId(for: message.id)
      : nil
    let targetAttachmentId = menuAttachmentId ?? highlightedAttachmentId
    let isShowingAttachmentReactionTarget = messageFrame != nil && targetAttachmentId != nil
    let hasMessageText =
      !isShowingAttachmentReactionTarget
      && !visibleMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let allImageAttachments = message.attachments.filter { $0.kind == .image }
    let imageAttachments =
      if isShowingAttachmentReactionTarget, let targetAttachmentId {
        allImageAttachments.filter { $0.id == targetAttachmentId }
      } else {
        allImageAttachments
      }
    let shiftSnapshot = message.shiftSnapshot
    let fallbackPreviewText = message.previewText
    let showsFallbackBubble =
      !hasMessageText && imageAttachments.isEmpty && shiftSnapshot == nil
      && fallbackPreviewText != nil
    let showsMetadataRow =
      !isShowingAttachmentReactionTarget && (inlineMetadataStatus != nil || message.editedAt != nil)
    let topPadding = groupContext.joinsPrevious ? Spacing.micro : Spacing.xxs
    let bottomPadding =
      if showsMetadataRow {
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
              if showsSenderLabel, let senderFirstName, !senderFirstName.isEmpty {
                Text(senderFirstName)
                  .font(.tidexCaptionRegular)
                  .foregroundColor(.tidexTextMuted)
                  .padding(.horizontal, CornerRadius.bubble)
              }

              VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Spacing.xxs) {
                if !isShowingAttachmentReactionTarget, let quotedPreview {
                  FriendsChatMessageReplyPreview(
                    preview: quotedPreview,
                    isCurrentUser: isCurrentUser,
                    isHighlighted: false,
                    maxWidth: resolvedMaximumTextBubbleWidth,
                    onTap: onTapQuotedMessage
                  )
                }

                ForEach(Array(imageAttachments.enumerated()), id: \.element.id) {
                  index, attachment in
                  if attachment.kind == .image {
                    replySwipeContainer(id: "image-\(attachment.id)") {
                      FriendsChatImageView(
                        messageId: message.id,
                        attachment: attachment,
                        isCurrentUser: isCurrentUser,
                        canOpenAttachment: messageFrame == nil,
                        canReact: message.canReact,
                        isHighlighted: false,
                        onOpenImageAttachment: onOpenImageAttachment,
                        onReactionPressChanged: onImageReactionPressChanged,
                        onPrepareReaction: onPrepareImageReaction
                      )
                    }
                    .friendsChatMessageFrame(
                      !hasMessageText && shiftSnapshot == nil && index == imageAttachments.count - 1
                        ? messageFrame : nil
                    )
                    .overlay(alignment: reactionAlignment) {
                      if !hasMessageText, !showsFallbackBubble, shiftSnapshot == nil {
                        let reactionTarget = imageReactionTarget(
                          for: attachment,
                          index: index,
                          imageCount: imageAttachments.count,
                          allowsMessageFallback: !isShowingAttachmentReactionTarget
                        )
                        reactionStrip(
                          for: reactionTarget.reactions,
                          attachmentId: reactionTarget.attachmentId
                        )
                      }
                    }
                  }
                }

                if let shiftSnapshot {
                  replySwipeContainer(id: "shift-\(message.id)") {
                    ChatShiftSnapshotCard(
                      snapshot: shiftSnapshot,
                      isCurrentUser: isCurrentUser,
                      showsOwnerHeader: shiftSnapshot.ownerUserId != message.senderUserId,
                      topInset: imageAttachments.isEmpty ? 0 : Spacing.xs,
                      onTap: messageFrame == nil
                        ? {
                          onOpenShiftSnapshot(shiftSnapshot)
                        } : nil
                    )
                  }
                  .friendsChatMessageFrame(
                    hasMessageText || !imageAttachments.isEmpty ? nil : messageFrame
                  )
                  .overlay(alignment: reactionAlignment) {
                    if !hasMessageText, imageAttachments.isEmpty {
                      reactionStrip(for: message.reactions)
                    }
                  }
                }

                if showsFallbackBubble, let fallbackPreviewText {
                  FriendsChatReactionAnchoredBubbleCard(
                    isCurrentUser: isCurrentUser,
                    groupContext: groupContext,
                    minWidth: Self.minimumBubbleWidthForTimestamp,
                    maxWidth: resolvedMaximumTextBubbleWidth,
                    messageFrame: messageFrame,
                    replySwipe: textBubbleReplySwipeConfiguration(id: "fallback-\(message.id)")
                  ) {
                    Text(fallbackPreviewText)
                      .font(.tidexBody)
                      .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
                      .multilineTextAlignment(.leading)
                      .fixedSize(horizontal: false, vertical: true)
                  } reaction: {
                    reactionStrip(for: message.reactions)
                  }
                }

                if hasMessageText {
                  FriendsChatReactionAnchoredBubbleCard(
                    isCurrentUser: isCurrentUser,
                    groupContext: groupContext,
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
                }
              }

              if showsMetadataRow {
                HStack(spacing: Spacing.xxs) {
                  if isCurrentUser {
                    if let inlineMetadataStatus {
                      statusView(inlineMetadataStatus)
                    }

                    if message.editedAt != nil {
                      Text(String(localized: "friends.chat.edited", table: "Localizable"))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    }

                  } else {
                    if message.editedAt != nil {
                      Text(String(localized: "friends.chat.edited", table: "Localizable"))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    if let inlineMetadataStatus {
                      statusView(inlineMetadataStatus)
                    }
                  }
                }
                .font(.tidexMicro)
                .foregroundColor(.tidexTextMuted)
                .fixedSize(horizontal: true, vertical: false)
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
  }

  private var shouldHighlightWholeMessage: Bool {
    isHighlighted && highlightedAttachmentId == nil
      && !message.attachments.contains {
        $0.kind == .image
      }
  }

  private var resolvedMaximumTextBubbleWidth: CGFloat {
    FriendsChatTimestampRevealResolver.contentMaxWidth(
      baseWidth: Self.maximumTextBubbleWidth,
      isCurrentUser: isCurrentUser
    )
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
        .foregroundColor(.tidexTextMuted)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: FriendsChatTimestampRevealResolver.revealWidth, alignment: .trailing)
        .padding(.trailing, Spacing.sm)
        .opacity(timestampRevealOpacity)
    }
    .allowsHitTesting(false)
  }

  private var timestampRevealOpacity: Double {
    let progress = timestampRevealOffset / FriendsChatTimestampRevealResolver.revealWidth
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

    let emptyWidth = payloadFrame.minX - rowFrame.minX
    return max(min(emptyWidth, rowFrame.width), 0)
  }

  private var timestampRevealSurfaceHeight: CGFloat {
    max(rowFrame.height, 1)
  }

  private static func unionFrame(_ frames: Dictionary<String, CGRect>.Values) -> CGRect {
    let union =
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

    guard timestampRevealOffset != 0 else { return }
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
      .onAppear {
        ReplySwipeHaptics.prepareIfNeeded()
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
        .foregroundColor(.tidexTextOnBrand)
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
    guard activeReplySwipePayloadId == id else { return 0 }
    return min(
      Double(abs(replySwipeOffset)) / Double(FriendsChatReplySwipeResolver.actionWidth * 0.6),
      1
    )
  }

  private var replySwipeActionScale: CGFloat {
    let progress = min(abs(replySwipeOffset) / FriendsChatReplySwipeResolver.actionWidth, 1)
    return 0.7 + (progress * 0.3)
  }

  private var renderedReplySwipeOffset: CGFloat {
    replySwipeOffset
  }

  private func textBubbleReplySwipeConfiguration(id: String) -> FriendsChatReplySwipeConfiguration?
  {
    guard onReplySwipe != nil else { return nil }
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

    let crossedThreshold = FriendsChatReplySwipeResolver.crossedThreshold(offset: replySwipeOffset)
    if crossedThreshold && !hasTriggeredReplySwipeHaptic {
      hasTriggeredReplySwipeHaptic = true
      ReplySwipeHaptics.impact.impactOccurred()
      ReplySwipeHaptics.impact.prepare()
    }
  }

  private func handleReplySwipeEnded(id: String, value: FriendsChatReplyDragValue) {
    let finalOffset = replySwipeOffset
    hasTriggeredReplySwipeHaptic = false

    guard finalOffset != 0 else {
      if activeReplySwipePayloadId == id {
        activeReplySwipePayloadId = nil
      }
      return
    }

    let outcome = replySwipeOutcome(offset: finalOffset, velocity: value.velocity.width)

    withAnimation(.easeOut(duration: Self.replySwipeResetAnimationDuration)) {
      replySwipeOffset = 0
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + Self.replySwipeResetAnimationDuration) {
      if activeReplySwipePayloadId == id {
        activeReplySwipePayloadId = nil
      }
    }

    guard outcome == .trigger, let onReplySwipe else { return }

    ReplySwipeHaptics.impact.impactOccurred()
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.replySwipeResetAnimationDuration + 0.04
    ) {
      onReplySwipe()
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

    case .delivered:
      HStack(spacing: 3) {
        Image(systemName: "checkmark")
          .font(.system(size: 11, weight: .semibold))

        Text(.friendsChatStatusDelivered)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }

    case .read:
      HStack(spacing: 3) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.tidexBlue)

        Text(.friendsChatStatusRead)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }

    case .failed:
      HStack(spacing: 4) {
        Image(systemName: "exclamationmark.circle.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.tidexError)

        Text(.friendsChatStatusFailed)
          .foregroundColor(.tidexError)
          .lineLimit(1)
          .minimumScaleFactor(0.9)
          .fixedSize(horizontal: true, vertical: false)

        Button {
          onRetry()
        } label: {
          Text(.commonRetry)
            .foregroundColor(.tidexBlue)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var inlineMetadataStatus: FriendsChatMessageStatus? {
    guard let messageStatus else { return nil }
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
                .foregroundColor(.tidexTextSecondary)
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

    if allowsMessageFallback && index == imageCount - 1 {
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
        size: Self.avatarSize,
        cornerRadius: CornerRadius.md
      )
      .padding(.top, 2)
    } else {
      Color.clear
        .frame(width: Self.avatarSize, height: Self.avatarSize)
    }
  }
}

extension FriendLastMessagePreviewKind {
  var friendsChatReplyIconSystemName: String? {
    switch self {
    case .text:
      return nil
    case .image:
      return "photo"
    case .shiftSnapshot:
      return "calendar.badge.clock"
    case .unknown:
      return "questionmark.circle"
    }
  }
}

struct FriendsChatEmojiGlyph: View {
  let emoji: String
  let size: CGFloat

  var body: some View {
    Text(verbatim: emoji)
      .font(.custom("Apple Color Emoji", size: size))
      .lineLimit(1)
      .fixedSize()
      .minimumScaleFactor(1)
      .accessibilityLabel(Text(verbatim: emoji))
  }
}

extension FriendMessageAttachment {
  func friendsChatImageFrameSize(
    maxDimension: CGFloat = 220,
    minDimension: CGFloat = 120
  ) -> CGSize {
    guard
      let width,
      let height,
      width > 0,
      height > 0
    else {
      return CGSize(width: 180, height: 180)
    }

    let aspectRatio = CGFloat(width) / CGFloat(height)

    if aspectRatio >= 1 {
      let scaledHeight = max(minDimension, maxDimension / aspectRatio)
      return CGSize(width: maxDimension, height: min(maxDimension, scaledHeight))
    }

    let scaledWidth = max(minDimension, maxDimension * aspectRatio)
    return CGSize(width: min(maxDimension, scaledWidth), height: maxDimension)
  }
}

struct FriendsChatReplySwipeConfiguration {
  let id: String
  let isCurrentUser: Bool
  let offset: CGFloat
  let actionAlignment: Alignment
  let actionLabel: AnyView
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void
}

struct FriendsChatReactionAnchoredBubbleCard<Content: View, Reaction: View, Status: View>: View {
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  var minWidth: CGFloat? = nil
  var maxWidth: CGFloat? = nil
  let messageFrame: Binding<CGRect>?
  var replySwipe: FriendsChatReplySwipeConfiguration? = nil
  @ViewBuilder let content: () -> Content
  @ViewBuilder let reaction: () -> Reaction
  @ViewBuilder let status: () -> Status

  var body: some View {
    Group {
      if let minWidth, let maxWidth {
        swipeableBubbleBody
          .frame(
            minWidth: minWidth,
            maxWidth: maxWidth,
            alignment: isCurrentUser ? .trailing : .leading
          )
          .offset(x: bubbleOffset)
      } else if let maxWidth {
        swipeableBubbleBody
          .frame(maxWidth: maxWidth, alignment: isCurrentUser ? .trailing : .leading)
          .offset(x: bubbleOffset)
      } else if let minWidth {
        swipeableBubbleBody
          .frame(minWidth: minWidth, alignment: isCurrentUser ? .trailing : .leading)
          .offset(x: bubbleOffset)
      } else {
        swipeableBubbleBody
          .offset(x: bubbleOffset)
      }
    }
  }

  @ViewBuilder
  private var swipeableBubbleBody: some View {
    if let replySwipe {
      bubbleBody
        .background(replySwipeFramePreference(replySwipe.id))
        .contentShape(bubbleShape)
        .modifier(
          FriendsChatReplyGestureModifier(
            isCurrentUser: replySwipe.isCurrentUser,
            onChanged: replySwipe.onChanged,
            onEnded: replySwipe.onEnded
          )
        )
        .overlay(alignment: replySwipe.actionAlignment) {
          replySwipe.actionLabel
            .allowsHitTesting(false)
        }
    } else {
      bubbleBody
    }
  }

  private func replySwipeFramePreference(_ id: String) -> some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: FriendsChatReplyPayloadFramePreferenceKey.self,
        value: [id: proxy.frame(in: .global)]
      )
    }
  }

  private var bubbleBody: some View {
    content()
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(
        bubbleShape
          .fill(isCurrentUser ? Color.tidexBrandPrimary : Color.tidexSurfacePrimary)
      )
      .overlay(
        bubbleShape
          .stroke(
            isCurrentUser ? Color.clear : Color.tidexBorderSubtle.opacity(0.45),
            lineWidth: 1
          )
      )
      .overlay(alignment: isCurrentUser ? .topLeading : .topTrailing) {
        reaction()
      }
      .overlay(alignment: isCurrentUser ? .bottomLeading : .bottomTrailing) {
        status()
      }
      .friendsChatMessageFrame(messageFrame)
  }

  private var bubbleOffset: CGFloat {
    replySwipe?.offset ?? 0
  }

  private var bubbleShape: some InsettableShape {
    UnevenRoundedRectangle(
      cornerRadii: RectangleCornerRadii(
        topLeading: topLeadingRadius,
        bottomLeading: bottomLeadingRadius,
        bottomTrailing: bottomTrailingRadius,
        topTrailing: topTrailingRadius
      ),
      style: .continuous
    )
  }

  private var topLeadingRadius: CGFloat {
    if !isCurrentUser && groupContext.joinsPrevious {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private var bottomLeadingRadius: CGFloat {
    if !isCurrentUser && groupContext.joinsNext {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private var bottomTrailingRadius: CGFloat {
    if isCurrentUser && groupContext.joinsNext {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private var topTrailingRadius: CGFloat {
    if isCurrentUser && groupContext.joinsPrevious {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }
}

extension FriendsChatReactionAnchoredBubbleCard where Status == EmptyView {
  init(
    isCurrentUser: Bool,
    groupContext: FriendsChatMessageGroupContext,
    minWidth: CGFloat? = nil,
    maxWidth: CGFloat? = nil,
    messageFrame: Binding<CGRect>?,
    replySwipe: FriendsChatReplySwipeConfiguration? = nil,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder reaction: @escaping () -> Reaction
  ) {
    self.isCurrentUser = isCurrentUser
    self.groupContext = groupContext
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.messageFrame = messageFrame
    self.replySwipe = replySwipe
    self.content = content
    self.reaction = reaction
    self.status = { EmptyView() }
  }
}

extension View {
  @ViewBuilder
  fileprivate func friendsChatMessageFrame(_ messageFrame: Binding<CGRect>?) -> some View {
    if let messageFrame {
      frameGetter(messageFrame)
    } else {
      self
    }
  }
}

private struct FriendsChatDateSeparator: View {
  let date: Date

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Rectangle()
        .fill(Color.tidexBorderSubtle)
        .frame(height: 1)

      Text(separatorText)
        .font(.tidexMicro)
        .foregroundColor(.tidexTextMuted)
        .fixedSize(horizontal: true, vertical: false)

      Rectangle()
        .fill(Color.tidexBorderSubtle)
        .frame(height: 1)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
  }

  private var separatorText: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
      return String(localized: .commonToday)
    }
    if calendar.isDateInYesterday(date) {
      return String(localized: .commonYesterday)
    }

    if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
      return date.formatted(
        .dateTime
          .weekday(.wide)
          .day()
          .month(.wide)
      )
    }

    return date.formatted(
      .dateTime
        .weekday(.wide)
        .day()
        .month(.wide)
        .year()
    )
  }
}

private struct FriendsChatMessageReplyPreview: View {
  let preview: FriendsChatReplyPreviewModel
  let isCurrentUser: Bool
  let isHighlighted: Bool
  var maxWidth: CGFloat? = nil
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(alignment: .top, spacing: Spacing.xs) {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
          .fill(accentColor)
          .frame(width: 3)

        FriendsChatReplyPreviewContent(
          preview: preview,
          isCurrentUser: isCurrentUser,
          accentColor: accentColor,
          textColor: textColor,
          snippetLineLimit: 2,
          thumbnailSize: CGSize(width: 56, height: 56),
          hidesImageOnlySnippet: true
        )
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .fixedSize(horizontal: false, vertical: true)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(replyBackgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(borderColor, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .frame(maxWidth: maxWidth, alignment: isCurrentUser ? .trailing : .leading)
  }

  private var replyBackgroundColor: Color {
    if isCurrentUser {
      return isHighlighted ? Color.black.opacity(0.24) : Color.black.opacity(0.18)
    }
    return isHighlighted ? Color.tidexBlue.opacity(0.08) : Color.tidexSurfaceSecondary.opacity(0.72)
  }

  private var textColor: Color {
    if isCurrentUser {
      return Color.tidexTextOnBrand.opacity(0.88)
    }
    return .tidexTextMuted
  }

  private var accentColor: Color {
    if isCurrentUser {
      return Color.white.opacity(0.78)
    }
    return Color.tidexBlue.opacity(0.7)
  }

  private var borderColor: Color {
    if isCurrentUser {
      return isHighlighted ? Color.white.opacity(0.32) : Color.white.opacity(0.18)
    }
    return isHighlighted ? Color.tidexBlue.opacity(0.45) : Color.tidexBorder.opacity(0.4)
  }
}

struct FriendsChatReplyPreviewContent: View {
  enum ImageLayout {
    case thumbnailThenSnippet
  }

  let preview: FriendsChatReplyPreviewModel
  let isCurrentUser: Bool
  let accentColor: Color
  let textColor: Color
  let snippetLineLimit: Int
  let thumbnailSize: CGSize
  var imageLayout: ImageLayout = .thumbnailThenSnippet
  var hidesImageOnlySnippet = false

  var body: some View {
    Group {
      if !preview.imageAttachments.isEmpty {
        imageContent
      } else {
        textOnlyContent
      }
    }
  }

  private var imageContent: some View {
    switch imageLayout {
    case .thumbnailThenSnippet:
      VStack(alignment: .leading, spacing: 3) {
        senderNameLabel

        HStack(alignment: .top, spacing: Spacing.xs) {
          imageThumbnails

          if let snippetText {
            snippetLabel(snippetText)
          }
        }
      }
    }
  }

  private var textOnlyContent: some View {
    VStack(alignment: .leading, spacing: 3) {
      senderNameLabel

      HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
        if let iconSystemName = preview.iconPreviewKind?.friendsChatReplyIconSystemName {
          Image(systemName: iconSystemName)
            .font(.tidexCaptionRegular)
            .foregroundColor(textColor)
        }

        snippetLabel(preview.snippet)
      }
    }
  }

  private var senderNameLabel: some View {
    Text(preview.senderName)
      .font(.tidexCaptionStrong)
      .foregroundColor(accentColor)
  }

  private var snippetText: String? {
    if hidesImageOnlySnippet, preview.previewKind == .image {
      return nil
    }

    return preview.snippet
  }

  private func snippetLabel(_ text: String) -> some View {
    Text(text)
      .font(.tidexFootnote)
      .foregroundColor(textColor)
      .multilineTextAlignment(.leading)
      .lineLimit(snippetLineLimit)
  }

  private var displayedImageAttachments: ArraySlice<FriendMessageAttachment> {
    preview.imageAttachments.prefix(3)
  }

  private var overflowImageCount: Int {
    max(0, preview.imageAttachments.count - displayedImageAttachments.count)
  }

  private var multiThumbnailSize: CGSize {
    CGSize(
      width: min(thumbnailSize.width, 34),
      height: min(thumbnailSize.height, 34)
    )
  }

  private var imageThumbnails: some View {
    HStack(spacing: Spacing.xxxs) {
      ForEach(Array(displayedImageAttachments.enumerated()), id: \.element.id) {
        index, attachment in
        thumbnail(
          for: attachment,
          size: preview.imageAttachments.count > 1 ? multiThumbnailSize : thumbnailSize
        )
        .overlay {
          if overflowImageCount > 0, index == displayedImageAttachments.count - 1 {
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
              .fill(Color.black.opacity(0.45))
              .overlay {
                Text("+\(overflowImageCount)")
                  .font(.tidexCaptionStrong)
                  .foregroundColor(.white)
              }
          }
        }
      }
    }
    .accessibilityHidden(true)
  }

  private func thumbnail(
    for imageAttachment: FriendMessageAttachment,
    size: CGSize
  ) -> some View {
    FriendsChatImageAttachmentCard(
      attachment: imageAttachment,
      isCurrentUser: isCurrentUser,
      displaySize: size,
      cornerRadius: CornerRadius.md,
      placeholderSymbolSize: 14
    )
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct ChatShiftSnapshotCard: View {
  let snapshot: FriendShiftSnapshot
  let isCurrentUser: Bool
  var showsOwnerHeader = true
  var topInset: CGFloat = 0
  var onTap: (() -> Void)? = nil
  @State private var shouldSuppressNextTap = false

  private var ownerPrimaryTextColor: Color {
    .tidexTextMuted
  }

  @ViewBuilder
  var body: some View {
    if let onTap {
      cardContent
        .contentShape(Rectangle())
        .onLongPressGesture(
          minimumDuration: FriendsThreadAttachmentTapGuard.messageMenuRecognitionDuration,
          maximumDistance: 20,
          perform: {
            shouldSuppressNextTap = true
          },
          onPressingChanged: { _ in }
        )
        .onTapGesture {
          guard !shouldSuppressNextTap else {
            shouldSuppressNextTap = false
            return
          }
          onTap()
        }
    } else {
      cardContent
    }
  }

  private var cardContent: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if showsOwnerHeader {
        ownerHeader
          .padding(.horizontal, Spacing.sm)
          .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
      }

      SharedShiftRow(
        shift: snapshot.renderableShift,
        isToday: snapshot.shiftDate == todayISO(),
        showEarnings: snapshot.includesEarnings,
        currency: snapshot.currency
      )
    }
    .padding(.top, topInset)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var ownerHeader: some View {
    HStack(alignment: .center, spacing: Spacing.xs) {
      if isCurrentUser {
        Spacer(minLength: 0)
        ownerName
        ownerAvatar
      } else {
        ownerAvatar
        ownerName
        Spacer(minLength: 0)
      }
    }
  }

  private var ownerAvatar: some View {
    AvatarView(
      url: snapshot.ownerAvatarUrl,
      initials: snapshot.ownerInitials,
      size: AvatarView.Size.small,
      cornerRadius: CornerRadius.sm
    )
  }

  private var ownerName: some View {
    Text(snapshot.ownerFirstName)
      .font(.tidexCaptionStrong)
      .foregroundColor(ownerPrimaryTextColor)
      .lineLimit(1)
  }
}

private struct FriendsChatImageView: View {
  let messageId: String
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let canOpenAttachment: Bool
  let canReact: Bool
  let isHighlighted: Bool
  let onOpenImageAttachment: (FriendMessageAttachment) -> Void
  let onReactionPressChanged: (FriendMessageAttachment, Bool) -> Void
  let onPrepareReaction: (FriendMessageAttachment) -> Void

  @State private var shouldSuppressNextTap = false

  var body: some View {
    let onImageTap: (() -> Void)? = canOpenAttachment ? handleImageTap : nil

    FriendsChatImageAttachmentCard(
      attachment: attachment,
      isCurrentUser: isCurrentUser,
      isHighlighted: isHighlighted,
      onTap: onImageTap
    )
    .onLongPressGesture(
      minimumDuration: FriendsThreadAttachmentTapGuard.messageMenuRecognitionDuration,
      maximumDistance: 20,
      perform: {
        shouldSuppressNextTap = true
        guard canReact else { return }
        FriendsThreadAttachmentReactionMenuTarget.set(
          messageId: messageId,
          attachmentId: attachment.id
        )
        onPrepareReaction(attachment)
      },
      onPressingChanged: { isPressing in
        if isPressing, canReact {
          FriendsThreadAttachmentReactionMenuTarget.set(
            messageId: messageId,
            attachmentId: attachment.id
          )
          return
        }
        onReactionPressChanged(attachment, false)
      }
    )
    .onChange(of: canReact) { _, canReact in
      if canReact {
        return
      }
      shouldSuppressNextTap = false
      FriendsThreadAttachmentReactionMenuTarget.clear(
        messageId: messageId,
        attachmentId: attachment.id
      )
      onReactionPressChanged(attachment, false)
    }
    .onAppear {
      if !canOpenAttachment {
        FriendsThreadAttachmentTapSuppressor.suppressNextTap(
          messageId: messageId,
          attachmentId: attachment.id
        )
      }
    }
  }

  private func handleImageTap() {
    guard !shouldSuppressNextTap else {
      shouldSuppressNextTap = false
      return
    }
    guard
      !FriendsThreadAttachmentTapSuppressor.consumeSuppressedTap(
        messageId: messageId,
        attachmentId: attachment.id
      )
    else {
      return
    }
    FriendsThreadAttachmentReactionMenuTarget.clear(
      messageId: messageId,
      attachmentId: attachment.id
    )
    onReactionPressChanged(attachment, false)
    onOpenImageAttachment(attachment)
  }
}

private struct FriendsChatReplyPayloadFramePreferenceKey: PreferenceKey {
  static var defaultValue: [String: CGRect] = [:]

  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue()) { _, new in new }
  }
}

struct FriendsChatReplyDragValue {
  let location: CGPoint
  let startLocation: CGPoint
  let translation: CGSize
  let velocity: CGSize

  init(
    location: CGPoint,
    startLocation: CGPoint,
    translation: CGSize,
    velocity: CGSize
  ) {
    self.location = location
    self.startLocation = startLocation
    self.translation = translation
    self.velocity = velocity
  }

  init(_ value: DragGesture.Value) {
    self.init(
      location: value.location,
      startLocation: value.startLocation,
      translation: value.translation,
      velocity: value.velocity
    )
  }
}

private struct FriendsChatReplyGestureModifier: ViewModifier {
  let isCurrentUser: Bool
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void

  private var direction: FriendsChatReplySwipeDirection {
    isCurrentUser ? .left : .right
  }

  func body(content: Content) -> some View {
    content.overlay {
      FriendsChatHorizontalPanSurface(
        targetKind: .replyPayload(direction: direction),
        minimumDistance: FriendsChatReplySwipeResolver.minimumDistance,
        direction: direction,
        onChanged: onChanged,
        onEnded: onEnded
      )
    }
  }
}

enum FriendsChatGestureTargetKind {
  case replyPayload(direction: FriendsChatReplySwipeDirection)
  case attachmentPhotoCarousel
  case timestampRevealGutter
}

final class FriendsChatGestureTargetView: UIView {
  var kind: FriendsChatGestureTargetKind

  init(kind: FriendsChatGestureTargetKind) {
    self.kind = kind
    super.init(frame: .zero)
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    false
  }
}

final class FriendsChatDirectionalPanGestureRecognizer: UIPanGestureRecognizer {
  var targetKind: FriendsChatGestureTargetKind?
  var direction: FriendsChatReplySwipeDirection?
}

struct FriendsChatGestureTargetSurface: UIViewRepresentable {
  let targetKind: FriendsChatGestureTargetKind

  func makeUIView(context _: Context) -> UIView {
    FriendsChatGestureTargetView(kind: targetKind)
  }

  func updateUIView(_ uiView: UIView, context _: Context) {
    if let targetView = uiView as? FriendsChatGestureTargetView {
      targetView.kind = targetKind
    }
  }
}

private struct FriendsChatHorizontalPanSurface: UIViewRepresentable {
  let targetKind: FriendsChatGestureTargetKind
  let minimumDistance: CGFloat
  let direction: FriendsChatReplySwipeDirection
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      targetKind: targetKind,
      minimumDistance: minimumDistance,
      direction: direction,
      onChanged: onChanged,
      onEnded: onEnded
    )
  }

  func makeUIView(context: Context) -> UIView {
    let view = FriendsChatGestureTargetView(kind: targetKind)
    context.coordinator.attach(to: view)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    if let targetView = uiView as? FriendsChatGestureTargetView {
      targetView.kind = targetKind
    }
    context.coordinator.targetKind = targetKind
    context.coordinator.minimumDistance = minimumDistance
    context.coordinator.direction = direction
    context.coordinator.onChanged = onChanged
    context.coordinator.onEnded = onEnded
    context.coordinator.attach(to: uiView)
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    coordinator.detach()
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var targetKind: FriendsChatGestureTargetKind
    var minimumDistance: CGFloat
    var direction: FriendsChatReplySwipeDirection
    var onChanged: (FriendsChatReplyDragValue) -> Void
    var onEnded: (FriendsChatReplyDragValue) -> Void
    private weak var view: UIView?
    private weak var gestureHostView: UIView?
    private var recognizer: UIPanGestureRecognizer?
    private var hasPassedMinimumDistance = false

    init(
      targetKind: FriendsChatGestureTargetKind,
      minimumDistance: CGFloat,
      direction: FriendsChatReplySwipeDirection,
      onChanged: @escaping (FriendsChatReplyDragValue) -> Void,
      onEnded: @escaping (FriendsChatReplyDragValue) -> Void
    ) {
      self.targetKind = targetKind
      self.minimumDistance = minimumDistance
      self.direction = direction
      self.onChanged = onChanged
      self.onEnded = onEnded
    }

    func attach(to view: UIView) {
      self.view = view
      installRecognizerIfPossible()

      DispatchQueue.main.async { [weak self, weak view] in
        guard let self, self.view === view else { return }
        self.installRecognizerIfPossible()
      }
    }

    func detach() {
      if let recognizer, let gestureHostView {
        gestureHostView.removeGestureRecognizer(recognizer)
      }
      recognizer = nil
      view = nil
      gestureHostView = nil
      hasPassedMinimumDistance = false
    }

    private func installRecognizerIfPossible() {
      guard let view, let hostView = gestureHost(for: view) else { return }
      guard gestureHostView !== hostView else { return }

      if let recognizer, let gestureHostView {
        gestureHostView.removeGestureRecognizer(recognizer)
      }

      let panRecognizer =
        recognizer
        ?? FriendsChatDirectionalPanGestureRecognizer(
          target: self,
          action: #selector(handlePan(_:))
        )
      if let directionalRecognizer = panRecognizer as? FriendsChatDirectionalPanGestureRecognizer {
        directionalRecognizer.targetKind = targetKind
        directionalRecognizer.direction = direction
      }
      panRecognizer.cancelsTouchesInView = false
      panRecognizer.delaysTouchesBegan = false
      panRecognizer.delaysTouchesEnded = false
      panRecognizer.delegate = self
      hostView.addGestureRecognizer(panRecognizer)
      self.recognizer = panRecognizer
      gestureHostView = hostView
    }

    private func gestureHost(for view: UIView) -> UIView? {
      let ancestors = sequence(first: view.superview, next: { $0?.superview })
      return ancestors.first { $0 is UITableViewCell } ?? view.superview
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let view else { return }
      let value = dragValue(from: recognizer, in: view)

      switch recognizer.state {
      case .began:
        hasPassedMinimumDistance = false
        handleChangedIfReady(value)
      case .changed:
        handleChangedIfReady(value)
      case .ended:
        handleChangedIfReady(value)
        if hasPassedMinimumDistance {
          onEnded(value)
        }
        hasPassedMinimumDistance = false
      case .cancelled, .failed:
        if hasPassedMinimumDistance {
          onEnded(value)
        }
        hasPassedMinimumDistance = false
      case .possible:
        break
      @unknown default:
        if hasPassedMinimumDistance {
          onEnded(value)
        }
        hasPassedMinimumDistance = false
      }
    }

    private func handleChangedIfReady(_ value: FriendsChatReplyDragValue) {
      if !hasPassedMinimumDistance {
        guard
          hypot(value.translation.width, value.translation.height) >= minimumDistance
        else {
          return
        }
        hasPassedMinimumDistance = true
      }

      onChanged(value)
    }

    private func dragValue(
      from recognizer: UIPanGestureRecognizer,
      in view: UIView
    ) -> FriendsChatReplyDragValue {
      let coordinateView = view.window ?? view
      let translation = recognizer.translation(in: coordinateView)
      let velocity = recognizer.velocity(in: coordinateView)
      let location = recognizer.location(in: coordinateView)
      let startLocation = CGPoint(
        x: location.x - translation.x,
        y: location.y - translation.y
      )

      return FriendsChatReplyDragValue(
        location: location,
        startLocation: startLocation,
        translation: CGSize(width: translation.x, height: translation.y),
        velocity: CGSize(width: velocity.x, height: velocity.y)
      )
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer, let view else {
        return true
      }
      guard view.bounds.contains(recognizer.location(in: view)) else { return false }
      let velocity = recognizer.velocity(in: view.window ?? view)
      return FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
        velocity: CGSize(width: velocity.x, height: velocity.y),
        direction: direction
      )
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}

private struct FriendsChatReplySwipeContainer<Content: View, ActionLabel: View>: View {
  let id: String
  let isCurrentUser: Bool
  let offset: CGFloat
  let actionAlignment: Alignment
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void
  @ViewBuilder let content: () -> Content
  @ViewBuilder let actionLabel: () -> ActionLabel

  var body: some View {
    content()
      .background(framePreference)
      .contentShape(Rectangle())
      .modifier(
        FriendsChatReplyGestureModifier(
          isCurrentUser: isCurrentUser,
          onChanged: onChanged,
          onEnded: onEnded
        )
      )
      .overlay(alignment: actionAlignment) {
        actionLabel()
          .offset(x: actionAlignment == .leading ? -48 : 48)
          .allowsHitTesting(false)
      }
      .offset(x: offset)
  }

  private var framePreference: some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: FriendsChatReplyPayloadFramePreferenceKey.self,
        value: [id: proxy.frame(in: .global)]
      )
    }
  }
}

@MainActor
final class FriendsChatImageLoader: ObservableObject {
  enum Variant {
    case original
    case display(pixelSize: CGSize)
  }

  @Published private(set) var image: UIImage?
  @Published private(set) var isLoading = false
  @Published private(set) var didFail = false

  private let variant: Variant

  init(initialImage: UIImage? = nil, variant: Variant = .original) {
    image = initialImage
    self.variant = variant
  }

  func loadIfNeeded(attachment: FriendMessageAttachment) async {
    if let image {
      self.image = image
      return
    }

    let cacheURL = Self.cacheURL(for: attachment.storagePath, variant: variant)

    if let cached = await cachedImage(for: cacheURL) {
      image = cached
      didFail = false
      return
    }

    if let cached = await originalCachedImageFallback(
      storagePath: attachment.storagePath,
      displayCacheURL: cacheURL
    ) {
      image = cached
      didFail = false
      return
    }

    guard !isLoading else { return }
    didFail = false
    isLoading = true
    defer { isLoading = false }

    do {
      let data = try await FriendsMessagingService.shared.downloadAttachmentData(
        path: attachment.storagePath
      )
      try Task.checkCancellation()
      guard let loadedImage = await Self.decodeImage(from: data, variant: variant) else { return }
      try Task.checkCancellation()
      ImageCache.shared.set(loadedImage, for: cacheURL, policy: .messageAttachment)
      image = loadedImage
      didFail = false
    } catch is CancellationError {
      didFail = false
    } catch {
      image = nil
      didFail = true
    }
  }

  private func cachedImage(for cacheURL: URL) async -> UIImage? {
    if let cached = ImageCache.shared.get(for: cacheURL, policy: .messageAttachment) {
      return cached
    }

    return await ImageCache.shared.getFromDisk(for: cacheURL, policy: .messageAttachment)
  }

  private func originalCachedImageFallback(
    storagePath: String,
    displayCacheURL: URL
  ) async -> UIImage? {
    guard case .display = variant else { return nil }

    let originalCacheURL = Self.cacheURL(for: storagePath, variant: .original)
    guard let cached = await cachedImage(for: originalCacheURL) else { return nil }
    let displayImage = await Self.displayImage(from: cached, variant: variant)
    ImageCache.shared.set(displayImage, for: displayCacheURL, policy: .messageAttachment)
    return displayImage
  }

  nonisolated static func cacheURL(for storagePath: String, variant: Variant = .original) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "friends-message-cache.local"
    components.path = "/\(storagePath)"
    switch variant {
    case .original:
      break
    case .display(let pixelSize):
      let width = Int(pixelSize.width.rounded())
      let height = Int(pixelSize.height.rounded())
      components.queryItems = [
        URLQueryItem(name: "variant", value: "display"),
        URLQueryItem(name: "w", value: "\(width)"),
        URLQueryItem(name: "h", value: "\(height)"),
      ]
    }
    return components.url ?? URL(filePath: "/tmp/friends-message-cache-fallback")
  }

  nonisolated private static func decodeImage(from data: Data, variant: Variant) async -> UIImage? {
    await Task.detached(priority: .utility) {
      autoreleasepool {
        switch variant {
        case .original:
          UIImage(data: data)
        case .display(let pixelSize):
          downsampleImage(from: data, pixelSize: pixelSize)
        }
      }
    }.value
  }

  nonisolated private static func downsampleImage(from data: Data, pixelSize: CGSize) -> UIImage? {
    let targetPixelSize = normalizedPixelSize(pixelSize)
    let maxPixelSize = max(targetPixelSize.width, targetPixelSize.height)
    guard maxPixelSize > 0 else { return UIImage(data: data) }
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
      return UIImage(data: data)
    }
    let thumbnailMaxPixelSize = thumbnailMaxPixelSize(
      for: imageSource,
      targetPixelSize: targetPixelSize
    )

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
    ]

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    else {
      return UIImage(data: data)
    }

    return UIImage(cgImage: cgImage)
  }

  nonisolated private static func displayImage(from image: UIImage, variant: Variant) async
    -> UIImage
  {
    await Task.detached(priority: .utility) {
      autoreleasepool {
        resizedDisplayImage(from: image, variant: variant)
      }
    }.value
  }

  nonisolated private static func resizedDisplayImage(from image: UIImage, variant: Variant)
    -> UIImage
  {
    guard case .display(let pixelSize) = variant else { return image }
    let targetPixelSize = normalizedPixelSize(pixelSize)
    guard max(targetPixelSize.width, targetPixelSize.height) > 0 else { return image }

    let sourcePixelWidth = image.size.width * image.scale
    let sourcePixelHeight = image.size.height * image.scale
    let sourcePixelSize = CGSize(width: sourcePixelWidth, height: sourcePixelHeight)
    let resizedPixelSize = coverPixelSize(
      for: sourcePixelSize,
      targetPixelSize: targetPixelSize
    )
    guard resizedPixelSize != sourcePixelSize else { return image }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false

    return UIGraphicsImageRenderer(size: resizedPixelSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: resizedPixelSize))
    }
  }

  nonisolated private static func normalizedPixelSize(_ pixelSize: CGSize) -> CGSize {
    CGSize(
      width: max(0, pixelSize.width.rounded(.up)),
      height: max(0, pixelSize.height.rounded(.up))
    )
  }

  nonisolated private static func thumbnailMaxPixelSize(
    for imageSource: CGImageSource,
    targetPixelSize: CGSize
  ) -> Int {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
        as? [CFString: Any],
      let pixelWidth = cgFloatProperty(kCGImagePropertyPixelWidth, in: properties),
      let pixelHeight = cgFloatProperty(kCGImagePropertyPixelHeight, in: properties)
    else {
      return Int(max(1, max(targetPixelSize.width, targetPixelSize.height)).rounded(.up))
    }

    let sourcePixelSize = orientedPixelSize(
      width: pixelWidth,
      height: pixelHeight,
      properties: properties
    )
    let resizedPixelSize = coverPixelSize(
      for: sourcePixelSize,
      targetPixelSize: targetPixelSize
    )
    return Int(max(resizedPixelSize.width, resizedPixelSize.height).rounded(.up))
  }

  nonisolated private static func orientedPixelSize(
    width: CGFloat,
    height: CGFloat,
    properties: [CFString: Any]
  ) -> CGSize {
    let orientation = intProperty(kCGImagePropertyOrientation, in: properties)
    if let orientation, [5, 6, 7, 8].contains(orientation) {
      return CGSize(width: height, height: width)
    }
    return CGSize(width: width, height: height)
  }

  nonisolated private static func cgFloatProperty(
    _ key: CFString,
    in properties: [CFString: Any]
  ) -> CGFloat? {
    if let number = properties[key] as? NSNumber {
      return CGFloat(truncating: number)
    }
    return properties[key] as? CGFloat
  }

  nonisolated private static func intProperty(
    _ key: CFString,
    in properties: [CFString: Any]
  ) -> Int? {
    if let number = properties[key] as? NSNumber {
      return number.intValue
    }
    return properties[key] as? Int
  }

  nonisolated private static func coverPixelSize(
    for sourcePixelSize: CGSize,
    targetPixelSize: CGSize
  ) -> CGSize {
    let sourceWidth = sourcePixelSize.width
    let sourceHeight = sourcePixelSize.height
    let targetWidth = targetPixelSize.width
    let targetHeight = targetPixelSize.height
    guard sourceWidth > 0, sourceHeight > 0, targetWidth > 0, targetHeight > 0 else {
      return sourcePixelSize
    }

    let scale = min(1, max(targetWidth / sourceWidth, targetHeight / sourceHeight))
    guard scale < 1 else { return sourcePixelSize }

    return CGSize(
      width: max(1, (sourceWidth * scale).rounded(.up)),
      height: max(1, (sourceHeight * scale).rounded(.up))
    )
  }
}

struct FriendsChatImageAttachmentCard: View {
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let isHighlighted: Bool
  let displaySize: CGSize?
  let cornerRadius: CGFloat
  let placeholderSymbolSize: CGFloat
  var onTap: (() -> Void)? = nil

  @StateObject private var loader: FriendsChatImageLoader

  init(
    attachment: FriendMessageAttachment,
    isCurrentUser: Bool,
    isHighlighted: Bool = false,
    displaySize: CGSize? = nil,
    cornerRadius: CGFloat = CornerRadius.lg,
    placeholderSymbolSize: CGFloat = 22,
    onTap: (() -> Void)? = nil
  ) {
    self.attachment = attachment
    self.isCurrentUser = isCurrentUser
    self.isHighlighted = isHighlighted
    self.displaySize = displaySize
    self.cornerRadius = cornerRadius
    self.placeholderSymbolSize = placeholderSymbolSize
    self.onTap = onTap
    let resolvedDisplaySize = displaySize ?? attachment.friendsChatImageFrameSize()
    let displayScale = max(UITraitCollection.current.displayScale, 1)
    let pixelSize = CGSize(
      width: resolvedDisplaySize.width * displayScale,
      height: resolvedDisplaySize.height * displayScale
    )
    let variant = FriendsChatImageLoader.Variant.display(pixelSize: pixelSize)
    let cacheURL = FriendsChatImageLoader.cacheURL(for: attachment.storagePath, variant: variant)
    let initialImage = ImageCache.shared.get(for: cacheURL, policy: .messageAttachment)
    _loader = StateObject(
      wrappedValue: FriendsChatImageLoader(initialImage: initialImage, variant: variant)
    )
  }

  var body: some View {
    ZStack {
      if let image = loader.image {
        loadedImage(image)
      } else if loader.didFail {
        placeholder {
          Image(systemName: "photo")
            .font(.system(size: placeholderSymbolSize, weight: .medium))
            .foregroundColor(.tidexTextMuted)
        }
      } else {
        placeholder {
          loadingIndicator
        }
      }
    }
    .task(id: attachment.storagePath) {
      await loader.loadIfNeeded(attachment: attachment)
    }
  }

  private var imageFrameSize: CGSize {
    displaySize ?? attachment.friendsChatImageFrameSize()
  }

  @ViewBuilder
  private func loadedImage(_ image: UIImage) -> some View {
    if let onTap {
      imageContent(image)
        .onTapGesture(perform: onTap)
    } else {
      imageContent(image)
    }
  }

  private func imageContent(_ image: UIImage) -> some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFill()
      .frame(width: imageFrameSize.width, height: imageFrameSize.height)
      .clipShape(imageShape)
      .overlay {
        imageShape
          .strokeBorder(
            imageBorderColor,
            lineWidth: 1
          )
      }
      .overlay {
        if isHighlighted {
          imageShape
            .fill(Color.tidexBlue.opacity(0.14))
        }
      }
      .contentShape(imageShape)
  }

  private var imageShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  private var imageBorderColor: Color {
    if isHighlighted {
      return .tidexBlue
    }
    return isCurrentUser ? Color.white.opacity(0.2) : Color.tidexBorder.opacity(0.45)
  }

  private var loadingIndicator: some View {
    ProgressView()
      .progressViewStyle(.circular)
      .tint(.tidexTextMuted)
      .controlSize(.regular)
      .scaleEffect(placeholderSymbolSize <= 14 ? 0.72 : 1)
  }

  @ViewBuilder
  private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    imageShape
      .fill(Color.tidexSurfacePrimary)
      .frame(width: imageFrameSize.width, height: imageFrameSize.height)
      .overlay {
        content()
      }
      .overlay {
        imageShape
          .strokeBorder(
            imageBorderColor,
            lineWidth: 1
          )
      }
  }
}

struct FriendsChatImageGalleryOverlay: View {
  let attachments: [FriendMessageAttachment]
  let initialAttachmentID: String
  let onDismiss: () -> Void
  let onSaveImage: (UIImage) async -> Bool

  @State private var selectedAttachmentID: String
  @State private var loadedImagesByAttachmentID: [String: UIImage] = [:]
  @State private var savedAttachmentIDs: Set<String> = []
  @State private var savingAttachmentID: String?
  @State private var selectedPageIsZoomed = false
  @GestureState private var dismissTranslationY: CGFloat = 0

  private let galleryDismissThreshold: CGFloat = 120

  init(
    attachments: [FriendMessageAttachment],
    initialAttachmentID: String,
    onDismiss: @escaping () -> Void,
    onSaveImage: @escaping (UIImage) async -> Bool
  ) {
    self.attachments = attachments
    self.initialAttachmentID = initialAttachmentID
    self.onDismiss = onDismiss
    self.onSaveImage = onSaveImage
    _selectedAttachmentID = State(initialValue: initialAttachmentID)
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      TabView(selection: $selectedAttachmentID) {
        ForEach(attachments) { attachment in
          FriendsChatImageGalleryPage(
            attachment: attachment,
            isSelected: attachment.id == selectedAttachmentID,
            onImageLoaded: { image in
              loadedImagesByAttachmentID[attachment.id] = image
            },
            onZoomStateChanged: { isZoomed in
              if attachment.id == selectedAttachmentID {
                selectedPageIsZoomed = isZoomed
              }
            }
          )
          .tag(attachment.id)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .offset(y: currentDismissOffsetY)

      VStack {
        topBar
          .padding(.horizontal, Spacing.mlg)
          .padding(.top, Spacing.mlg)
        Spacer()
        pageIndicator
          .padding(.bottom, Spacing.xl)
      }
    }
    .simultaneousGesture(verticalDismissGesture)
    .onChange(of: selectedAttachmentID) { _, _ in
      selectedPageIsZoomed = false
    }
    .statusBarHidden()
  }

  private var topBar: some View {
    HStack {
      if let selectedImage {
        Button {
          saveSelectedImage(selectedImage)
        } label: {
          Image(systemName: saveButtonIconName)
            .font(.system(size: 30))
            .foregroundColor(.white.opacity(0.88))
            .frame(width: 44, height: 44)
            .background(
              Circle()
                .fill(Color.black.opacity(0.32))
            )
        }
        .buttonStyle(.plain)
        .disabled(savingAttachmentID == selectedAttachmentID)
        .accessibilityLabel(
          Text(saveButtonAccessibilityLabel)
        )
      }

      Spacer()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 30))
          .foregroundColor(.white.opacity(0.88))
          .frame(width: 44, height: 44)
          .background(
            Circle()
              .fill(Color.black.opacity(0.32))
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: .commonCancel)))
    }
    .padding(.vertical, Spacing.xs)
  }

  @ViewBuilder
  private var pageIndicator: some View {
    if let selectedIndex, attachments.count > 1 {
      Text("\(selectedIndex + 1) / \(attachments.count)")
        .font(.tidexFootnoteMedium)
        .foregroundColor(.white.opacity(0.88))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
          Capsule(style: .continuous)
            .fill(Color.black.opacity(0.35))
        )
        .allowsHitTesting(false)
    }
  }

  private var selectedImage: UIImage? {
    loadedImagesByAttachmentID[selectedAttachmentID]
  }

  private var selectedImageIsSaved: Bool {
    savedAttachmentIDs.contains(selectedAttachmentID)
  }

  private var saveButtonIconName: String {
    selectedImageIsSaved ? "checkmark.circle.fill" : "arrow.down.circle.fill"
  }

  private var saveButtonAccessibilityLabel: String {
    if selectedImageIsSaved {
      return String(localized: "friends.chat.image.saved", table: "Localizable")
    }
    return String(localized: "friends.chat.action.save_image", table: "Localizable")
  }

  private var selectedIndex: Int? {
    attachments.firstIndex(where: { $0.id == selectedAttachmentID })
  }

  private var currentDismissOffsetY: CGFloat {
    guard !selectedPageIsZoomed else { return 0 }
    return max(0, dismissTranslationY)
  }

  private var verticalDismissGesture: some Gesture {
    DragGesture(minimumDistance: 12)
      .updating($dismissTranslationY) { value, state, _ in
        guard !selectedPageIsZoomed else { return }

        let horizontal = abs(value.translation.width)
        let vertical = value.translation.height

        guard vertical > 0, vertical > horizontal else { return }
        state = vertical
      }
      .onEnded { value in
        guard !selectedPageIsZoomed else { return }

        let horizontal = abs(value.translation.width)
        let vertical = value.translation.height

        guard vertical > 0, vertical > horizontal else { return }

        if vertical >= galleryDismissThreshold {
          onDismiss()
        }
      }
  }

  private func saveSelectedImage(_ image: UIImage) {
    let attachmentID = selectedAttachmentID

    guard savingAttachmentID != attachmentID else {
      return
    }

    savingAttachmentID = attachmentID

    Task {
      let didSave = await onSaveImage(image)

      await MainActor.run {
        if didSave {
          withAnimation(.snappy(duration: 0.18)) {
            _ = savedAttachmentIDs.insert(attachmentID)
          }
        }

        if savingAttachmentID == attachmentID {
          savingAttachmentID = nil
        }
      }
    }
  }
}

struct FriendsChatImageGalleryUnavailableOverlay: View {
  let onDismiss: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.black.ignoresSafeArea()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 30))
          .foregroundColor(.white.opacity(0.88))
          .frame(width: 44, height: 44)
          .background(
            Circle()
              .fill(Color.black.opacity(0.32))
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: .commonCancel)))
      .padding(.top, Spacing.mlg)
      .padding(.horizontal, Spacing.mlg)
    }
    .task {
      await MainActor.run {
        onDismiss()
      }
    }
    .statusBarHidden()
  }
}

private struct FriendsChatImageGalleryPage: View {
  let attachment: FriendMessageAttachment
  let isSelected: Bool
  let onImageLoaded: (UIImage) -> Void
  let onZoomStateChanged: (Bool) -> Void

  @StateObject private var loader: FriendsChatImageLoader

  init(
    attachment: FriendMessageAttachment,
    isSelected: Bool,
    onImageLoaded: @escaping (UIImage) -> Void,
    onZoomStateChanged: @escaping (Bool) -> Void
  ) {
    self.attachment = attachment
    self.isSelected = isSelected
    self.onImageLoaded = onImageLoaded
    self.onZoomStateChanged = onZoomStateChanged
    let cacheURL = FriendsChatImageLoader.cacheURL(for: attachment.storagePath)
    let initialImage = ImageCache.shared.get(for: cacheURL, policy: .messageAttachment)
    _loader = StateObject(
      wrappedValue: FriendsChatImageLoader(initialImage: initialImage, variant: .original)
    )
  }

  var body: some View {
    ZStack {
      if let image = loader.image {
        FriendsChatZoomableImageView(
          image: image,
          isActive: isSelected,
          onZoomStateChanged: onZoomStateChanged
        )
      } else if loader.isLoading {
        ProgressView()
          .tint(.white.opacity(0.8))
      } else {
        Image(systemName: "photo")
          .font(.system(size: 28, weight: .medium))
          .foregroundColor(.white.opacity(0.6))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .task(id: attachment.id) {
      await loader.loadIfNeeded(attachment: attachment)
      if let image = loader.image {
        onImageLoaded(image)
      }
    }
    .onChange(of: loader.image) { _, newImage in
      guard let newImage else { return }
      onImageLoaded(newImage)
    }
    .onChange(of: isSelected) { _, newValue in
      if !newValue {
        onZoomStateChanged(false)
      }
    }
  }
}

private struct FriendsChatZoomableImageView: UIViewRepresentable {
  let image: UIImage
  let isActive: Bool
  let onZoomStateChanged: (Bool) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onZoomStateChanged: onZoomStateChanged)
  }

  func makeUIView(context: Context) -> UIScrollView {
    let scrollView = ZoomScrollView()
    scrollView.delegate = context.coordinator
    scrollView.backgroundColor = .clear
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.bouncesZoom = true
    scrollView.decelerationRate = .fast
    scrollView.minimumZoomScale = 1
    scrollView.maximumZoomScale = 4
    scrollView.panGestureRecognizer.isEnabled = false

    let imageView = context.coordinator.imageView
    imageView.image = image
    imageView.contentMode = .scaleToFill
    scrollView.addSubview(imageView)

    let doubleTapRecognizer = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleDoubleTap(_:))
    )
    doubleTapRecognizer.numberOfTapsRequired = 2
    scrollView.addGestureRecognizer(doubleTapRecognizer)
    scrollView.onLayout = { [weak coordinator = context.coordinator] scrollView in
      coordinator?.layoutIfNeeded(in: scrollView)
    }
    context.coordinator.configure(image: image, in: scrollView, forceReset: true)

    return scrollView
  }

  func updateUIView(_ scrollView: UIScrollView, context: Context) {
    context.coordinator.onZoomStateChanged = onZoomStateChanged
    context.coordinator.configure(image: image, in: scrollView, forceReset: !isActive)

    if !isActive, scrollView.zoomScale > scrollView.minimumZoomScale {
      context.coordinator.resetZoom(in: scrollView)
    }
  }

  private final class ZoomScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?

    override func layoutSubviews() {
      super.layoutSubviews()
      onLayout?(self)
    }
  }

  final class Coordinator: NSObject, UIScrollViewDelegate {
    let imageView = UIImageView()
    var onZoomStateChanged: (Bool) -> Void
    private let minimumZoomEpsilon: CGFloat = 0.01
    private let minimumZoomSnapThreshold: CGFloat = 0.06
    private var currentImageIdentifier: ObjectIdentifier?
    private var lastBoundsSize: CGSize = .zero
    private var fittedImageSize: CGSize = .zero
    private var reportedIsZoomed = false
    private var isResettingZoom = false
    private var pendingImage: UIImage?

    init(onZoomStateChanged: @escaping (Bool) -> Void) {
      self.onZoomStateChanged = onZoomStateChanged
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
      imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      let isZoomed = isZoomed(scrollView)
      scrollView.isScrollEnabled = isZoomed
      scrollView.panGestureRecognizer.isEnabled = isZoomed
      centerImage(in: scrollView)
      guard !isResettingZoom else { return }
      setZoomState(isZoomed)
    }

    func scrollViewDidEndZooming(
      _ scrollView: UIScrollView,
      with _: UIView?,
      atScale scale: CGFloat
    ) {
      if scale <= scrollView.minimumZoomScale + minimumZoomSnapThreshold {
        resetZoom(in: scrollView)
        return
      }

      let isZoomed = scale > scrollView.minimumZoomScale + minimumZoomEpsilon
      scrollView.isScrollEnabled = isZoomed
      scrollView.panGestureRecognizer.isEnabled = isZoomed
      centerImage(in: scrollView)
      setZoomState(isZoomed)
    }

    @objc
    func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
      guard let scrollView = recognizer.view as? UIScrollView else { return }

      if isZoomed(scrollView) {
        resetZoom(in: scrollView)
        return
      }

      let tapPoint = recognizer.location(in: imageView)
      let zoomScale = min(scrollView.maximumZoomScale, 2)
      let width = scrollView.bounds.size.width / zoomScale
      let height = scrollView.bounds.size.height / zoomScale
      let zoomRect = CGRect(
        x: tapPoint.x - (width / 2),
        y: tapPoint.y - (height / 2),
        width: width,
        height: height
      )
      scrollView.zoom(to: zoomRect, animated: true)
      scrollView.isScrollEnabled = true
      scrollView.panGestureRecognizer.isEnabled = true
      setZoomState(true)
    }

    func configure(image: UIImage, in scrollView: UIScrollView, forceReset: Bool) {
      pendingImage = image
      let imageIdentifier = ObjectIdentifier(image)
      let boundsSize = scrollView.bounds.size

      guard boundsSize.width > 0, boundsSize.height > 0 else {
        imageView.image = image
        return
      }

      let imageChanged = imageIdentifier != currentImageIdentifier
      let boundsChanged = boundsSize != lastBoundsSize

      guard imageChanged || boundsChanged || forceReset else {
        centerImage(in: scrollView)
        return
      }

      currentImageIdentifier = imageIdentifier
      lastBoundsSize = boundsSize
      imageView.image = image
      fittedImageSize = Self.fittedSize(for: image.size, in: boundsSize)

      if imageChanged || forceReset || !isZoomed(scrollView) {
        resetZoom(in: scrollView)
        return
      }

      imageView.frame = CGRect(origin: .zero, size: fittedImageSize)
      scrollView.contentSize = fittedImageSize
      centerImage(in: scrollView)
    }

    func layoutIfNeeded(in scrollView: UIScrollView) {
      guard let pendingImage else { return }
      configure(image: pendingImage, in: scrollView, forceReset: false)
    }

    func resetZoom(in scrollView: UIScrollView) {
      guard fittedImageSize.width > 0, fittedImageSize.height > 0 else { return }

      isResettingZoom = true
      defer { isResettingZoom = false }

      scrollView.contentInset = .zero
      scrollView.contentOffset = .zero
      scrollView.minimumZoomScale = 1
      scrollView.maximumZoomScale = 4
      scrollView.zoomScale = scrollView.minimumZoomScale
      imageView.transform = .identity
      imageView.frame = CGRect(origin: .zero, size: fittedImageSize)
      scrollView.contentSize = fittedImageSize
      centerImage(in: scrollView)
      scrollView.isScrollEnabled = false
      scrollView.panGestureRecognizer.isEnabled = false
      setZoomState(false)
    }

    private func centerImage(in scrollView: UIScrollView) {
      let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
      let verticalInset = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
      imageView.center = CGPoint(
        x: scrollView.contentSize.width / 2 + horizontalInset,
        y: scrollView.contentSize.height / 2 + verticalInset
      )
    }

    private func isZoomed(_ scrollView: UIScrollView) -> Bool {
      scrollView.zoomScale > scrollView.minimumZoomScale + minimumZoomEpsilon
    }

    private func setZoomState(_ isZoomed: Bool) {
      guard reportedIsZoomed != isZoomed else { return }
      reportedIsZoomed = isZoomed
      onZoomStateChanged(isZoomed)
    }

    private static func fittedSize(for imageSize: CGSize, in boundsSize: CGSize) -> CGSize {
      guard imageSize.width > 0, imageSize.height > 0,
        boundsSize.width > 0, boundsSize.height > 0
      else {
        return boundsSize
      }

      let scale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
      return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
  }
}
