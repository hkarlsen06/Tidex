// swiftlint:disable file_length function_body_length cyclomatic_complexity
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable anonymous_argument_in_multiline_closure conditional_returns_on_newline
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable discouraged_none_name discouraged_optional_boolean discouraged_optional_collection
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_enum_raw_value explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_types_order identifier_name
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable multiline_arguments_brackets no_magic_numbers pattern_matching_keywords
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable sorted_enum_cases strict_fileprivate switch_case_on_newline
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_body_length type_contents_order
import Foundation

#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Widget Shift Status

/// Status of a shift preview
/// Note: This mirrors the app's ShiftPreviewStatus but is local to shared extension code.
enum FriendShiftStatus: String, Codable, Sendable {
  case active
  case upcoming
  case past
}

// MARK: - Combined Friends Data

/// Combined data for a friend with their shift preview
/// Shift data for the friends widget.
struct FriendWithShift: Sendable {
  let id: String
  let displayName: String
  let initials: String
  let profilePictureUrl: String?
  let oauthAvatarUrl: String?
  let showEarnings: Bool
  let hidden: Bool

  // Shift data (if available)
  let shiftId: String?
  let shiftDate: String?
  let startTime: String?
  let endTime: String?
  let gross: Double?
  let status: FriendShiftStatus?
  var ownerTimeZone: String?

  /// Whether this friend has a shift to display
  var hasShift: Bool {
    shiftId != nil
  }

  /// Effective avatar URL (profile picture takes precedence)
  var effectiveAvatarURL: URL? {
    if let urlString = profilePictureUrl ?? oauthAvatarUrl,
      !urlString.isEmpty
    {
      return URL(string: urlString)
    }
    return nil
  }
}

// MARK: - Errors

enum FriendsAPIError: Error, LocalizedError, Sendable {
  case noAccessToken
  case networkError(underlying: String)
  case offline
  case httpError(statusCode: Int)
  case decodingError(underlying: String)
  case unauthorized

  /// Maps a transport failure to `.offline` when the device has no usable connection.
  /// The share extension can't reach `AuthSessionManager`, so it keeps its own code list.
  static func transportError(_ error: Error) -> FriendsAPIError {
    let offlineCodes: Set<URLError.Code> = [
      .timedOut,
      .cannotFindHost,
      .cannotConnectToHost,
      .networkConnectionLost,
      .dnsLookupFailed,
      .notConnectedToInternet,
      .internationalRoamingOff,
      .callIsActive,
      .dataNotAllowed,
    ]
    if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
      return .offline
    }
    return .networkError(underlying: error.localizedDescription)
  }

  /// User-facing text. The `underlying` strings are English diagnostics and stay out of it.
  var errorDescription: String? {
    switch self {
    case .noAccessToken, .unauthorized:
      return String(localized: .shareErrorSignInRequired)

    case .offline:
      return String(localized: .shareErrorOffline)

    case .networkError, .httpError, .decodingError:
      return String(localized: .shareErrorRequestFailed)
    }
  }
}

// MARK: - Friends API Client

