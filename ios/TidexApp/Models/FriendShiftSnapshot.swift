import CryptoKit
import Foundation

internal struct FriendShiftSnapshot: Codable, Equatable {
  private static let ownerInitialsLimit: Int = 2

  internal let schemaVersion: Int
  internal let ownerUserId: String
  internal let ownerDisplayName: String
  internal let ownerAvatarUrl: String?
  internal let shiftId: String
  internal let jobName: String?
  internal let jobColorHex: String?
  internal let shiftDate: String
  internal let startTime: String
  internal let endTime: String
  internal let paidHours: Double
  internal let currency: String
  internal let includesEarnings: Bool
  internal let grossPay: Double?
  internal let netPay: Double?
  internal let taxEnabled: Bool
  internal let source: String

  internal enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case ownerUserId = "owner_user_id"
    case ownerDisplayName = "owner_display_name"
    case ownerAvatarUrl = "owner_avatar_url"
    case shiftId = "shift_id"
    case jobName = "job_name"
    case jobColorHex = "job_color_hex"
    case shiftDate = "shift_date"
    case startTime = "start_time"
    case endTime = "end_time"
    case paidHours = "paid_hours"
    case currency
    case includesEarnings = "includes_earnings"
    case grossPay = "gross_pay"
    case netPay = "net_pay"
    case taxEnabled = "tax_enabled"
    case source
  }

  internal var isSupportedSchemaVersion: Bool {
    schemaVersion == 1
  }

  internal var ownerFirstName: String {
    let trimmed: String = ownerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "?"
    }
    return trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? trimmed
  }

  internal var ownerInitials: String {
    let letters: ArraySlice<String.Element> =
      ownerFirstName
      .split(whereSeparator: \.isWhitespace)
      .compactMap(\.first)
      .prefix(Self.ownerInitialsLimit)
    let initials: String = letters.map(String.init).joined()
    return initials.isEmpty ? "?" : initials.uppercased()
  }

  internal var normalizedForTransport: Self {
    Self(
      schemaVersion: schemaVersion,
      ownerUserId: SnapshotRichContentIdentifier.normalizedUUIDString(
        primary: ownerUserId,
        fallbackSeed: "owner:\(ownerUserId)"
      ),
      ownerDisplayName: ownerDisplayName,
      ownerAvatarUrl: ownerAvatarUrl,
      shiftId: SnapshotRichContentIdentifier.normalizedUUIDString(
        primary: shiftId,
        fallbackSeed: "shift:\(shiftId):\(shiftDate):\(startTime):\(endTime)"
      ),
      jobName: jobName,
      jobColorHex: jobColorHex,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      paidHours: paidHours,
      currency: currency,
      includesEarnings: includesEarnings,
      grossPay: grossPay,
      netPay: netPay,
      taxEnabled: taxEnabled,
      source: source
    )
  }

  // swiftlint:disable:next type_contents_order
  internal func applyingEarningsVisibility(_ canSeeEarnings: Bool) -> Self {
    guard !canSeeEarnings else {
      return self
    }

    return Self(
      schemaVersion: schemaVersion,
      ownerUserId: ownerUserId,
      ownerDisplayName: ownerDisplayName,
      ownerAvatarUrl: ownerAvatarUrl,
      shiftId: shiftId,
      jobName: jobName,
      jobColorHex: jobColorHex,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      paidHours: paidHours,
      currency: currency,
      includesEarnings: false,
      grossPay: nil,
      netPay: nil,
      taxEnabled: false,
      source: source
    )
  }

  internal var renderableShift: ShiftWithComputations {
    let gross: Double = grossPay ?? netPay ?? 0
    let resolvedTaxEnabled: Bool = includesEarnings ? taxEnabled : false
    let resolvedTaxPercentage: Double

    if resolvedTaxEnabled, gross > 0, let netPay {
      resolvedTaxPercentage = max(0, min((1 - (netPay / gross)) * 100, 100))
    } else {
      resolvedTaxPercentage = 0
    }

    return ShiftWithComputations(
      shift: ShiftRow(
        id: shiftId,
        user_id: ownerUserId,
        job_id: nil,
        shift_date: shiftDate,
        start_time: startTime,
        end_time: endTime,
        custom_supplements: nil
      ),
      computed: ShiftComputed(
        id: shiftId,
        durationHours: paidHours,
        paidHours: paidHours,
        basePay: gross,
        supplementPay: 0,
        gross: gross,
        wagePeriods: [],
        originalWagePeriods: [],
        breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
      ),
      taxEnabled: resolvedTaxEnabled,
      taxPercentage: resolvedTaxPercentage
    )
  }
}

internal enum SnapshotRichContentIdentifier {
  private static let uuidByteCount: Int = 16
  private static let uuidVersionByteIndex: Int = 6
  private static let uuidVariantByteIndex: Int = 8
  private static let uuidVersionMask: UInt8 = 0x0F
  private static let uuidVersionBits: UInt8 = 0x50
  private static let uuidVariantMask: UInt8 = 0x3F
  private static let uuidVariantBits: UInt8 = 0x80
  private static let uuidPattern: String =
    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"

  internal static func normalizedUUIDString(primary: String, fallbackSeed: String) -> String {
    if let valid = validUUIDString(from: primary) {
      return valid
    }

    return deterministicUUID(seed: fallbackSeed)
  }

  internal static func normalizedUUIDString(
    primary: String?, secondary: String?, fallbackSeed: String
  )
    -> String
  {
    if let primary, let valid = validUUIDString(from: primary) {
      return valid
    }

    if let secondary, let valid = validUUIDString(from: secondary) {
      return valid
    }

    return deterministicUUID(seed: fallbackSeed)
  }

  private static func validUUIDString(from rawValue: String) -> String? {
    let trimmed: String = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.range(of: uuidPattern, options: .regularExpression) != nil
    else {
      return nil
    }
    return trimmed.lowercased()
  }

  private static func deterministicUUID(seed: String) -> String {
    let digest: SHA256.Digest = SHA256.hash(data: Data(seed.utf8))
    var bytes: [UInt8] = Array(digest.prefix(Self.uuidByteCount))
    bytes[Self.uuidVersionByteIndex] =
      (bytes[Self.uuidVersionByteIndex] & Self.uuidVersionMask) | Self.uuidVersionBits
    bytes[Self.uuidVariantByteIndex] =
      (bytes[Self.uuidVariantByteIndex] & Self.uuidVariantMask) | Self.uuidVariantBits

    let uuid: UUID = UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
      ))
    return uuid.uuidString.lowercased()
  }
}

internal struct ComposerShiftSnapshotDraft: Codable, Equatable {
  internal let snapshot: FriendShiftSnapshot

  internal var ownerDisplayName: String {
    snapshot.ownerDisplayName
  }
}
