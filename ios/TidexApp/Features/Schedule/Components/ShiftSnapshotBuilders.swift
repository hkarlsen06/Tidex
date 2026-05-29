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
    ShiftSnapshotDraftFactory.makeDraft(
      .init(
        shift: shift,
        jobName: normalizedJobName,
        jobColorHex: normalizedJobColorHex,
        currency: currency,
        ownerUserId: normalizedOwnerUserId,
        ownerDisplayName: normalizedOwnerDisplayName,
        ownerAvatarUrl: ownerAvatarUrl,
        includesEarnings: canSeeOwnerEarnings,
        ownerIdSeed: ownerUserId
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
    ShiftSnapshotDraftFactory.makeDraft(
      .init(
        shift: shift,
        jobName: normalizedJobName,
        jobColorHex: normalizedJobColorHex,
        currency: currency,
        ownerUserId: normalizedOwnerUserId,
        ownerDisplayName: owner.displayName,
        ownerAvatarUrl: owner.avatarUrl,
        includesEarnings: owner.showEarnings,
        ownerIdSeed: owner.id
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

  private var normalizedJobColorHex: String? {
    let trimmed = jobColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == true ? nil : trimmed
  }
}

struct ForwardedShiftSnapshotBuilder {
  let snapshot: FriendShiftSnapshot
  let viewerUserId: String

  func build(for recipient: ShareRecipient) -> ComposerShiftSnapshotDraft {
    let canSeeOwnerEarnings = snapshot.ownerUserId == viewerUserId && recipient.canSeeOwnerEarnings
    return ComposerShiftSnapshotDraft(
      snapshot: snapshot.applyingEarningsVisibility(canSeeOwnerEarnings)
    )
  }
}

private enum ShiftSnapshotDraftFactory {
  struct Configuration {
    let shift: ShiftWithComputations
    let jobName: String?
    let jobColorHex: String?
    let currency: String
    let ownerUserId: String
    let ownerDisplayName: String
    let ownerAvatarUrl: String?
    let includesEarnings: Bool
    let ownerIdSeed: String
  }

  static func makeDraft(
    _ configuration: Configuration
  ) -> ComposerShiftSnapshotDraft {
    ComposerShiftSnapshotDraft(
      snapshot: FriendShiftSnapshot(
        schemaVersion: 1,
        ownerUserId: configuration.ownerUserId,
        ownerDisplayName: configuration.ownerDisplayName,
        ownerAvatarUrl: configuration.ownerAvatarUrl,
        shiftId: normalizedShiftId(
          shift: configuration.shift,
          ownerIdSeed: configuration.ownerIdSeed
        ),
        jobName: configuration.jobName,
        jobColorHex: configuration.jobColorHex,
        shiftDate: configuration.shift.shiftDate,
        startTime: configuration.shift.startTime,
        endTime: configuration.shift.endTime,
        paidHours: configuration.shift.paidHours,
        currency: configuration.currency,
        includesEarnings: configuration.includesEarnings,
        grossPay: configuration.includesEarnings ? configuration.shift.grossPay : nil,
        netPay: configuration.includesEarnings ? configuration.shift.netPay : nil,
        taxEnabled: configuration.shift.taxEnabled,
        source: "shift_details_sheet"
      )
    )
  }

  static func normalizedShiftId(shift: ShiftWithComputations, ownerIdSeed: String) -> String {
    SnapshotRichContentIdentifier.normalizedUUIDString(
      primary: shift.id,
      secondary: shift.shift.recurring_id,
      fallbackSeed:
        "shift:\(ownerIdSeed):\(shift.id):\(shift.shiftDate):\(shift.startTime):\(shift.endTime)"
    )
  }
}
