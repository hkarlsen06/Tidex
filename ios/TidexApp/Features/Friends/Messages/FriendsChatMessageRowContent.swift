import SwiftUI
import UIKit

struct FriendsChatReplyPreviewModel: Equatable {
  let snippet: String?
  let hasImageAttachment: Bool
}

struct FriendsChatMessageRowContent: View {
  private static let minimumBubbleWidthForTimestamp: CGFloat = 92

  let message: FriendMessage
  let quotedPreview: FriendsChatReplyPreviewModel?
  let isCurrentUser: Bool
  let isHighlighted: Bool
  let senderFirstName: String?
  let separatorDate: Date?
  let showsSenderLabel: Bool
  let showsTimestamp: Bool
  let onReply: () -> Void
  let onReportMessage: () -> Void
  let onTapQuotedMessage: () -> Void

  var body: some View {
    let messageText = message.body?.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasMessageText = !(messageText?.isEmpty ?? true)

    return VStack(spacing: Spacing.xs) {
      if let separatorDate {
        FriendsChatDateSeparator(date: separatorDate)
      }

      ChatMessageRow(isCurrentUser: isCurrentUser, minSpacer: 48, spacing: Spacing.xxs) {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 3) {
          if showsSenderLabel, let senderFirstName, !senderFirstName.isEmpty {
            Text(senderFirstName)
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextMuted)
              .padding(.horizontal, CornerRadius.bubble)
          }

          FriendsChatReplySwipeContainer(
            isCurrentUser: isCurrentUser,
            onReply: onReply
          ) {
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Spacing.xxs) {
              if !hasMessageText, let quotedPreview {
                FriendsChatMessageReplyPreview(
                  preview: quotedPreview,
                  isCurrentUser: isCurrentUser,
                  isHighlighted: false,
                  onTap: onTapQuotedMessage
                )
              }

              ForEach(message.attachments) { attachment in
                if attachment.kind == .image {
                  FriendsChatImageView(
                    attachment: attachment,
                    isCurrentUser: isCurrentUser,
                    onReport: onReportMessage
                  )
                }
              }

              if let messageText, !messageText.isEmpty {
                ChatBubbleCard(
                  isCurrentUser: isCurrentUser,
                  minWidth: Self.minimumBubbleWidthForTimestamp,
                  maxWidth: 280
                ) {
                  VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let quotedPreview {
                      FriendsChatMessageReplyPreview(
                        preview: quotedPreview,
                        isCurrentUser: isCurrentUser,
                        isHighlighted: false,
                        onTap: onTapQuotedMessage
                      )
                    }

                    Text(messageText)
                      .font(.tidexBody)
                      .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
                  }
                }
                .contextMenu {
                  Button {
                    UIPasteboard.general.string = messageText
                  } label: {
                    Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
                  }

                  if !isCurrentUser {
                    Button(String(localized: .friendsChatReportMessage)) {
                      onReportMessage()
                    }
                  }
                }
              }
            }
          }

          if showsTimestamp {
            Text(message.createdAt.formatted(.dateTime.hour().minute()))
              .font(.tidexMicro)
              .foregroundColor(.tidexTextMuted)
              .padding(.horizontal, CornerRadius.bubble)
          }
        }
      }
    }
    .padding(.vertical, 2)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .fill(isHighlighted ? Color.tidexBlue.opacity(0.08) : Color.clear)
    )
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

private struct FriendsChatReplySwipeContainer<Content: View>: View {
  let isCurrentUser: Bool
  let onReply: () -> Void
  @ViewBuilder let content: () -> Content

  @GestureState private var dragTranslation: CGFloat = 0

  private let activationDistance: CGFloat = 72
  private let recognitionDistance: CGFloat = 22
  private let horizontalDominanceRatio: CGFloat = 1.75
  private let visualTravelLimit: CGFloat = 26

  var body: some View {
    content()
      .offset(x: limitedVisualOffset)
      .overlay(alignment: isCurrentUser ? .trailing : .leading) {
        replyIndicator
          .padding(.horizontal, Spacing.sm)
      }
      .contentShape(Rectangle())
      .simultaneousGesture(replyGesture)
      .animation(.easeOut(duration: 0.16), value: limitedVisualOffset)
  }

  private var directionalTranslation: CGFloat {
    if isCurrentUser {
      return max(0, -dragTranslation)
    }
    return max(0, dragTranslation)
  }

  private var limitedVisualOffset: CGFloat {
    let offset = min(directionalTranslation, visualTravelLimit)
    return isCurrentUser ? -offset : offset
  }

  private var replyIndicator: some View {
    Image(systemName: "arrowshape.turn.up.left.fill")
      .font(.system(size: 15, weight: .semibold))
      .foregroundColor(.tidexBlue)
      .frame(width: 28, height: 28)
      .background(
        Circle()
          .fill(Color.tidexBlue.opacity(0.14))
      )
      .opacity(min(directionalTranslation / activationDistance, 1))
      .scaleEffect(0.85 + (min(directionalTranslation / activationDistance, 1) * 0.15))
  }

