import Foundation

// MARK: - Sharer Data

/// A user who has shared their shifts with the current user
struct SharedUser: Codable, Identifiable, Equatable, Hashable {
  let id: String
  let email: String?
  let phone: String?
  let firstName: String?
  let profilePictureUrl: String?
  let oauthAvatarUrl: String?
  let sharedAt: String
  /// Whether this user allows the viewer to see earnings
  let showEarnings: Bool
  /// Whether the viewer has hidden this sharer from the main list
  let hidden: Bool
  /// Whether this sharer has any shared shift history or recurring shifts at all.
  let hasSharedCalendarContent: Bool

  private enum CodingKeys: String, CodingKey {
    case id
    case email
    case phone
    case firstName
    case profilePictureUrl
    case oauthAvatarUrl
    case sharedAt
    case showEarnings
    case hidden
    case hasSharedCalendarContent
    case blocked
  }

  init(
    id: String,
    email: String?,
    phone: String?,
    firstName: String?,
    profilePictureUrl: String?,
    oauthAvatarUrl: String?,
    sharedAt: String,
    showEarnings: Bool,
    hidden: Bool,
    hasSharedCalendarContent: Bool = false
  ) {
    self.id = id
    self.email = email
    self.phone = phone
    self.firstName = firstName
    self.profilePictureUrl = profilePictureUrl
    self.oauthAvatarUrl = oauthAvatarUrl
    self.sharedAt = sharedAt
    self.showEarnings = showEarnings
    self.hidden = hidden
    self.hasSharedCalendarContent = hasSharedCalendarContent
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    phone = try container.decodeIfPresent(String.self, forKey: .phone)
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
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(email, forKey: .email)
    try container.encodeIfPresent(phone, forKey: .phone)
    try container.encodeIfPresent(firstName, forKey: .firstName)
    try container.encodeIfPresent(profilePictureUrl, forKey: .profilePictureUrl)
    try container.encodeIfPresent(oauthAvatarUrl, forKey: .oauthAvatarUrl)
    try container.encode(sharedAt, forKey: .sharedAt)
    try container.encode(showEarnings, forKey: .showEarnings)
    try container.encode(hidden, forKey: .hidden)
    try container.encode(hasSharedCalendarContent, forKey: .hasSharedCalendarContent)
  }

  /// Display name for the sharer (firstName > email > phone > "Unknown")
  var displayName: String {
    if let firstName = firstName, !firstName.isEmpty {
      return firstName
    }
    if let email = email, !email.isEmpty {
      return email.components(separatedBy: "@").first ?? email
    }
    if let phone = phone, !phone.isEmpty {
      return phone
    }
    return "Unknown"
  }

  /// First name only (first word of displayName), for compact toolbar display
  var firstNameOnly: String {
    let name = displayName
    return name.components(separatedBy: " ").first ?? name
  }

  /// Best available avatar URL
  var avatarUrl: String? {
    profilePictureUrl ?? oauthAvatarUrl
  }

  /// Initials for avatar placeholder
  var initials: String {
    let name = firstName ?? email ?? phone ?? "?"
    let components = name.components(separatedBy: " ")
    if components.count >= 2 {
      let first = components[0].prefix(1)
      let last = components[1].prefix(1)
      return "\(first)\(last)".uppercased()
    }
    return String(name.prefix(2)).uppercased()
  }

  /// Contact info to display (email or phone, preferring email)
  /// Returns nil if the contact info would duplicate the display name
  var contactInfo: String? {
    // If we have email and it's not already used as displayName
    if let email = email, !email.isEmpty {
      if let firstName = firstName, !firstName.isEmpty {
        // firstName is used as display name, so show email
        return email
      }
      // Email is used as display name, don't duplicate
      return nil
    }
    // If we have phone and it's not already used as displayName
    if let phone = phone, !phone.isEmpty {
      if let firstName = firstName, !firstName.isEmpty {
        // firstName is used as display name, so show phone
        return phone
      }
      // Phone is used as display name, don't duplicate
      return nil
    }
    return nil
  }
}
