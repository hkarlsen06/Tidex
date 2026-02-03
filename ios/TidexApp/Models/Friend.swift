import Foundation

// MARK: - Notification Frequency

/// How often the user wants notifications from a sharer
enum NotificationFrequency: String, Codable, Equatable {
    case instant
    case summary
    case muted
}

// MARK: - Friend (Bidirectional Share Relationship)

/// A unified friend entry combining both directions of sharing:
/// - sharesWithMe: They share their shifts with me (I can see their shifts)
/// - iShareWith: I share my shifts with them (they can see my shifts)
struct Friend: Codable, Identifiable, Equatable {
    let id: String
    let email: String?
    let phone: String?
    let firstName: String?
    let profilePictureUrl: String?
    let oauthAvatarUrl: String?

    /// If they share their shifts with me
    let sharesWithMe: SharesWithMe?

    /// If I share my shifts with them
    let iShareWith: IShareWith?

    // MARK: - Nested Types

    struct SharesWithMe: Codable, Equatable {
        /// Whether I've hidden them from my view
        let blocked: Bool
        /// Whether they allow me to see their earnings
        let showEarningsToMe: Bool
        /// When they started sharing with me (ISO date string)
        let sharedAt: String
        /// How often I want notifications from this sharer
        let notificationFrequency: NotificationFrequency

        /// Whether notifications from this sharer are muted
        var isMuted: Bool {
            notificationFrequency == .muted
        }

        /// Create a copy with updated blocked status
        func with(blocked: Bool) -> SharesWithMe {
            SharesWithMe(blocked: blocked, showEarningsToMe: showEarningsToMe, sharedAt: sharedAt, notificationFrequency: notificationFrequency)
        }

        /// Create a copy with updated notification frequency
        func with(notificationFrequency: NotificationFrequency) -> SharesWithMe {
            SharesWithMe(blocked: blocked, showEarningsToMe: showEarningsToMe, sharedAt: sharedAt, notificationFrequency: notificationFrequency)
        }
    }

    struct IShareWith: Codable, Equatable {
        /// Whether I allow them to see my earnings
        let showEarningsToThem: Bool
        /// When I started sharing with them (ISO date string)
        let sharedAt: String

        /// Create a copy with updated earnings visibility
        func with(showEarningsToThem: Bool) -> IShareWith {
            IShareWith(showEarningsToThem: showEarningsToThem, sharedAt: sharedAt)
        }
    }

    // MARK: - Computed Properties

    /// Display name for the friend (firstName > email username > phone > "Unknown")
    var displayName: String {
        if let firstName = firstName, !firstName.isEmpty {
            return firstName
        }
        if let email = email, !email.isEmpty {
            return email.components(separatedBy: "@").first ?? email
        }
        if let phone = phone, !phone.isEmpty {
            return formatPhoneNumber(phone)
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

    /// Contact info to display (email or phone), avoiding duplication with display name
    var contactInfo: String? {
        // If we have firstName, show email or phone as secondary info
        if let firstName = firstName, !firstName.isEmpty {
            if let email = email, !email.isEmpty {
                return email
            }
            if let phone = phone, !phone.isEmpty {
                return formatPhoneNumber(phone)
            }
        }
        // If email is display name, show phone if available
        if let email = email, !email.isEmpty {
            if let phone = phone, !phone.isEmpty {
                return formatPhoneNumber(phone)
            }
        }
        return nil
    }

    // MARK: - Relationship Status

    /// Both users share with each other
    var isMutual: Bool {
        sharesWithMe != nil && iShareWith != nil
    }

    /// Only I share my shifts with them (they can see mine, but I can't see theirs)
    var isOutgoingOnly: Bool {
        iShareWith != nil && sharesWithMe == nil
    }

    /// Only they share with me (I can see theirs, but they can't see mine)
    var isIncomingOnly: Bool {
        sharesWithMe != nil && iShareWith == nil
    }

    // MARK: - Copy-With Methods (for optimistic updates)

    /// Create a copy with updated sharesWithMe
    func with(sharesWithMe: SharesWithMe?) -> Friend {
        Friend(
            id: id,
            email: email,
            phone: phone,
            firstName: firstName,
            profilePictureUrl: profilePictureUrl,
            oauthAvatarUrl: oauthAvatarUrl,
            sharesWithMe: sharesWithMe,
            iShareWith: iShareWith
        )
    }

    /// Create a copy with updated iShareWith
    func with(iShareWith: IShareWith?) -> Friend {
        Friend(
            id: id,
            email: email,
            phone: phone,
            firstName: firstName,
            profilePictureUrl: profilePictureUrl,
            oauthAvatarUrl: oauthAvatarUrl,
            sharesWithMe: sharesWithMe,
            iShareWith: iShareWith
        )
    }

    // MARK: - Helpers

    /// Format phone number for display (Norwegian format)
    private func formatPhoneNumber(_ phone: String) -> String {
        let digits = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)

        // Remove country code if present
        let localNumber: String
        if digits.hasPrefix("47") && digits.count == 10 {
            localNumber = String(digits.dropFirst(2))
        } else {
            localNumber = digits
        }

        // Format as XXX XX XXX
        if localNumber.count == 8 {
            let part1 = localNumber.prefix(3)
            let part2 = localNumber.dropFirst(3).prefix(2)
            let part3 = localNumber.dropFirst(5)
            return "\(part1) \(part2) \(part3)"
        }

        return phone
    }
}

// MARK: - Share Capacity

/// User's share capacity based on subscription tier
struct ShareCapacity: Codable, Equatable {
    let canAdd: Bool
    let currentCount: Int
    let limit: Int
}

// MARK: - API Response Types

/// Response from GET /api/sharing/friends
struct FriendsAPIResponse: Codable {
    let friends: [Friend]
    let capacity: ShareCapacity
}

/// Response from POST /api/sharing/manage
struct ManageActionResponse: Codable {
    let success: Bool
    let error: String?
}
