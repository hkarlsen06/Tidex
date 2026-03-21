import Auth
import Foundation
import Supabase

/// Shared Supabase client instance for the native iOS app
/// Configured to use Supabase's built-in Keychain storage for session tokens.
let supabase = SupabaseClient(
  supabaseURL: APIConfiguration.supabaseURL,
  supabaseKey: APIConfiguration.supabaseAnonKey,
  options: SupabaseClientOptions(
    auth: SupabaseClientOptions.AuthOptions(
      storage: Auth.KeychainLocalStorage(service: APIConfiguration.keychainService),
      autoRefreshToken: true,
      emitLocalSessionAsInitialSession: true
    )
  )
)
