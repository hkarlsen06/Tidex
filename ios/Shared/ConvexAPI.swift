import Foundation

/// Calls Convex queries, mutations and actions over the deployment's HTTP API
/// (`POST /api/query`, `/api/mutation`, `/api/action`). The app and its extensions share it.
/// Chat subscriptions use the Convex client in the app instead.
///
/// Arguments are any `Encodable`. Convex rejects `null` for an optional argument, so leave a
/// missing value out of the JSON instead: synthesized `Encodable` does this for optional
/// properties. Whole numbers arrive as `1.0`, which `JSONDecoder` reads into `Int` fine.
struct ConvexAPI: Sendable {
  /// A failed call. Transport failures are thrown as the `URLError` itself, so offline checks
  /// keep working.
  enum Failure: Error, LocalizedError, Sendable {
    /// The function threw. `code` is the `code` field of a `ConvexError`, such as
    /// "not_authorized" or "conflict", and nil for an unexpected server error.
    case server(code: String?, message: String)
    /// No signed-in user, or Convex refused the token.
    case notSignedIn
    case badResponse(status: Int)

    var code: String? {
      if case .server(let code, _) = self { return code }
      return nil
    }

    var errorDescription: String? {
      switch self {
      case .server(_, let message): message
      case .notSignedIn: "Not signed in"
      case .badResponse(let status): "Unexpected response from the server (\(status))"
      }
    }
  }

  /// Returns a token for the signed-in user, or nil when nobody is signed in.
  /// `forceRefresh` is true after Convex refused the last one.
  typealias TokenProvider = @Sendable (_ forceRefresh: Bool) async throws -> String?

  let deploymentURL: URL
  let token: TokenProvider

  /// `CONVEX_URL` from the target's Info.plist, set per build configuration.
  static let configuredURL: URL = {
    guard let value = Bundle.main.infoDictionary?["CONVEX_URL"] as? String,
      let url = URL(string: value), url.scheme != nil
    else { return URL(string: "https://convex.tidex.no")! }
    return url
  }()

  private static let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    return URLSession(configuration: config)
  }()

  func query<T: Decodable>(
    _ path: String, _ args: some Encodable & Sendable = NoArgs(), as _: T.Type = T.self
  ) async throws -> T {
    try await call("query", path, args)
  }

  func mutation<T: Decodable>(
    _ path: String, _ args: some Encodable & Sendable = NoArgs(), as _: T.Type = T.self
  ) async throws -> T {
    try await call("mutation", path, args)
  }

  func action<T: Decodable>(
    _ path: String, _ args: some Encodable & Sendable = NoArgs(), as _: T.Type = T.self
  ) async throws -> T {
    try await call("action", path, args)
  }

  private func call<T: Decodable>(_ kind: String, _ path: String, _ args: some Encodable)
    async throws -> T
  {
    let body = try JSONEncoder().encode(Body(path: path, args: args))
    var retried = false
    while true {
      var request = URLRequest(url: deploymentURL.appending(path: "api/\(kind)"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      if let token = try await token(retried) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }
      request.httpBody = body
      let (data, response) = try await Self.session.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      // Convex answers 401 for an expired or unknown token. Try once more with a fresh one.
      if status == 401 {
        if retried { throw Failure.notSignedIn }
        retried = true
        continue
      }
      guard status == 200 else { throw Failure.badResponse(status: status) }
      let reply = try JSONDecoder().decode(Reply<T>.self, from: data)
      if reply.status == "success", let value = reply.value { return value }
      let code = reply.errorData?.code
      if code == "not_authorized" { throw Failure.notSignedIn }
      throw Failure.server(
        code: code, message: reply.errorData?.message ?? reply.errorMessage ?? "Server error")
    }
  }

  struct NoArgs: Encodable, Sendable {}

  /// For functions that return null or a value the caller ignores.
  struct Ignored: Decodable, Sendable {
    init(from _: Decoder) {}
  }

  private struct Body<Args: Encodable>: Encodable {
    let path: String
    let args: Args
    var format = "json"
  }

  private struct Reply<T: Decodable>: Decodable {
    let status: String
    let value: T?
    let errorMessage: String?
    let errorData: ErrorData?

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      status = try container.decode(String.self, forKey: .status)
      errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
      errorData = try? container.decodeIfPresent(ErrorData.self, forKey: .errorData)
      // Optional and Ignored decode a null value too.
      value = status == "success" ? try container.decode(T.self, forKey: .value) : nil
    }

    enum CodingKeys: String, CodingKey { case status, value, errorMessage, errorData }
  }

  private struct ErrorData: Decodable {
    let code: String?
    let message: String?
  }
}
