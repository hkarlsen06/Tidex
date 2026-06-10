import Foundation

// MARK: - Sharer Data

/// A user who has shared their shifts with the current user
internal struct SharedUser: Codable, Identifiable, Equatable, Hashable {
  private enum CodingKeys: String, CodingKey {
    case id
    case email
    case phone
    case username
    case firstName
    case profilePictureUrl
    case oauthAvatarUrl
    case sharedAt
    case showEarnings
    case hidden
    case hasSharedCalendarContent
    case latestSharedShiftDate
    case hasRecurringSharedShifts
    case blocked
  }

  private static let minimumInitialsComponentCount: Int = 2
  private static let initialsLength: Int = 2

  internal let id: String
  internal let email: String?
  internal let phone: String?
  internal let username: String?
  internal let firstName: String?
  internal let profilePictureUrl: String?
  internal let oauthAvatarUrl: String?
  internal let sharedAt: String
  /// Whether this user allows the viewer to see earnings
  internal let showEarnings: Bool
  /// Whether the viewer has hidden this sharer from the main list
  internal let hidden: Bool
  /// Whether this sharer has any shared shift history or recurring shifts at all.
  internal let hasSharedCalendarContent: Bool
  /// Most recent shared shift date, when one exists.
  internal let latestSharedShiftDate: String?
  /// Whether this sharer has recurring shifts that can generate future months.
  internal let hasRecurringSharedShifts: Bool

  internal init(
    id: String,
    email: String?,
    phone: String?,
    firstName: String?,
    profilePictureUrl: String?,
    oauthAvatarUrl: String?,
    sharedAt: String,
    showEarnings: Bool,
    hidden: Bool,
    hasSharedCalendarContent: Bool = false,
    latestSharedShiftDate: String? = nil,
    hasRecurringSharedShifts: Bool = false,
    username: String? = nil
  ) {
    self.id = id
    self.email = email
    self.phone = phone
    self.username = username
    self.firstName = firstName
    self.profilePictureUrl = profilePictureUrl
    self.oauthAvatarUrl = oauthAvatarUrl
    self.sharedAt = sharedAt
    self.showEarnings = showEarnings
    self.hidden = hidden
    self.hasSharedCalendarContent = hasSharedCalendarContent
    self.latestSharedShiftDate = latestSharedShiftDate
    self.hasRecurringSharedShifts = hasRecurringSharedShifts
  }

  internal init(from decoder: Decoder) throws {
    let container: KeyedDecodingContainer<CodingKeys> =
      try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    phone = try container.decodeIfPresent(String.self, forKey: .phone)
    username = try container.decodeIfPresent(String.self, forKey: .username)
    firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
    profilePictureUrl = try container.decodeIfPresent(String.self, forKey: .profilePictureUrl)
    oauthAvatarUrl = try container.decodeIfPresent(String.self, forKey: .oauthAvatarUrl)
    sharedAt = try container.decode(String.self, forKey: .sharedAt)
    showEarnings = try container.decode(Bool.self, forKey: .showEarnings)
    hidden =
      try container.decodeIfPresent(Bool.self, forKey: .hidden)
      ?? container.decodeIfPresent(Bool.self, forKey: .blocked)
      ?? false
    hasSharedCalendarContent =
      try container.decodeIfPresent(Bool.self, forKey: .hasSharedCalendarContent)
      ?? false
    latestSharedShiftDate = try container.decodeIfPresent(
      String.self,
      forKey: .latestSharedShiftDate
    )
    hasRecurringSharedShifts =
      try container.decodeIfPresent(Bool.self, forKey: .hasRecurringSharedShifts)
      ?? false
  }

  internal func encode(to encoder: Encoder) throws {
    var container: KeyedEncodingContainer<CodingKeys> =
      encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(email, forKey: .email)
    try container.encodeIfPresent(phone, forKey: .phone)
    try container.encodeIfPresent(username, forKey: .username)
    try container.encodeIfPresent(firstName, forKey: .firstName)
    try container.encodeIfPresent(profilePictureUrl, forKey: .profilePictureUrl)
    try container.encodeIfPresent(oauthAvatarUrl, forKey: .oauthAvatarUrl)
    try container.encode(sharedAt, forKey: .sharedAt)
    try container.encode(showEarnings, forKey: .showEarnings)
    try container.encode(hidden, forKey: .hidden)
    try container.encode(hasSharedCalendarContent, forKey: .hasSharedCalendarContent)
    try container.encodeIfPresent(latestSharedShiftDate, forKey: .latestSharedShiftDate)
    try container.encode(hasRecurringSharedShifts, forKey: .hasRecurringSharedShifts)
  }

  /// Display name for the sharer (firstName > username > email > phone > "Unknown")
  internal var displayName: String {
    if let firstName, !firstName.isEmpty {
      return firstName
    }
    if let username = formattedUsername {
      return username
    }
    if let email, !email.isEmpty {
      return email.components(separatedBy: "@").first ?? email
    }
    if let phone, !phone.isEmpty {
      return phone
    }
    return "Unknown"
  }

  /// First name only (first word of displayName), for compact toolbar display
  internal var firstNameOnly: String {
    let name: String = displayName
    return name.components(separatedBy: " ").first ?? name
  }

  /// Best available avatar URL
  internal var avatarUrl: String? {
    profilePictureUrl ?? oauthAvatarUrl
  }

  /// Initials for avatar placeholder
  internal var initials: String {
    let name: String = firstName ?? username ?? email ?? phone ?? "?"
    let components: [String] = name.components(separatedBy: " ")
    if components.count >= Self.minimumInitialsComponentCount {
      let first: Substring = components[0].prefix(1)
      let last: Substring = components[1].prefix(1)
      return "\(first)\(last)".uppercased()
    }
    return String(name.prefix(Self.initialsLength)).uppercased()
  }

  /// Contact info to display (username, email, or phone)
  /// Returns nil if the contact info would duplicate the display name
  internal var contactInfo: String? {
    if let username = formattedUsername {
      return firstName?.isEmpty == false ? username : nil
    }

    // If we have email and it's not already used as displayName
    if let email, !email.isEmpty {
      if let firstName, !firstName.isEmpty {
        // firstName is used as display name, so show email
        return email
      }
      // Email is used as display name, don't duplicate
      return nil
    }
    // If we have phone and it's not already used as displayName
    if let phone, !phone.isEmpty {
      if let firstName, !firstName.isEmpty {
        // firstName is used as display name, so show phone
        return phone
      }
      // Phone is used as display name, don't duplicate
      return nil
    }
    return nil
  }

  internal var formattedUsername: String? {
    guard let username = username?.trimmingCharacters(in: .whitespacesAndNewlines),
      !username.isEmpty
    else {
      return nil
    }

    return username.hasPrefix("@") ? username : "@\(username)"
  }
}