/// Lightweight API client for fetching friends data directly
/// Fetches friend data for widgets without launching the main app.
///
/// This client fetches from the consolidated Convex `sharing:friendsBootstrap` query.
///
/// Preview selection and payroll computation are handled client-side via SharingComputeCore.
enum FriendsAPIClient {
  /// Shared URLSession with reasonable timeouts
  fileprivate static let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    return URLSession(configuration: config)
  }()

  // MARK: - Public API

  /// Fetch all friends with their shift previews in a single call
  /// Main entry point for the friends widget.
  /// - Returns: Array of friends with their shift data
  static func fetchFriendsWithShifts() async throws -> [FriendWithShift] {
    let now = Date()
    let startDate = SharingComputeCore.isoDateString(
      Calendar.gregorianCurrent.date(byAdding: .day, value: -30, to: now) ?? now)
    let endDate = SharingComputeCore.isoDateString(
      Calendar.gregorianCurrent.date(byAdding: .day, value: 30, to: now) ?? now)

    let bootstrap: FriendsTabBootstrapRPCResponse = try await fetchFriendsTabBootstrap(
      startDate: startDate,
      endDate: endDate
    )
    let sharers = bootstrap.sharers
    let activeSharers = sharers.filter { !$0.hidden }

    guard !activeSharers.isEmpty else {
      return []
    }

    let activeSharerIds = Set(activeSharers.map(\.id))
    let payloadRows = bootstrap.previewPayloads.filter { activeSharerIds.contains($0.sharerId) }

    let rowsBySharerId = Dictionary(
      payloadRows.map { ($0.sharerId, $0) }, uniquingKeysWith: { _, last in last })

    var previews: [SharingComputedPreview] = []
    previews.reserveCapacity(activeSharers.count)

    for sharer in activeSharers {
      if let payloadRow = rowsBySharerId[sharer.id] {
        let mode: SharingRPCMode = payloadRow.showEarnings ? .visible : .hidden
        let shifts = SharingComputeCore.computeShiftsInRange(
          payload: payloadRow.payloadInput,
          startDate: startDate,
          endDate: endDate,
          mode: mode
        )
        previews.append(
          SharingComputeCore.selectPreview(
            sharerId: sharer.id,
            shifts: shifts,
            showEarnings: payloadRow.showEarnings,
            ownerTimeZone: payloadRow.ownerTimeZone,
            now: now
          ))
      } else {
        // Defense: no row means no share access or no data
        previews.append(
          SharingComputedPreview(
            sharerId: sharer.id,
            shift: nil,
            status: nil,
            showEarnings: false
          ))
      }
    }

    let sortedPreviews = SharingComputeCore.sortPreviews(previews)
    let previewMap = Dictionary(
      sortedPreviews.map { ($0.sharerId, $0) }, uniquingKeysWith: { _, last in last })

    let results = activeSharers.map { sharer in
      let preview = previewMap[sharer.id]
      let status = preview?.status.flatMap { FriendShiftStatus(rawValue: $0.rawValue) }

      let showEarnings = preview?.showEarnings ?? sharer.showEarnings
      let previewShift = preview?.shift
      let safeGross = showEarnings ? previewShift?.computed.gross : nil

      return FriendWithShift(
        id: sharer.id,
        displayName: sharer.firstName ?? formattedUsername(sharer.username)
          ?? sharer.email?.components(separatedBy: "@").first
          ?? "Unknown",
        initials: makeInitials(
          from: sharer.firstName ?? sharer.username ?? sharer.email?.components(separatedBy: "@")
            .first
            ?? "?"
        ),
        profilePictureUrl: sharer.profilePictureUrl,
        oauthAvatarUrl: sharer.oauthAvatarUrl,
        showEarnings: showEarnings,
        hidden: sharer.hidden,
        shiftId: previewShift?.id,
        shiftDate: previewShift?.shiftDate,
        startTime: previewShift?.startTime,
        endTime: previewShift?.endTime,
        gross: safeGross,
        status: status,
        ownerTimeZone: preview?.ownerTimeZone
      )
    }

    return sortFriends(results)
  }

  // MARK: - Private API Methods

  fileprivate static func fetchFriendsTabBootstrap<T: Decodable>(
    startDate: String,
    endDate: String
  ) async throws -> T {
    try await callConvex(
      .query, "sharing:friendsBootstrap",
      BootstrapArgs(preview_start_date: startDate, preview_end_date: endDate))
  }

  private struct BootstrapArgs: Encodable, Sendable {
    let preview_start_date: String
    let preview_end_date: String
    let payrollRevision = "2026-11"

    enum CodingKeys: String, CodingKey {
      case preview_start_date, preview_end_date
      case payrollRevision = "payroll_revision"
    }
  }

  private struct FriendsTabBootstrapRPCResponse: Decodable, Sendable {
    let sharers: [BootstrapSharerRow]
    let previewPayloads: [SharingRPCPreviewPayloadRow]
  }

  private struct BootstrapSharerRow: Decodable, Sendable {
    let id: String
    let email: String?
    let phone: String?
    let username: String?
    let firstName: String?
    let profilePictureUrl: String?
    let oauthAvatarUrl: String?
    let sharedAt: String
    let showEarnings: Bool
    let hidden: Bool
    let hasSharedCalendarContent: Bool
    let latestSharedShiftDate: String?
    let hasRecurringSharedShifts: Bool
  }

  fileprivate enum ConvexCall {
    case query
    case mutation
  }

  /// Calls a Convex function as the signed-in user, with a fresh Clerk token. Failures map to
  /// `FriendsAPIError`: no stored session is `.noAccessToken`, a refused token is
  /// `.unauthorized` and a lost connection is `.offline`.
  fileprivate static func callConvex<T: Decodable>(
    _ call: ConvexCall,
    _ path: String,
    _ args: some Encodable & Sendable = ConvexAPI.NoArgs()
  ) async throws -> T {
    try await requireToken()
    do {
      switch call {
      case .query: return try await SharedAuthToken.convex.query(path, args)
      case .mutation: return try await SharedAuthToken.convex.mutation(path, args)
      }
    } catch  where UserFacingError.isCancellation(error) {
      throw error
    } catch let error as FriendsAPIError {
      throw error
    } catch ConvexAPI.Failure.notSignedIn {
      throw FriendsAPIError.unauthorized
    } catch ConvexAPI.Failure.badResponse(let status) {
      throw FriendsAPIError.httpError(statusCode: status)
    } catch let error as ConvexAPI.Failure {
      throw FriendsAPIError.networkError(
        underlying: "\(path) failed: \(error.localizedDescription)")
    } catch let error as DecodingError {
      throw FriendsAPIError.decodingError(underlying: error.localizedDescription)
    } catch {
      throw FriendsAPIError.transportError(error)
    }
  }

  /// Makes sure a valid Clerk token exists, asking Clerk for a new one when the stored one
  /// expired. Clerk tokens last 60 seconds, so this runs before every call.
  fileprivate static func requireToken() async throws {
    if SharedKeychainStorage.getValidAccessToken() != nil { return }
    do {
      guard try await SharedAuthToken.renew() != nil else { throw FriendsAPIError.noAccessToken }
    } catch let error as FriendsAPIError {
      throw error
    } catch {
      if UserFacingError.isCancellation(error) { throw error }
      throw FriendsAPIError.transportError(error)
    }
  }

  // MARK: - Helpers

  private static func sortFriends(_ friends: [FriendWithShift]) -> [FriendWithShift] {
    friends.sorted { lhs, rhs in
      let priorityOrder: [FriendShiftStatus?] = [.active, .upcoming, .past, nil]
      let lhsPriority = priorityOrder.firstIndex(where: { $0 == lhs.status }) ?? 4
      let rhsPriority = priorityOrder.firstIndex(where: { $0 == rhs.status }) ?? 4

      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }

      guard let lhsDateTime = interval(lhs)?.start,
        let rhsDateTime = interval(rhs)?.start
      else {
        return lhs.shiftDate != nil
      }

      if lhs.status == .upcoming {
        return lhsDateTime < rhsDateTime
      }
      if lhs.status == .past {
        return lhsDateTime > rhsDateTime
      }

      return false
    }
  }

  private static func makeInitials(from name: String) -> String {
    let words = name.split(separator: " ")
    if words.count >= 2 {
      let first = words[0].prefix(1).uppercased()
      let second = words[1].prefix(1).uppercased()
      return first + second
    }
    return String(name.prefix(2).uppercased())
  }

  private static func formattedUsername(_ username: String?) -> String? {
    guard let username = username?.trimmingCharacters(in: .whitespacesAndNewlines),
      !username.isEmpty
    else {
      return nil
    }

    return username.hasPrefix("@") ? username : "@\(username)"
  }

  private static func interval(_ friend: FriendWithShift) -> SharedShiftInterval? {
    guard let date = friend.shiftDate, let start = friend.startTime, let end = friend.endTime else {
      return nil
    }
    return SharedShiftInterval(
      date: date, startTime: start, endTime: end, timeZoneIdentifier: friend.ownerTimeZone)
  }

}

