import SwiftUI

/// One thing VoiceOver and Voice Control can do to a chat message besides reading it.
struct FriendsChatAccessibilityAction: Identifiable {
  let id: String
  let name: String
  let perform: () -> Void

  init(name: String, perform: @escaping () -> Void) {
    id = name
    self.name = name
    self.perform = perform
  }
}

/// Spoken text for chat messages. A message reads as one element, so the label carries the
/// sender, the content, the time and the delivery state that the bubbles show in other ways.
enum FriendsChatMessageAccessibility {
  /// Joins the non-empty parts with commas, so VoiceOver pauses between them.
  static func join(_ parts: [String?]) -> String {
    parts
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }

  /// "Photo from Anna" and, when a message has several, "Photo from Anna, 2 of 3".
  static func photoLabel(senderName: String?, isCurrentUser: Bool, index: Int, count: Int)
    -> String
  {
    let base: String =
      if isCurrentUser {
        String(localized: .friendsAccessibilityYourPhoto)
      } else if let senderName, !senderName.isEmpty {
        String(localized: .friendsAccessibilityPhotoFrom(senderName))
      } else {
        String(localized: .friendsChatPreviewImage)
      }
    guard count > 1 else { return base }
    return join([base, String(localized: .friendsAccessibilityPosition(index + 1, count))])
  }

  /// The time, delivery state, edit mark and reactions that end a message's label.
  static func detailsLabel(
    time: String,
    status: FriendsChatMessageStatus?,
    isEdited: Bool,
    reactions: [FriendMessageReaction]
  ) -> String {
    join([
      time,
      status.map(statusText),
      isEdited ? String(localized: .friendsChatEdited) : nil,
      reactionsText(reactions),
    ])
  }

  static func statusText(_ status: FriendsChatMessageStatus) -> String {
    switch status {
    case .sending:
      return String(localized: .friendsChatStatusSending)

    case .delivered:
      return String(localized: .friendsChatStatusDelivered)

    case .read:
      return String(localized: .friendsChatStatusRead)

    case .failed:
      return String(localized: .friendsChatStatusFailed)
    }
  }

  static func reactionsText(_ reactions: [FriendMessageReaction]) -> String? {
    guard !reactions.isEmpty else { return nil }
    let summary = reactions
      .map { $0.count > 1 ? "\($0.emoji) \($0.count)" : $0.emoji }
      .joined(separator: ", ")
    return String(localized: .friendsAccessibilityReactions(summary))
  }

  /// "Shared a shift, Monday 13 October, 09:00 to 17:00" plus the pay when the sender shows it.
  static func shiftSummary(_ snapshot: FriendShiftSnapshot) -> String {
    let dateText = Date.fromISODateString(snapshot.shiftDate)?
      .formatted(
        .dateTime.weekday(.wide).day().month(.wide).locale(.appLocale).calendar(.gregorian))
    let pay: Double? = snapshot.taxEnabled ? snapshot.netPay : snapshot.grossPay
    let payText: String? =
      snapshot.includesEarnings
      ? pay.map { CurrencyConfig.format($0, currency: snapshot.currency) } : nil
    return join([
      String(localized: .friendsChatPreviewSharedShift),
      dateText,
      CalendarGridHelper.shiftTimesAccessibilityText(
        startTime: snapshot.startTime, endTime: snapshot.endTime),
      snapshot.jobName,
      payText,
    ])
  }
}

extension View {
  /// Makes a chat payload one VoiceOver element with `label` and the message's actions.
  /// Tappable payloads get the button trait and run `onActivate` on a double tap.
  func chatMessageAccessibility(
    label: String,
    isImage: Bool = false,
    actions: [FriendsChatAccessibilityAction],
    onActivate: (() -> Void)? = nil
  ) -> some View {
    modifier(
      FriendsChatMessageAccessibilityModifier(
        label: label, isImage: isImage, actions: actions, onActivate: onActivate)
    )
  }
}

private struct FriendsChatMessageAccessibilityModifier: ViewModifier {
  let label: String
  let isImage: Bool
  let actions: [FriendsChatAccessibilityAction]
  let onActivate: (() -> Void)?

  @ViewBuilder
  func body(content: Content) -> some View {
    let element =
      content
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(label)
      .accessibilityActions {
        ForEach(actions) { action in
          Button(action.name, action: action.perform)
        }
      }

    switch (isImage, onActivate) {
    case (true, let onActivate?):
      element
        .accessibilityAddTraits([.isImage, .isButton])
        .accessibilityAction(.default, onActivate)

    case (true, nil):
      element.accessibilityAddTraits(.isImage)

    case (false, let onActivate?):
      element
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onActivate)

    case (false, nil):
      element
    }
  }
}
