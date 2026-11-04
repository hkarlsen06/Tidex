import AppIntents
import Foundation

/// Whose data Siri, Shortcuts and Spotlight may read or change.
///
/// An admin who impersonates another user sees that user's data in the app, but the system
/// keeps Spotlight items and Siri answers across sessions, so the assistant acts for nobody then.
enum AssistantAccess: Equatable {
  case user(id: String)
  case signedOut
  case impersonating

  init(session: AuthSession?) {
    guard let session else {
      self = .signedOut
      return
    }
    self = session.user.isImpersonating ? .impersonating : .user(id: session.normalizedUserId)
  }

  /// Reads the stored session without the network, so intents work offline and in the background.
  @MainActor static var current: Self {
    Self(session: AuthSessionManager.shared.localSession())
  }

  func requireUserId() throws -> String {
    switch self {
    case .user(let id):
      return id

    case .signedOut:
      throw AssistantError.signedOut

    case .impersonating:
      throw AssistantError.impersonating
    }
  }
}

enum AssistantError: Error, CustomLocalizedStringResourceConvertible {
  case signedOut
  case impersonating
  case shiftNotFound
  case notWorking
  case clockHasNoEnd
  case recurringShift
  case shiftTooLong

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .signedOut:
      return .assistantErrorSignedOut

    case .impersonating:
      return .assistantErrorImpersonating

    case .shiftNotFound:
      return .assistantErrorShiftNotFound

    case .notWorking:
      return .assistantErrorNotWorking

    case .clockHasNoEnd:
      return .assistantErrorClockHasNoEnd

    case .recurringShift:
      return .assistantErrorRecurringShift

    case .shiftTooLong:
      return .assistantErrorShiftTooLong
    }
  }
}
