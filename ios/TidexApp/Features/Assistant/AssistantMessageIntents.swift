import AppIntents
import Foundation
import GeoToolbox

// The messages schema decides these parameter and property names and types. Tidex sends text
// to one friend, so the intents reject attachments, groups and scheduling instead of using them.

/// Who Siri asked Tidex to message, before matching it against the user's friends.
enum MessageRecipientRequest: Equatable {
  case userId(String)
  case name(String)
}

enum MessageRecipientResolution: Equatable {
  case recipient(ShareRecipient)
  case ambiguous([ShareRecipient])
  case unknown
  case severalPeople
}

enum MessageRecipientResolver {
  /// Matches against `recipients`, the friends the server lets the user message, so an ID or
  /// name outside that list never resolves.
  static func resolve(
    _ requests: [MessageRecipientRequest],
    among recipients: [ShareRecipient]
  ) -> MessageRecipientResolution {
    guard requests.count <= 1 else { return .severalPeople }
    switch requests.first {
    case .userId(let id):
      return recipients.first { $0.id.lowercased() == id.lowercased() }.map { .recipient($0) }
        ?? .unknown

    case .name(let name):
      let matches = SiriMessageRecipientMatcher.matches(for: name, in: recipients)
      switch matches.count {
      case 0: return .unknown
      case 1: return .recipient(matches[0])
      default: return .ambiguous(matches)
      }

    case nil:
      return .unknown
    }
  }
}

@available(iOS 27, *)
@AppEntity(schema: .messages.messagePerson)
struct MessageRecipientEntity {
  static let defaultQuery = MessageRecipientQuery()

  let id: String
  var person: IntentPerson

  var displayRepresentation: DisplayRepresentation {
    if case .displayName(let name) = person.name {
      return DisplayRepresentation(title: "\(name)")
    }
    return DisplayRepresentation(title: "assistant.friend.type")
  }

  init(_ recipient: ShareRecipient) {
    id = recipient.id
    person = IntentPerson(
      identifier: .applicationDefined(recipient.id),
      name: .displayName(recipient.displayName),
      handle: IntentPerson.Handle(.applicationDefined(recipient.id)),
      image: recipient.avatarURL.map { DisplayRepresentation.Image(url: $0) }
    )
  }

  init(me userId: String) {
    id = userId
    person = IntentPerson(
      identifier: .applicationDefined(userId), name: .unknown, handle: nil, isMe: true)
  }

  var request: MessageRecipientRequest { .userId(id) }
}

@available(iOS 27, *)
struct MessageRecipientQuery: EntityStringQuery {
  @MainActor
  func entities(for identifiers: [MessageRecipientEntity.ID]) async throws
    -> [MessageRecipientEntity]
  {
    let ids = Set(identifiers.map { $0.lowercased() })
    return try await MessageRecipients.load()
      .filter { ids.contains($0.id.lowercased()) }
      .map(MessageRecipientEntity.init)
  }

  @MainActor
  func entities(matching string: String) async throws -> [MessageRecipientEntity] {
    SiriMessageRecipientMatcher.matches(for: string, in: try await MessageRecipients.load())
      .map(MessageRecipientEntity.init)
  }

  @MainActor
  func suggestedEntities() async throws -> [MessageRecipientEntity] {
    try await MessageRecipients.load().map(MessageRecipientEntity.init)
  }
}

@MainActor
enum MessageRecipients {
  /// Friends the user can message, most recent conversations first.
  static func load() async throws -> [ShareRecipient] {
    _ = try AssistantAccess.current.requireUserId()
    return try await ShareExtensionMessagingClient.fetchRecipients()
  }

  /// Asks the user to pick when the name matches more than one friend.
  @available(iOS 27, *)
  nonisolated static func resolve(
    _ requests: [MessageRecipientRequest],
    for intent: some AppIntent
  ) async throws -> ShareRecipient {
    switch MessageRecipientResolver.resolve(requests, among: try await load()) {
    case .recipient(let recipient):
      return recipient

    case .ambiguous(let matches):
      let titles = matches.map { choiceTitle(for: $0, among: matches) }
      let choice = try await intent.requestChoice(
        between: titles.map { IntentChoiceOption(title: "\($0)") },
        dialog: IntentDialog(.assistantMessageWhichFriend))
      guard let index = titles.firstIndex(where: { IntentChoiceOption(title: "\($0)") == choice })
      else {
        throw AssistantMessageError.unknownFriend
      }
      return matches[index]

    case .unknown:
      throw AssistantMessageError.unknownFriend

    case .severalPeople:
      throw AssistantMessageError.oneFriendOnly
    }
  }

  nonisolated private static func choiceTitle(for recipient: ShareRecipient, among matches: [ShareRecipient])
    -> String
  {
    let sharesName = matches.filter { $0.displayName == recipient.displayName }.count > 1
    guard sharesName, let statusText = recipient.statusText else { return recipient.displayName }
    return "\(recipient.displayName) (\(statusText))"
  }
}

