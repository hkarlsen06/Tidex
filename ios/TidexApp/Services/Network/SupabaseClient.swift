import Auth
import Foundation
import Supabase

// The GoTrue session that version N stored in the keychain. N+1 reads it only in
// `LegacySessionExchange`, to sign the user in to Clerk. Nothing else talks to Supabase.
// ponytail: remove with the Supabase package once nearly every user has updated (phase 4).
private let legacyClient = SupabaseClient(
  supabaseURL: APIConfiguration.supabaseURL,
  supabaseKey: APIConfiguration.supabaseAnonKey,
  options: SupabaseClientOptions(
    auth: SupabaseClientOptions.AuthOptions(
      storage: Auth.KeychainLocalStorage(service: APIConfiguration.keychainService),
      autoRefreshToken: false,
      emitLocalSessionAsInitialSession: true
    )
  )
)

var legacyGoTrue: AuthClient { legacyClient.auth }

/// True when GoTrue refused the stored session, so retrying can't help. GoTrue names a dead
/// refresh token with one of these codes. The SDK already turns `refresh_token_not_found`,
/// `refresh_token_already_used`, `session_not_found` and `session_expired` into
/// `sessionMissing`, and they are listed for SDK versions that don't. Any other error, such as a
/// rate limit (429), a timeout, a server error or a network failure, is worth another try.
func isLegacyGoTrueRefusal(_ error: Error) -> Bool {
  guard let error = error as? Auth.AuthError else { return false }
  switch error {
  case .sessionMissing:
    return true
  case .api(_, let code, _, _):
    return legacyGoTrueRefusalCodes.contains(code)
  default:
    return false
  }
}

private let legacyGoTrueRefusalCodes: Set<Auth.ErrorCode> = [
  .refreshTokenNotFound, .refreshTokenAlreadyUsed, .sessionNotFound, .sessionExpired,
  .userNotFound, .userBanned,
  // GoTrue's answer to a refresh token that isn't in its format.
  .validationFailed,
]
