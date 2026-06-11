// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface file_types_order prefixed_toplevel_constant
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable required_deinit unneeded_escaping
import Foundation
import Intents
import os.log

private let logger: Logger = Logger(subsystem: "no.tidex.app", category: "SiriIntents")

final class IntentHandler: INExtension {
  override func handler(for intent: INIntent) -> Any {
    switch intent {
    case is INSendMessageIntent:
      return SendMessageIntentHandler()

    default:
      return self
    }
  }
}

private final class SendMessageIntentHandler: NSObject, INSendMessageIntentHandling {
  func resolveRecipients(
    for intent: INSendMessageIntent,
    with completion: @escaping ([INSendMessageRecipientResolutionResult]) -> Void
  ) {
    Task {
      let result = await resolvedRecipients(for: intent)
      completion(result)
    }
  }

  func resolveContent(
    for intent: INSendMessageIntent,
    with completion: @escaping (INStringResolutionResult) -> Void
  ) {
    let content = normalizedContent(intent.content)
    guard let content else {
      completion(.needsValue())
      return
    }

    completion(.success(with: content))
  }

  func confirm(
    intent: INSendMessageIntent,
    completion: @escaping (INSendMessageIntentResponse) -> Void
  ) {
    guard SharedKeychainStorage.hasValidToken else {
      completion(INSendMessageIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
      return
    }

    guard normalizedContent(intent.content) != nil else {
      completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
      return
    }

    guard resolvedRecipientUserIds(from: intent).count == 1 else {
      completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
      return
    }

    completion(INSendMessageIntentResponse(code: .ready, userActivity: nil))
  }

  func handle(
    intent: INSendMessageIntent,
    completion: @escaping (INSendMessageIntentResponse) -> Void
  ) {
    let recipientUserIds = resolvedRecipientUserIds(from: intent)
    guard recipientUserIds.count == 1,
      let recipientUserId = recipientUserIds.first,
      let content = normalizedContent(intent.content)
    else {
      completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
      return
    }

    Task {
      do {
        try await ShareExtensionMessagingClient.sendTextMessage(
          to: recipientUserId,
          message: content
        )
        completion(INSendMessageIntentResponse(code: .success, userActivity: nil))
      } catch FriendsAPIError.noAccessToken {
        completion(INSendMessageIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
      } catch {
        logger.error("Siri message send failed: \(error.localizedDescription, privacy: .public)")
        completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
      }
    }
  }

  private func resolvedRecipients(for intent: INSendMessageIntent) async
    -> [INSendMessageRecipientResolutionResult]
  {
    guard let requestedRecipients = intent.recipients, !requestedRecipients.isEmpty else {
      return [.needsValue()]
    }

    let availableRecipients: [ShareRecipient]
    do {
      availableRecipients = try await ShareExtensionMessagingClient.fetchRecipients()
    } catch {
      logger.error("Siri recipient fetch failed: \(error.localizedDescription, privacy: .public)")
      return requestedRecipients.map { _ in .unsupported() }
    }

    return requestedRecipients.map { requestedRecipient in
      resolve(requestedRecipient, availableRecipients: availableRecipients)
    }
  }

  private func resolve(
    _ requestedRecipient: INPerson,
    availableRecipients: [ShareRecipient]
  ) -> INSendMessageRecipientResolutionResult {
    if let customIdentifier = normalizedIdentifier(requestedRecipient.customIdentifier),
      let exactRecipient = availableRecipients.first(where: { $0.id == customIdentifier })
    {
      return .success(with: person(for: exactRecipient))
    }

    let spokenName =
      normalizedNonEmpty(requestedRecipient.displayName)
      ?? normalizedNonEmpty(requestedRecipient.personHandle?.value)
    let matches = SiriMessageRecipientMatcher.matches(
      for: spokenName,
      in: availableRecipients
    )

    switch matches.count {
    case 0:
      return .unsupported()

    case 1:
      return .success(with: person(for: matches[0]))

    default:
      return .disambiguation(with: matches.map(person(for:)))
    }
  }

  private func person(for recipient: ShareRecipient) -> INPerson {
    let handleValue = recipient.statusText ?? recipient.displayName
    let image: INImage?
    if let avatarURL = recipient.avatarURL {
      image = INImage(url: avatarURL)
    } else {
      image = nil
    }

    return INPerson(
      personHandle: INPersonHandle(value: handleValue, type: .unknown),
      nameComponents: nil,
      displayName: recipient.displayName,
      image: image,
      contactIdentifier: recipient.id,
      customIdentifier: recipient.id
    )
  }

  private func resolvedRecipientUserIds(from intent: INSendMessageIntent) -> [String] {
    guard let recipients = intent.recipients, !recipients.isEmpty else { return [] }

    let userIds = recipients.compactMap { recipient in
      normalizedIdentifier(recipient.customIdentifier)
        ?? normalizedIdentifier(recipient.contactIdentifier)
    }

    guard userIds.count == recipients.count else { return [] }
    return userIds
  }

  private func normalizedContent(_ value: String?) -> String? {
    normalizedNonEmpty(value)
  }

  private func normalizedIdentifier(_ value: String?) -> String? {
    normalizedNonEmpty(value)?.lowercased()
  }

  private func normalizedNonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }

    return value
  }
}