enum AssistantMessageError: Error, CustomLocalizedStringResourceConvertible {
  case unknownFriend
  case oneFriendOnly
  case emptyMessage
  case unsupportedContent

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .unknownFriend:
      return .assistantMessageErrorUnknownFriend

    case .oneFriendOnly:
      return .assistantMessageErrorOneFriendOnly

    case .emptyMessage:
      return .assistantMessageErrorEmpty

    case .unsupportedContent:
      return .assistantMessageErrorUnsupportedContent
    }
  }
}

@available(iOS 27, *)
@UnionValue
enum MessageDestination {
  case people([IntentPerson])
  case messagePerson(MessageRecipientEntity)
  case messagePeople([MessageRecipientEntity])

  var requests: [MessageRecipientRequest] {
    switch self {
    case .people(let people):
      return people.map(Self.request(for:))

    case .messagePerson(let entity):
      return [entity.request]

    case .messagePeople(let entities):
      return entities.map(\.request)
    }
  }

  private static func request(for person: IntentPerson) -> MessageRecipientRequest {
    if case .applicationDefined(let id) = person.identifier {
      return .userId(id)
    }
    switch person.name {
    case .displayName(let name):
      return .name(name)

    case .components(let components):
      return .name(components.formatted())

    case .unknown:
      return .name(handleText(person.handle?.value))

    @unknown default:
      return .name(handleText(person.handle?.value))
    }
  }

  private static func handleText(_ value: IntentPerson.Handle.Value?) -> String {
    switch value {
    case .phoneNumber(let text), .emailAddress(let text), .applicationDefined(let text):
      return text

    case nil:
      return ""

    @unknown default:
      return ""
    }
  }
}

@available(iOS 27, *)
@AppIntent(schema: .messages.sendMessage)
struct SendFriendMessageIntent {
  var content: AttributedString?
  var destination: MessageDestination
  var subject: AttributedString?
  var attachments: [IntentFile]
  var audioMessage: IntentFile?
  var locations: [PlaceDescriptor]
  var links: [URL]
  var scheduledDate: Date?

  @MainActor
  func perform() async throws -> some ReturnsValue<[SentMessageEntity]> {
    let userId = try AssistantAccess.current.requireUserId()
    guard attachments.isEmpty, audioMessage == nil, locations.isEmpty, scheduledDate == nil else {
      throw AssistantMessageError.unsupportedContent
    }
    let text = MessageText.plain(subject: subject, content: content, links: links)
    guard !text.isEmpty else { throw AssistantMessageError.emptyMessage }

    let recipient = try await MessageRecipients.resolve(destination.requests, for: self)
    try await ShareExtensionMessagingClient.sendTextMessage(to: recipient.id, message: text)

    let sent = SentMessageEntity(
      id: UUID().uuidString.lowercased(),
      author: MessageRecipientEntity(me: userId),
      recipient: recipient,
      body: AttributedString(text)
    )
    return .result(value: [sent])
  }
}

@available(iOS 27, *)
@AppIntent(schema: .messages.draftMessage)
struct DraftFriendMessageIntent {
  static let supportedModes: IntentModes = .foreground

  var destination: MessageDestination?
  var subject: AttributedString?
  var content: AttributedString?
  var attachments: [IntentFile]
  var audioMessage: IntentFile?
  var locations: [PlaceDescriptor]
  var links: [URL]
  var scheduledDate: Date?

  @MainActor
  func perform() async throws -> some IntentResult {
    let userId = try AssistantAccess.current.requireUserId()
    guard let destination else {
      AppCoordinator.shared.pendingDeepLink = .sharing(
        sharerId: nil, highlightDates: nil, changes: nil)
      return .result()
    }

    let recipient = try await MessageRecipients.resolve(destination.requests, for: self)
    let thread = try await FriendsMessagingService.shared.getOrCreateDirectThread(
      otherUserId: recipient.id)
    let text = MessageText.plain(subject: subject, content: content, links: links)
    if !text.isEmpty {
      await FriendsComposerDraftStore.shared.saveDraftText(
        text, threadId: thread.id, viewerUserId: userId)
    }
    AppCoordinator.shared.pendingDeepLink = .friendChat(
      threadId: thread.id, messageId: nil, senderUserId: nil, typingUserId: nil,
      navigationRequestId: UUID())
    return .result()
  }
}

enum MessageText {
  /// Tidex messages are plain text, so a subject and links become lines of the message.
  static func plain(subject: AttributedString?, content: AttributedString?, links: [URL])
    -> String
  {
    let parts =
      [subject, content].compactMap { $0.map { String($0.characters) } }
      + links.map(\.absoluteString)
    return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }
}
