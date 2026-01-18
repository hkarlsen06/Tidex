import Foundation

// MARK: - Sharer Data

/// A user who has shared their shifts with the current user
struct SharedUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String?
    let phone: String?
    let firstName: String?
    let profilePictureUrl: String?
    let oauthAvatarUrl: String?
    let sharedAt: String
    /// Whether this user allows the viewer to see earnings
    let showEarnings: Bool
    /// Whether the viewer has blocked this sharer
    let blocked: Bool

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
}
