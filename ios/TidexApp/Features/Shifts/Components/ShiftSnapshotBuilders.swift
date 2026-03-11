import Foundation

enum ShiftSnapshotShareContext: Equatable {
  case own
  case shared(owner: SharedUser)
}

struct OwnShiftSnapshotBuilder {
  let shift: ShiftWithComputations
  let jobName: String?
  let jobColorHex: String?
  let currency: String
  let ownerUserId: String
  let ownerDisplayName: String
  let ownerAvatarUrl: String?

  func build(for recipient: ShareRecipient) -> ComposerShiftSnapshotDraft {
    build(canSeeOwnerEarnings: recipient.canSeeOwnerEarnings)
  }

  func build(canSeeOwnerEarnings: Bool) -> ComposerShiftSnapshotDraft {
    let includesEarnings = canSeeOwnerEarnings
    return ComposerShiftSnapshotDraft(
      snapshot: FriendShiftSnapshot(
        schemaVersion: 1,
        ownerUserId: normalizedOwnerUserId,
        ownerDisplayName: normalizedOwnerDisplayName,
        ownerAvatarUrl: ownerAvatarUrl,
        shiftId: normalizedShiftId,
        jobName: normalizedJobName,
        jobColorHex: normalizedJobColorHex,
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        paidHours: shift.paidHours,
        currency: currency,
        includesEarnings: includesEarnings,
        grossPay: includesEarnings ? shift.grossPay : nil,
        netPay: includesEarnings ? shift.netPay : nil,
        taxEnabled: shift.taxEnabled,
        source: "shift_details_sheet"
      )
    )
  }

  private var normalizedOwnerDisplayName: String {
    let trimmed = ownerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "User" : trimmed
  }

  private var normalizedOwnerUserId: String {
    SnapshotRichContentIdentifier.normalizedUUIDString(
      primary: ownerUserId,
      fallbackSeed: "owner:\(ownerUserId)"
    )
  }

  private var normalizedShiftId: String {
    SnapshotRichContentIdentifier.normalizedUUIDString(
      primary: shift.id,
      secondary: shift.shift.recurring_id,
      fallbackSeed:
        "shift:\(ownerUserId):\(shift.id):\(shift.shiftDate):\(shift.startTime):\(shift.endTime)"
    )
  }

  private var normalizedJobName: String? {
    let trimmed = jobName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == true ? nil : trimmed
  }

  private var normalizedJobColorHex: String? {
    let trimmed = jobColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == true ? nil : trimmed
  }
}

struct SharedShiftSnapshotBuilder {
  let shift: ShiftWithComputations
  let jobName: String?
  let jobColorHex: String?
  let currency: String
  let owner: SharedUser

  func build() -> ComposerShiftSnapshotDraft {
    let includesEarnings = owner.showEarnings
    return ComposerShiftSnapshotDraft(
      snapshot: FriendShiftSnapshot(
        schemaVersion: 1,
        ownerUserId: normalizedOwnerUserId,
        ownerDisplayName: owner.displayName,
        ownerAvatarUrl: owner.avatarUrl,
        shiftId: normalizedShiftId,
        jobName: normalizedJobName,
        jobColorHex: normalizedJobColorHex,
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        paidHours: shift.paidHours,
        currency: currency,
        includesEarnings: includesEarnings,
        grossPay: includesEarnings ? shift.grossPay : nil,
        netPay: includesEarnings ? shift.netPay : nil,
        taxEnabled: shift.taxEnabled,
        source: "shift_details_sheet"
      )
    )
  }

  private var normalizedJobName: String? {
    let trimmed = jobName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == true ? nil : trimmed
  }

  private var normalizedOwnerUserId: String {
    SnapshotRichContentIdentifier.normalizedUUIDString(
      primary: owner.id,
      fallbackSeed: "owner:\(owner.id)"
    )
  }

  private var normalizedShiftId: String {
    SnapshotRichContentIdentifier.normalizedUUIDString(
      primary: shift.id,
      secondary: shift.shift.recurring_id,
      fallbackSeed:
        "shift:\(owner.id):\(shift.id):\(shift.shiftDate):\(shift.startTime):\(shift.endTime)"
    )
  }

  private var normalizedJobColorHex: String? {
    let trimmed = jobColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == true ? nil : trimmed
  }
}
