import Foundation

/// Presentation copy for failures shared by the app and its extensions.
enum UserFacingError {
  /// Cancellation is silent. Raw server and system error text belongs in diagnostic logs.
  static func message(for error: Error, fallback: LocalizedStringResource? = nil) -> String? {
    guard !Task.isCancelled, !isCancellation(error) else { return nil }
    switch error {
    case ConvexAPI.Failure.notSignedIn:
      return String(localized: .commonErrorNotAuthenticated)
    case let error as URLError where error.code == .userAuthenticationRequired:
      return String(localized: .commonErrorNotAuthenticated)
    case ConvexAPI.Failure.server(let code, _):
      return serverMessage(code: code)
    case ConvexAPI.Failure.badResponse(let status):
      return responseMessage(status: status, fallback: fallback)
    case let error as URLError where [
      .notConnectedToInternet, .networkConnectionLost, .timedOut,
      .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
      .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed,
    ].contains(error.code):
      return String(localized: .dataExportErrorNetwork)
    case let error as FriendsAPIError:
      return error.errorDescription
    default:
      return String(localized: fallback ?? .commonErrorGeneric)
    }
  }

  static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError || (error as? URLError)?.code == .cancelled { return true }
    if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
      return isCancellation(underlying)
    }
    return false
  }

  private static func responseMessage(status: Int, fallback: LocalizedStringResource?) -> String {
    switch status {
    case 401: return String(localized: .commonErrorNotAuthenticated)
    case 409: return String(localized: .commonErrorConflict)
    default: return String(localized: fallback ?? .commonErrorGeneric)
    }
  }

  private static func serverMessage(code: String?) -> String {
    switch code {
    case "not_authorized", "wrong_user":
      return String(localized: .commonErrorNotAuthenticated)
    case "conflict", "default_job_exists":
      return String(localized: .commonErrorConflict)
    case "already_exists":
      return String(localized: .calendarSubscriptionErrorAlreadyActive)
    case "username_taken":
      return String(localized: .profileErrorsUsernameTaken)
    case "username_blocked":
      return String(localized: .profileErrorsNameSafetyFilter)
    case "username_invalid":
      return String(localized: .profileErrorsUsernameInvalid)
    default:
      return String(localized: .commonErrorGeneric)
    }
  }
}
