import Foundation

/// A Clerk session token for code that runs outside the app, such as the widget and the share
/// extension. The app stores each token it gets in the shared keychain. Clerk tokens last 60
/// seconds, so when the stored one has expired this asks Clerk's Frontend API for a new one,
/// the request Clerk's SDK makes, with the device token the SDK keeps in the shared group.
enum SharedAuthToken {
  /// A valid token, renewed if needed. Nil when signed out or offline.
  static func current() async -> String? {
    if let token = SharedKeychainStorage.getValidAccessToken() { return token }
    return try? await renew()
  }

  /// `ConvexAPI` for the extensions.
  static let convex = ConvexAPI(
    deploymentURL: ConvexAPI.configuredURL,
    token: { forceRefresh in
      forceRefresh ? try await renew() : await current()
    }
  )

  /// Asks Clerk for a new token for the stored session.
  static func renew() async throws -> String? {
    guard let sessionId = SharedKeychainStorage.clerkSessionId,
      let deviceToken = SharedKeychainStorage.clerkDeviceToken,
      let host = frontendAPIHost,
      var components = URLComponents(string: "https://\(host)/v1/client/sessions/\(sessionId)/tokens")
    else { return nil }
    components.queryItems = [URLQueryItem(name: "_is_native", value: "true")]
    guard let url = components.url else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(deviceToken, forHTTPHeaderField: "Authorization")
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("2026-08-20", forHTTPHeaderField: "clerk-api-version")
    request.setValue("1", forHTTPHeaderField: "x-mobile")
    // Both instances use Clerk's session minter, which wants the previous token.
    var form = [URLQueryItem(name: "organization_id", value: "")]
    if let previous = SharedKeychainStorage.lastAccessToken {
      form.append(URLQueryItem(name: "token", value: previous))
    }
    var body = URLComponents()
    body.queryItems = form
    request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
    if let rotated = http.value(forHTTPHeaderField: "Authorization"), !rotated.isEmpty {
      SharedKeychainStorage.clerkDeviceToken = rotated
    }
    struct Reply: Decodable { let jwt: String }
    let jwt = try JSONDecoder().decode(Reply.self, from: data).jwt
    let expiresAt = expiry(ofJWT: jwt) ?? Date().timeIntervalSince1970 + 50
    try? SharedKeychainStorage.storeAccessToken(jwt, expiresAt: Int(expiresAt))
    return jwt
  }

  /// The `exp` claim of a JWT, read without checking the signature.
  static func expiry(ofJWT token: String) -> TimeInterval? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var base64 = parts[1].replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: base64),
      let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let exp = claims["exp"] as? Double
    else { return nil }
    return exp
  }

  /// Clerk's Frontend API host, which the publishable key encodes:
  /// `pk_live_` or `pk_test_` and then base64 of the host and a `$`.
  static var frontendAPIHost: String? {
    guard let key = Bundle.main.infoDictionary?["CLERK_PUBLISHABLE_KEY"] as? String else {
      return nil
    }
    return host(fromPublishableKey: key)
  }

  static func host(fromPublishableKey key: String) -> String? {
    guard let encoded = key.split(separator: "_").last else { return nil }
    var base64 = String(encoded)
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: base64),
      let decoded = String(data: data, encoding: .utf8), decoded.hasSuffix("$")
    else { return nil }
    return String(decoded.dropLast())
  }
}
