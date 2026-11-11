import Foundation

/// Maps service errors to the shared presentation policy without exposing server text.
enum ErrorTranslations {
  /// Nil means the operation was cancelled and no error should be presented.
  @MainActor
  static func translate(_ error: Error, fallback: LocalizedStringResource? = nil) -> String? {
    guard !Task.isCancelled, !isCancellation(error) else { return nil }
    if isOffline(error) { return offlineMessage }

    switch error {
    case SharingServiceError.networkError(let underlying),
      SharingServiceError.decodingError(let underlying),
      FriendsMessagingServiceError.networkError(let underlying),
      FriendsMessagingServiceError.decodingError(let underlying),
      TariffVersionServiceError.networkError(let underlying),
      ShiftsError.dataLoadFailed(let underlying),
      DashboardError.dataLoadFailed(let underlying),
      SharingError.loadFailed(let underlying),
      StatsServiceError.computationFailed(let underlying):
      return translate(underlying, fallback: fallback)

    case SharingServiceError.httpError(let status, _),
      FriendsMessagingServiceError.httpError(let status, _):
      return UserFacingError.message(
        for: ConvexAPI.Failure.badResponse(status: status), fallback: fallback)

    case SharingServiceError.shareRejected(let failure):
      return failure?.message ?? String(localized: fallback ?? .commonErrorGeneric)

    default:
      return localMessage(for: error) ?? UserFacingError.message(for: error, fallback: fallback)
    }
  }

  /// Only these local errors contain catalog copy. Never trust arbitrary LocalizedError text.
  private static func localMessage(for error: Error) -> String? {
    switch error {
    case is JobsRepositoryError, is ShiftSaveError, is CalendarSubscriptionStoreError,
      is AuthSessionManagerError, is AuthError, is AppCoordinator.UserIdError,
      is SharingServiceError,
      is FriendsMessagingServiceError, is TariffVersionServiceError, is ShiftsError,
      is DashboardError, is SharingError, is StatsServiceError, is ExportError:
      return (error as? LocalizedError)?.errorDescription
    default:
      return nil
    }
  }

  static var offlineMessage: String {
    String(localized: .dataExportErrorNetwork)
  }

  static func isCancellation(_ error: Error) -> Bool {
    if UserFacingError.isCancellation(error) { return true }
    switch error {
    case SharingServiceError.networkError(let underlying),
      SharingServiceError.decodingError(let underlying),
      FriendsMessagingServiceError.networkError(let underlying),
      FriendsMessagingServiceError.decodingError(let underlying),
      TariffVersionServiceError.networkError(let underlying),
      ShiftsError.dataLoadFailed(let underlying),
      DashboardError.dataLoadFailed(let underlying),
      SharingError.loadFailed(let underlying),
      StatsServiceError.computationFailed(let underlying):
      return isCancellation(underlying)
    default:
      return false
    }
  }

  @MainActor
  static func isOffline(_ error: Error) -> Bool {
    switch error {
    case SharingServiceError.networkError(let underlying),
      SharingServiceError.decodingError(let underlying),
      FriendsMessagingServiceError.networkError(let underlying),
      FriendsMessagingServiceError.decodingError(let underlying),
      TariffVersionServiceError.networkError(let underlying):
      return isOffline(underlying)
    case FriendsAPIError.offline:
      return true
    default:
      return AuthSessionManager.shared.isTransientSessionResolutionError(error)
    }
  }
}