  private var replyGesture: some Gesture {
    DragGesture(minimumDistance: recognitionDistance, coordinateSpace: .local)
      .updating($dragTranslation) { value, state, _ in
        let horizontalTravel = abs(value.translation.width)
        let verticalTravel = abs(value.translation.height)
        guard horizontalTravel >= recognitionDistance,
          horizontalTravel > verticalTravel * horizontalDominanceRatio
        else {
          state = 0
          return
        }
        state = value.translation.width
      }
      .onEnded { value in
        let horizontalTravel = abs(value.translation.width)
        let verticalTravel = abs(value.translation.height)
        guard horizontalTravel >= recognitionDistance,
          horizontalTravel > verticalTravel * horizontalDominanceRatio
        else { return }

        let directionalTravel = isCurrentUser ? -value.translation.width : value.translation.width
        guard directionalTravel >= activationDistance else { return }

        Haptics.play(.medium)
        onReply()
      }
  }
}

private struct FriendsChatMessageReplyPreview: View {
  let preview: FriendsChatReplyPreviewModel
  let isCurrentUser: Bool
  let isHighlighted: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(alignment: .top, spacing: Spacing.xs) {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
          .fill(accentColor)
          .frame(width: 3)

        VStack(alignment: .leading, spacing: 3) {
          if preview.hasImageAttachment {
            Image(systemName: "photo")
              .font(.tidexCaptionRegular)
              .foregroundColor(textColor)
          }

          if let snippet = preview.snippet {
            Text(snippet)
              .font(.tidexFootnote)
              .foregroundColor(textColor)
              .multilineTextAlignment(.leading)
              .lineLimit(2)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .frame(maxWidth: .infinity, alignment: .leading)
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

private struct FriendsChatImageView: View {
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let onReport: () -> Void

  @StateObject private var loader = FriendsChatImageLoader()
  @State private var selectedImageViewer: FriendsChatSelectedImageViewer?

  var body: some View {
    Group {
      if let image = loader.image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: imageFrameSize.width, height: imageFrameSize.height)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
              .strokeBorder(
                isCurrentUser ? Color.white.opacity(0.2) : Color.tidexBorder,
                lineWidth: 1
              )
          )
          .onTapGesture {
            selectedImageViewer = FriendsChatSelectedImageViewer(image: image)
          }
      } else if loader.isLoading {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfacePrimary)
          .frame(width: imageFrameSize.width, height: imageFrameSize.height)
          .overlay {
            ProgressView()
          }
      } else {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfacePrimary)
          .frame(width: imageFrameSize.width, height: imageFrameSize.height)
          .overlay {
            Image(systemName: "photo")
              .font(.tidexTitle2)
              .foregroundColor(.tidexTextMuted)
          }
      }
    }
    .task(id: attachment.id) {
      await loader.loadIfNeeded(attachment: attachment)
    }
    .contextMenu {
      if let image = loader.image {
        Button {
          UIPasteboard.general.image = image
        } label: {
          Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
        }
      }

      if !isCurrentUser {
        Button(String(localized: .friendsChatReportMessage)) {
          onReport()
        }
      }
    }
    .fullScreenCover(item: $selectedImageViewer) { viewer in
      ImageViewerOverlay(image: viewer.image) {
        selectedImageViewer = nil
      }
    }
  }

  private var imageFrameSize: CGSize {
    let maxDimension: CGFloat = 220
    let minDimension: CGFloat = 120

    guard
      let width = attachment.width,
      let height = attachment.height,
      width > 0,
      height > 0
    else {
      return CGSize(width: 180, height: 180)
    }

    let aspectRatio = CGFloat(width) / CGFloat(height)

    if aspectRatio >= 1 {
      let scaledHeight = max(minDimension, maxDimension / aspectRatio)
      return CGSize(width: maxDimension, height: min(maxDimension, scaledHeight))
    } else {
      let scaledWidth = max(minDimension, maxDimension * aspectRatio)
      return CGSize(width: min(maxDimension, scaledWidth), height: maxDimension)
    }
  }
}

@MainActor
private final class FriendsChatImageLoader: ObservableObject {
  @Published private(set) var image: UIImage?
  @Published private(set) var isLoading = false

  func loadIfNeeded(attachment: FriendMessageAttachment) async {
    if let image {
      self.image = image
      return
    }

    let cacheURL = Self.cacheURL(for: attachment.storagePath)

    if let cached = ImageCache.shared.get(for: cacheURL) {
      image = cached
      return
    }

    if let cached = await ImageCache.shared.getFromDisk(for: cacheURL) {
      image = cached
      return
    }

    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      let data = try await FriendsMessagingService.shared.downloadAttachmentData(
        path: attachment.storagePath
      )
      guard let loadedImage = await Self.decodeImage(from: data) else { return }
      ImageCache.shared.set(loadedImage, for: cacheURL)
      image = loadedImage
    } catch {
      image = nil
    }
  }

  nonisolated private static func cacheURL(for storagePath: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "friends-message-cache.local"
    components.path = "/\(storagePath)"
    return components.url ?? URL(filePath: "/tmp/friends-message-cache-fallback")
  }

  nonisolated private static func decodeImage(from data: Data) async -> UIImage? {
    await Task.detached(priority: .utility) {
      autoreleasepool {
        UIImage(data: data)
      }
    }.value
  }
}

private struct FriendsChatSelectedImageViewer: Identifiable {
  let id = UUID()
  let image: UIImage
}
