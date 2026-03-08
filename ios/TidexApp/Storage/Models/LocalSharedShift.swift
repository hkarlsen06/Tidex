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

  /// Job ID for multi-job context (optional for legacy cached rows)
  var jobId: String?

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
    jobId: String? = nil,
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
    self.jobId = jobId
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
      jobId: apiShift.job_id,
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
      job_id: jobId,
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

  /// Whether the viewer has hidden this sharer
  @Attribute(originalName: "blocked")
  var hidden: Bool

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
    hidden: Bool,
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
    self.hidden = hidden
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
      hidden: sharedUser.hidden
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
      hidden: hidden
    )
  }
}

// MARK: - Local Shift Preview Cache

/// SwiftData model for caching shift previews
/// Shows the most relevant shift (active/upcoming/past) for each sharer
@Model
final class LocalShiftPreview {
  // MARK: - Primary Key

  /// Composite key: viewerId:sharerId
  @Attribute(.unique)
  var compositeKey: String

  // MARK: - Identity

  /// The sharer's user ID
  var sharerId: String

  /// The viewer's user ID (current user)
  var viewerId: String

  // MARK: - Preview Status

  /// Status: active, upcoming, or past
  var status: String?

  /// Whether earnings are visible
  var showEarnings: Bool

  // MARK: - Shift Data (optional - may be nil if no shifts)

  var shiftId: String?
  var shiftDate: String?
  var startTime: String?
  var endTime: String?
  var durationHours: Double?
  var paidHours: Double?
  var basePay: Double?
  var supplementPay: Double?
  var gross: Double?
  var taxEnabled: Bool?
  var taxPercentage: Double?
  var recurringId: String?
  var recurringAnchorWeekday: Int?

  // MARK: - Cache Metadata

  var cachedAt: Date

  // MARK: - Initialization

  init(
    sharerId: String,
    viewerId: String,
    status: String?,
    showEarnings: Bool,
    shiftId: String? = nil,
    shiftDate: String? = nil,
    startTime: String? = nil,
    endTime: String? = nil,
    durationHours: Double? = nil,
    paidHours: Double? = nil,
    basePay: Double? = nil,
    supplementPay: Double? = nil,
    gross: Double? = nil,
    taxEnabled: Bool? = nil,
    taxPercentage: Double? = nil,
    recurringId: String? = nil,
    recurringAnchorWeekday: Int? = nil,
    cachedAt: Date = Date()
  ) {
    self.compositeKey = "\(viewerId):\(sharerId)"
    self.sharerId = sharerId
    self.viewerId = viewerId
    self.status = status
    self.showEarnings = showEarnings
    self.shiftId = shiftId
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
    self.recurringId = recurringId
    self.recurringAnchorWeekday = recurringAnchorWeekday
    self.cachedAt = cachedAt
  }

  /// Create from SharerShiftPreview
  static func from(
    preview: SharerShiftPreview,
    viewerId: String
  ) -> LocalShiftPreview {
    LocalShiftPreview(
      sharerId: preview.sharerId,
      viewerId: viewerId,
      status: preview.status?.rawValue,
      showEarnings: preview.showEarnings,
      shiftId: preview.shift?.id,
      shiftDate: preview.shift?.shift_date,
      startTime: preview.shift?.start_time,
      endTime: preview.shift?.end_time,
      durationHours: preview.shift?.computed.durationHours,
      paidHours: preview.shift?.computed.paidHours,
      basePay: preview.shift?.computed.basePay,
      supplementPay: preview.shift?.computed.supplementPay,
      gross: preview.shift?.computed.gross,
      taxEnabled: preview.shift?.tax_enabled,
      taxPercentage: preview.shift?.tax_percentage,
      recurringId: preview.shift?.recurring_id,
      recurringAnchorWeekday: preview.shift?.recurring_anchor_weekday
    )
  }

  /// Convert back to SharerShiftPreview
  func toSharerShiftPreview() -> SharerShiftPreview {
    let shiftData: SharedShiftData? = buildShiftData()
    let previewStatus: ShiftPreviewStatus? = status.flatMap { ShiftPreviewStatus(rawValue: $0) }

    return SharerShiftPreview(
      sharerId: sharerId,
      shift: shiftData,
      status: previewStatus,
      showEarnings: showEarnings
    )
  }

  /// Helper to build SharedShiftData (separated to help compiler type-checking)
  private func buildShiftData() -> SharedShiftData? {
    guard let shiftId = shiftId,
      let shiftDate = shiftDate,
      let startTime = startTime,
      let endTime = endTime
    else {
      return nil
    }

    let computedPayroll = SharedShiftComputed(
      id: shiftId,
      durationHours: durationHours ?? 0,
      paidHours: paidHours ?? 0,
      basePay: basePay ?? 0,
      supplementPay: supplementPay ?? 0,
      gross: gross ?? 0
    )

    return SharedShiftData(
      id: shiftId,
      user_id: sharerId,
      job_id: nil,
      job_name: nil,
      job_color: nil,
      shift_date: shiftDate,
      start_time: startTime,
      end_time: endTime,
      computed: computedPayroll,
      tax_enabled: taxEnabled,
      tax_percentage: taxPercentage,
      custom_supplements: nil,
      recurring_id: recurringId,
      recurring_anchor_weekday: recurringAnchorWeekday
    )
  }
}

// MARK: - Fetch Record (tracks which owner/month combinations have been fetched)

/// Tracks that a specific owner/month was fetched from the server.
/// Allows distinguishing "never fetched" from "fetched but empty" so that
/// revisiting an empty month shows the calendar instantly without a loading state.
@Model
final class LocalSharedShiftFetchRecord {
  @Attribute(.unique)
  var compositeKey: String

  var ownerId: String
  var viewerId: String
  var year: Int
  var month: Int
  var fetchedAt: Date
  var shiftCount: Int

  init(
    ownerId: String,
    viewerId: String,
    year: Int,
    month: Int,
    shiftCount: Int,
    fetchedAt: Date = Date()
  ) {
    self.compositeKey = "\(viewerId):\(ownerId):\(year):\(month)"
    self.ownerId = ownerId
    self.viewerId = viewerId
    self.year = year
    self.month = month
    self.shiftCount = shiftCount
    self.fetchedAt = fetchedAt
  }
}
