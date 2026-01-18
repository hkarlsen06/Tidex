import Foundation
import SwiftData

// MARK: - Local Shared Shift

/// SwiftData model for locally cached shared shifts
/// These are shifts from users who have shared with the current user
/// Server is source of truth - local data is replaced on each fetch
@Model
final class LocalSharedShift {
    // MARK: - Primary Key

    /// Unique identifier (composite of shiftId + viewerId for uniqueness)
    @Attribute(.unique)
    var compositeKey: String

    // MARK: - Shift Identity

    /// Original shift ID from the owner
    var shiftId: String

    /// User who owns/shared the shift
    var ownerId: String

    /// User viewing the shared shift (current user)
    var viewerId: String

    // MARK: - Shift Data

    /// Date of the shift
    var shiftDate: Date

    /// Start time in HH:mm format
    var startTime: String

    /// End time in HH:mm format
    var endTime: String

    // MARK: - Computed Payroll (from API)

    /// Duration in hours (raw, before breaks)
    var durationHours: Double

    /// Paid hours (after break deduction)
    var paidHours: Double

    /// Base pay in NOK
    var basePay: Double

    /// Supplement pay in NOK
    var supplementPay: Double

    /// Gross pay in NOK
    var gross: Double

    // MARK: - Tax Settings

    /// Whether tax is enabled for this shift
    var taxEnabled: Bool

    /// Tax percentage
    var taxPercentage: Double

    // MARK: - Sharing Settings

    /// Whether earnings are visible (from share relationship)
    var showEarnings: Bool

    // MARK: - Recurring Shift Metadata

    /// Links to recurring_shifts if this is a virtual shift
    var recurringId: String?

    /// Which weekday anchor (0-6) generated this virtual shift
    var recurringAnchorWeekday: Int?

    // MARK: - Cache Metadata

    /// When this record was cached
    var cachedAt: Date

    /// Year of the shift (for efficient querying)
    var year: Int

    /// Month of the shift (1-12, for efficient querying)
    var month: Int

    // MARK: - Computed Properties

    /// Whether this is a virtual (recurring) shift
    var isVirtual: Bool {
        recurringId != nil
    }

    /// Net pay after tax
    var netPay: Double {
        guard taxEnabled else { return gross }
        return gross * (1 - taxPercentage / 100)
    }

    /// Tax amount
    var taxAmount: Double {
        guard taxEnabled else { return 0 }
        return gross * taxPercentage / 100
    }

    /// Shift date as ISO string (YYYY-MM-DD)
    var shiftDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Date.localTimeZone
        return formatter.string(from: shiftDate)
    }

    // MARK: - Initialization

    init(
        shiftId: String,
        ownerId: String,
        viewerId: String,
        shiftDate: Date,
        startTime: String,
        endTime: String,
        durationHours: Double,
        paidHours: Double,
        basePay: Double,
        supplementPay: Double,
        gross: Double,
        taxEnabled: Bool,
        taxPercentage: Double,
        showEarnings: Bool,
        recurringId: String? = nil,
        recurringAnchorWeekday: Int? = nil,
        cachedAt: Date = Date()
    ) {
        self.compositeKey = "\(viewerId):\(shiftId)"
        self.shiftId = shiftId
        self.ownerId = ownerId
        self.viewerId = viewerId
        self.shiftDate = shiftDate
        self.startTime = startTime
        self.endTime = endTime
        self.durationHours = durationHours
        self.paidHours = paidHours
        self.basePay = basePay
        self.supplementPay = supplementPay
        self.gross = gross
        self.taxEnabled = taxEnabled
        self.taxPercentage = taxPercentage
        self.showEarnings = showEarnings
        self.recurringId = recurringId
        self.recurringAnchorWeekday = recurringAnchorWeekday
        self.cachedAt = cachedAt

        // Extract year/month for efficient querying
        let calendar = Calendar(identifier: .gregorian)
        self.year = calendar.component(.year, from: shiftDate)
        self.month = calendar.component(.month, from: shiftDate)
    }

    /// Create from API response data
    static func from(
        apiShift: SharedShiftData,
        ownerId: String,
        viewerId: String,
        showEarnings: Bool
    ) -> LocalSharedShift {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = Date.localTimeZone

        let shiftDate = dateFormatter.date(from: apiShift.shift_date) ?? Date()

        return LocalSharedShift(
            shiftId: apiShift.id,
            ownerId: ownerId,
            viewerId: viewerId,
            shiftDate: shiftDate,
            startTime: apiShift.start_time,
            endTime: apiShift.end_time,
            durationHours: apiShift.computed.durationHours,
            paidHours: apiShift.computed.paidHours,
            basePay: apiShift.computed.basePay,
            supplementPay: apiShift.computed.supplementPay,
            gross: apiShift.computed.gross,
            taxEnabled: apiShift.tax_enabled ?? false,
            taxPercentage: apiShift.tax_percentage ?? 0,
            showEarnings: showEarnings,
            recurringId: apiShift.recurring_id,
            recurringAnchorWeekday: apiShift.recurring_anchor_weekday
        )
    }
}

