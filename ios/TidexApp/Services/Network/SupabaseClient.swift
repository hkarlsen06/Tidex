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

/// True when GoTrue refused the stored session, so retrying can't help. Its server errors
/// and network failures are worth another try on the next launch.
func isLegacyGoTrueRefusal(_ error: Error) -> Bool {
  guard let error = error as? Auth.AuthError else { return false }
  switch error {
  case .sessionMissing:
    return true
  case .api(_, _, _, let response):
    return (400..<500).contains(response.statusCode)
  default:
    return false
  }
}