#if os(iOS)

  struct ShareRecipient: Identifiable, Equatable {
    let id: String
    let displayName: String
    let avatarURL: URL?
    let statusText: String?
    let canSeeOwnerEarnings: Bool
  }

  struct ShareRecipientThreadSummary: Equatable, Sendable {
    let counterpartUserId: String
    let timestamp: Date
    let hasUnread: Bool
  }

  enum ShareRecipientFeedOrdering {
    static func sortedRecipients(
      _ recipients: [ShareRecipient],
      threads: [ShareRecipientThreadSummary],
      shiftPreviews: [String: SharingComputedPreview]
    ) -> [ShareRecipient] {
      let threadDescriptorsByUserId = threads.reduce(into: [String: ShareRecipientThreadSummary]())
      { result, thread in
        if let existing = result[thread.counterpartUserId] {
          if thread.timestamp > existing.timestamp {
            result[thread.counterpartUserId] = thread
          } else if thread.timestamp == existing.timestamp, thread.hasUnread, !existing.hasUnread {
            result[thread.counterpartUserId] = thread
          }
        } else {
          result[thread.counterpartUserId] = thread
        }
      }

      return recipients.sorted { lhs, rhs in
        let lhsThread = threadDescriptorsByUserId[lhs.id]
        let rhsThread = threadDescriptorsByUserId[rhs.id]

        switch (lhsThread, rhsThread) {
        case (let lhsThread?, let rhsThread?):
          if lhsThread.timestamp != rhsThread.timestamp {
            return lhsThread.timestamp > rhsThread.timestamp
          }
          if lhsThread.hasUnread != rhsThread.hasUnread {
            return lhsThread.hasUnread
          }

        case (.some, .none):
          return true

        case (.none, .some):
          return false

        case (.none, .none):
          break
        }

        return compareShiftFallback(
          lhs: lhs,
          rhs: rhs,
          lhsPreview: shiftPreviews[lhs.id],
          rhsPreview: shiftPreviews[rhs.id]
        )
      }
    }

    private static func compareShiftFallback(
      lhs: ShareRecipient,
      rhs: ShareRecipient,
      lhsPreview: SharingComputedPreview?,
      rhsPreview: SharingComputedPreview?
    ) -> Bool {
      let lhsPriority = shiftStatusPriority(lhsPreview?.status)
      let rhsPriority = shiftStatusPriority(rhsPreview?.status)

      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }

      guard
        let lhsDateTime = previewStart(lhsPreview),
        let rhsDateTime = previewStart(rhsPreview)
      else {
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }

      switch lhsPreview?.status {
      case .upcoming:
        if lhsDateTime != rhsDateTime {
          return lhsDateTime < rhsDateTime
        }

      case .past:
        if lhsDateTime != rhsDateTime {
          return lhsDateTime > rhsDateTime
        }

      default:
        break
      }

      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func shiftStatusPriority(_ status: SharingPreviewStatus?) -> Int {
      switch status {
      case .active: return 0
      case .upcoming: return 1
      case .past: return 2
      case .none: return 3
      }
    }

    private static func previewStart(_ preview: SharingComputedPreview?) -> Date? {
      guard let shift = preview?.shift else { return nil }
      return SharedShiftInterval(
        date: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime,
        timeZoneIdentifier: preview?.ownerTimeZone
      )?.start
    }

  }

  enum SiriMessageRecipientMatcher {
    static func matches(
      for spokenName: String?,
      in recipients: [ShareRecipient]
    ) -> [ShareRecipient] {
      let query = normalizedSearchText(spokenName)
      guard !query.isEmpty else { return [] }

      let scoredRecipients = recipients.compactMap {
        recipient -> (recipient: ShareRecipient, score: Int)? in
        let fields = searchableFields(for: recipient)
        let recipientScore = fields.reduce(0) { partial, field in
          max(partial, Self.score(query: query, candidate: normalizedSearchText(field)))
        }
        guard recipientScore > 0 else { return nil }
        return (recipient, recipientScore)
      }

      let bestScore = scoredRecipients.map { $0.score }.max() ?? 0
      return
        scoredRecipients
        .filter { $0.score == bestScore }
        .sorted {
          $0.recipient.displayName.localizedCaseInsensitiveCompare($1.recipient.displayName)
            == .orderedAscending
        }
        .map { $0.recipient }
    }

    private static func searchableFields(for recipient: ShareRecipient) -> [String] {
      var fields = [recipient.displayName]

      if let statusText = recipient.statusText {
        fields.append(statusText)
      }

      return fields
    }

    private static func score(query: String, candidate: String) -> Int {
      guard !candidate.isEmpty else { return 0 }
      if candidate == query { return 100 }
      if candidate.hasPrefix(query) { return 90 }
      if candidate.split(separator: " ").contains(where: { $0 == query }) { return 80 }
      if candidate.contains(query) { return 70 }

      let queryTokens = Set(query.split(separator: " "))
      let candidateTokens = Set(candidate.split(separator: " "))
      guard !queryTokens.isEmpty, queryTokens.isSubset(of: candidateTokens) else {
        return 0
      }

      return 60
    }

    private static func normalizedSearchText(_ value: String?) -> String {
      guard let value else { return "" }

      let folded =
        value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: "@", with: " ")

      let scalars = folded.unicodeScalars.map { scalar -> Character in
        CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
      }

      return String(scalars)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }
  }

  enum ShareExtensionMessagingClient {
    private static let maxUploadBytes = 1_500_000

    static func fetchRecipients() async throws -> [ShareRecipient] {
      let now = Date()
      let startDate = SharingComputeCore.isoDateString(
        Calendar.gregorianCurrent.date(byAdding: .day, value: -30, to: now) ?? now)
      let endDate = SharingComputeCore.isoDateString(
        Calendar.gregorianCurrent.date(byAdding: .day, value: 30, to: now) ?? now)

      async let friendsTask: ShareFriendsResponse = FriendsAPIClient.fetchFriendsTabBootstrap(
        startDate: startDate,
        endDate: endDate
      )
      async let threadsTask = fetchThreadSummaries()

      let response = try await friendsTask
      let threads = (try? await threadsTask) ?? []
      let recipients = response.friends
        .filter(\.isMessageable)
        .map(\.shareRecipient)
      let shiftPreviews = makeShiftPreviews(
        from: response.previewPayloads,
        startDate: startDate,
        endDate: endDate,
        now: now
      )

      return ShareRecipientFeedOrdering.sortedRecipients(
        recipients,
        threads: threads,
        shiftPreviews: shiftPreviews
      )
    }

    static func sendTextMessage(
      to recipientUserId: String,
      message: String
    ) async throws {
      try await FriendsAPIClient.requireToken()

      let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedMessage.isEmpty else {
        throw FriendsAPIError.networkError(underlying: "Message content is empty")
      }

      let thread = try await getOrCreateDirectThread(otherUserId: recipientUserId)
      try await send(
        SendArgs(
          thread_id: thread.threadId,
          client_id: UUID().uuidString.lowercased(),
          body: trimmedMessage
        ))
    }

    static func sendSharedImage(
      to recipientUserId: String,
      message: String,
      imageData: Data
    ) async throws {
      try await FriendsAPIClient.requireToken()

      let thread = try await getOrCreateDirectThread(otherUserId: recipientUserId)
      let preparedImage = try prepareImage(from: imageData)
      let storageId = try await uploadImageAttachment(preparedImage, threadId: thread.threadId)

      let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
      try await send(
        SendArgs(
          thread_id: thread.threadId,
          client_id: UUID().uuidString.lowercased(),
          body: trimmedMessage.isEmpty ? nil : trimmedMessage,
          attachments: [
            SendAttachment(
              attachment_id: preparedImage.id,
              storage_id: storageId,
              mime_type: preparedImage.mimeType,
              byte_size: preparedImage.data.count,
              width: preparedImage.width,
              height: preparedImage.height
            )
          ]
        ))
    }

    private static func send(_ args: SendArgs) async throws {
      let _: ShareMessageAck = try await FriendsAPIClient.callConvex(
        .mutation, "messages:send", args)
    }

    private static func getOrCreateDirectThread(otherUserId: String) async throws -> ShareThreadRow
    {
      try await FriendsAPIClient.callConvex(
        .mutation, "threads:getOrCreateDirect", DirectThreadArgs(other_user_id: otherUserId))
    }

    private static func fetchThreadSummaries() async throws -> [ShareRecipientThreadSummary] {
      let inbox: ShareInboxResponse = try await FriendsAPIClient.callConvex(
        .query, "threads:inbox", InboxArgs(limit: 100))
      return inbox.threads.compactMap(\.shareRecipientThreadSummary)
    }

    private static func makeShiftPreviews(
      from payloadRows: [SharingRPCPreviewPayloadRow],
      startDate: String,
      endDate: String,
      now: Date
    ) -> [String: SharingComputedPreview] {
      Dictionary(
        payloadRows.map { row in
          let mode: SharingRPCMode = row.showEarnings ? .visible : .hidden
          let shifts = SharingComputeCore.computeShiftsInRange(
            payload: row.payloadInput,
            startDate: startDate,
            endDate: endDate,
            mode: mode
          )
          let preview = SharingComputeCore.selectPreview(
            sharerId: row.sharerId,
            shifts: shifts,
            showEarnings: row.showEarnings,
            ownerTimeZone: row.ownerTimeZone,
            now: now
          )
          return (row.sharerId, preview)
        },
        uniquingKeysWith: { _, last in last }
      )
    }

    /// Uploads the image to the deployment's `POST /attachments` and returns the storage id
    /// that `messages:send` takes for the attachment.
    private static func uploadImageAttachment(
      _ image: PreparedSharedImage,
      threadId: String
    ) async throws -> String {
      guard let accessToken = await SharedAuthToken.current() else {
        throw FriendsAPIError.noAccessToken
      }

      var components = URLComponents(
        url: ConvexAPI.configuredSiteURL.appending(path: "attachments"),
        resolvingAgainstBaseURL: false)
      components?.queryItems = [URLQueryItem(name: "thread_id", value: threadId)]
      guard let uploadURL = components?.url else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorInvalidStorageBaseUrl))
      }

      var request = URLRequest(url: uploadURL)
      request.httpMethod = "POST"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue(image.mimeType, forHTTPHeaderField: "Content-Type")

      do {
        let (data, response) = try await FriendsAPIClient.urlSession.upload(
          for: request, from: image.data)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw FriendsAPIError.networkError(
            underlying: String(localized: .shareErrorInvalidStorageResponse))
        }

        if httpResponse.statusCode == 401 { throw FriendsAPIError.unauthorized }
        guard (200...299).contains(httpResponse.statusCode) else {
          throw FriendsAPIError.httpError(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(UploadReply.self, from: data).storageId
      } catch  where UserFacingError.isCancellation(error) {
        throw error
      } catch let error as FriendsAPIError {
        throw error
      } catch let error as DecodingError {
        throw FriendsAPIError.decodingError(underlying: error.localizedDescription)
      } catch {
        throw FriendsAPIError.transportError(error)
      }
    }

    private static func prepareImage(from data: Data) throws -> PreparedSharedImage {
      guard let originalImage = UIImage(data: data) else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorUnableToReadImage))
      }

      let resizedImage = resizeImageIfNeeded(originalImage)
      let compressedData = try makeJPEGData(from: resizedImage)

      return PreparedSharedImage(
        id: UUID().uuidString.lowercased(),
        data: compressedData,
        mimeType: "image/jpeg",
        fileExtension: "jpg",
        width: Int(resizedImage.size.width.rounded()),
        height: Int(resizedImage.size.height.rounded())
      )
    }

    private static func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
      let maxDimension: CGFloat = 1_568
      let maxSide = max(image.size.width, image.size.height)
      guard maxSide > maxDimension else { return image }

      let scale = maxDimension / maxSide
      let targetSize = CGSize(
        width: image.size.width * scale,
        height: image.size.height * scale
      )

      let format = UIGraphicsImageRendererFormat.default()
      format.scale = 1
      format.opaque = false

      let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
      return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
      }
    }

    private static func makeJPEGData(from image: UIImage) throws -> Data {
      let qualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52]

      for quality in qualities {
        if let data = image.jpegData(compressionQuality: quality), data.count <= maxUploadBytes {
          return data
        }
      }

      guard let fallbackData = image.jpegData(compressionQuality: 0.45) else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorUnableToEncodeImage))
      }

      guard fallbackData.count <= maxUploadBytes else {
        throw FriendsAPIError.networkError(
          underlying: String(localized: .shareErrorImageTooLarge))
      }

      return fallbackData
    }

    private struct PreparedSharedImage {
      let id: String
      let data: Data
      let mimeType: String
      let fileExtension: String
      let width: Int?
      let height: Int?
    }

    private struct ShareThreadRow: Decodable {
      let threadId: String

      private enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
      }
    }

    private struct ShareMessageAck: Decodable {
      let id: String
    }

    private struct UploadReply: Decodable {
      let storageId: String
    }

    private struct ShareInboxResponse: Decodable {
      let threads: [ShareThreadSummaryRow]
    }

    private struct InboxArgs: Encodable, Sendable {
      let limit: Int
    }

    private struct DirectThreadArgs: Encodable, Sendable {
      let other_user_id: String
    }

    private struct SendArgs: Encodable, Sendable {
      let thread_id: String
      let client_id: String
      var body: String?
      var attachments: [SendAttachment]?
    }

    private struct SendAttachment: Encodable, Sendable {
      let attachment_id: String
      let storage_id: String
      let mime_type: String
      let byte_size: Int
      let width: Int?
      let height: Int?
    }

    private struct ShareFriendsResponse: Decodable {
      let friends: [ShareFriendRow]
      let previewPayloads: [SharingRPCPreviewPayloadRow]

      private enum CodingKeys: String, CodingKey {
        case friends
        case previewPayloads
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        friends = try container.decodeIfPresent([ShareFriendRow].self, forKey: .friends) ?? []
        previewPayloads =
          try container.decodeIfPresent(
            [SharingRPCPreviewPayloadRow].self, forKey: .previewPayloads)
          ?? []
      }
    }

    private struct ShareThreadSummaryRow: Decodable {
      let kind: String
      let counterpartUserId: String?
      let lastMessageAt: String?
      let unreadCount: Int
      let createdAt: String

      var shareRecipientThreadSummary: ShareRecipientThreadSummary? {
        guard kind == "direct",
          let counterpartUserId,
          let timestamp = Self.parseTimestamp(lastMessageAt) ?? Self.parseTimestamp(createdAt)
        else {
          return nil
        }

        return ShareRecipientThreadSummary(
          counterpartUserId: counterpartUserId,
          timestamp: timestamp,
          hasUnread: unreadCount > 0
        )
      }

      private enum CodingKeys: String, CodingKey {
        case kind
        case counterpartUserId = "counterpart_user_id"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
        case createdAt = "created_at"
      }

      private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601Timestamp.date(from: value)
      }
    }

    private struct ShareFriendRow: Decodable {
      let id: String
      let email: String?
      let phone: String?
      let firstName: String?
      let profilePictureUrl: String?
      let oauthAvatarUrl: String?
      let sharesWithMe: ShareDirection?
      let iShareWith: ShareDirection?

      var isMessageable: Bool {
        sharesWithMe != nil || iShareWith != nil
      }

      var shareRecipient: ShareRecipient {
        ShareRecipient(
          id: id,
          displayName: displayName,
          avatarURL: effectiveAvatarURL,
          statusText: contactInfo,
          canSeeOwnerEarnings: iShareWith?.showEarningsToThem ?? false
        )
      }

      private var displayName: String {
        if let firstName, !firstName.isEmpty {
          return firstName
        }
        if let email, !email.isEmpty {
          return email.components(separatedBy: "@").first ?? email
        }
        if let phone, !phone.isEmpty {
          return phone
        }
        return String(localized: .shareRecipientUnknown)
      }

      private var contactInfo: String? {
        if let firstName, !firstName.isEmpty {
          if let email, !email.isEmpty {
            return email
          }
          if let phone, !phone.isEmpty {
            return phone
          }
        }

        if let email, !email.isEmpty, let phone, !phone.isEmpty {
          return phone
        }

        return nil
      }

      private var effectiveAvatarURL: URL? {
        guard let urlString = profilePictureUrl ?? oauthAvatarUrl, !urlString.isEmpty else {
          return nil
        }

        return URL(string: urlString)
      }
    }

    private struct ShareDirection: Decodable {
      let showEarningsToThem: Bool?

      private enum CodingKeys: String, CodingKey {
        case showEarningsToThem
      }
    }
  }

#endif
// swiftlint:enable file_length function_body_length cyclomatic_complexity