// MARK: - Conversion to ShiftWithComputations

extension LocalSharedShift {
    /// Convert to ShiftWithComputations for use with existing UI components
    func toShiftWithComputations() -> ShiftWithComputations {
        let shiftRow = ShiftRow(
            id: shiftId,
            user_id: ownerId,
            shift_date: shiftDateString,
            start_time: startTime,
            end_time: endTime,
            custom_supplements: nil,
            created_at: nil,
            recurring_id: recurringId,
            recurring_anchor_weekday: recurringAnchorWeekday
        )

        let shiftComputed = ShiftComputed(
            id: shiftId,
            durationHours: durationHours,
            paidHours: paidHours,
            basePay: basePay,
            supplementPay: supplementPay,
            gross: gross,
            wagePeriods: [],
            originalWagePeriods: [],
            breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
        )

        return ShiftWithComputations(
            shift: shiftRow,
            computed: shiftComputed,
            taxEnabled: taxEnabled,
            taxPercentage: taxPercentage
        )
    }
}

// MARK: - Local Sharer Cache

/// SwiftData model for caching sharer information
/// Allows offline display of sharers list
@Model
final class LocalSharer {
    // MARK: - Primary Key

    /// Composite key: viewerId:sharerId
    @Attribute(.unique)
    var compositeKey: String

    // MARK: - Identity

    /// The sharer's user ID
    var sharerId: String

    /// The viewer's user ID (current user)
    var viewerId: String

    // MARK: - Profile Data

    var email: String?
    var phone: String?
    var firstName: String?
    var profilePictureUrl: String?
    var oauthAvatarUrl: String?

    // MARK: - Share Settings

    /// When the share was created
    var sharedAt: String

    /// Whether the viewer can see earnings
    var showEarnings: Bool

    /// Whether the viewer has blocked this sharer
    var blocked: Bool

    // MARK: - Cache Metadata

    var cachedAt: Date

    // MARK: - Computed Properties

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

    var avatarUrl: String? {
        profilePictureUrl ?? oauthAvatarUrl
    }

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

    // MARK: - Initialization

    init(
        sharerId: String,
        viewerId: String,
        email: String?,
        phone: String?,
        firstName: String?,
        profilePictureUrl: String?,
        oauthAvatarUrl: String?,
        sharedAt: String,
        showEarnings: Bool,
        blocked: Bool,
        cachedAt: Date = Date()
    ) {
        self.compositeKey = "\(viewerId):\(sharerId)"
        self.sharerId = sharerId
        self.viewerId = viewerId
        self.email = email
        self.phone = phone
        self.firstName = firstName
        self.profilePictureUrl = profilePictureUrl
        self.oauthAvatarUrl = oauthAvatarUrl
        self.sharedAt = sharedAt
        self.showEarnings = showEarnings
        self.blocked = blocked
        self.cachedAt = cachedAt
    }

    /// Create from API response
    static func from(sharedUser: SharedUser, viewerId: String) -> LocalSharer {
        LocalSharer(
            sharerId: sharedUser.id,
            viewerId: viewerId,
            email: sharedUser.email,
            phone: sharedUser.phone,
            firstName: sharedUser.firstName,
            profilePictureUrl: sharedUser.profilePictureUrl,
            oauthAvatarUrl: sharedUser.oauthAvatarUrl,
            sharedAt: sharedUser.sharedAt,
            showEarnings: sharedUser.showEarnings,
            blocked: sharedUser.blocked
        )
    }

    /// Convert back to SharedUser for use with existing code
    func toSharedUser() -> SharedUser {
        SharedUser(
            id: sharerId,
            email: email,
            phone: phone,
            firstName: firstName,
            profilePictureUrl: profilePictureUrl,
            oauthAvatarUrl: oauthAvatarUrl,
            sharedAt: sharedAt,
            showEarnings: showEarnings,
            blocked: blocked
        )
    }
}
