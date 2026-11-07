import SwiftData

/// Matches the unversioned schema shipped before migration planning.
internal enum SchemaV1: VersionedSchema {
  internal static let versionIdentifier = Schema.Version(1, 0, 0)

  internal static var models: [any PersistentModel.Type] {
    [
      LocalJob.self,
      LocalUserShift.self,
      LocalEvent.self,
      LocalRecurringShift.self,
      LocalWageSnapshot.self,
      LocalPayrollAdjustment.self,
      LocalUserSettings.self,
      LocalNotificationPreferences.self,
      LocalSyncState.self,
      LocalSharedShift.self,
      LocalSharer.self,
      LocalShiftPreview.self,
      LocalSharedShiftFetchRecord.self,
      LocalPendingFriendComposerDraft.self,
      LocalThread.self,
      LocalThreadState.self,
      LocalThreadFeedPlacement.self,
      LocalMessage.self,
      LocalMessageAttachment.self,
      LocalMessageReaction.self,
      LocalFriendMessagingSyncState.self,
    ]
  }
}

internal enum LocalStoreMigrationPlan: SchemaMigrationPlan {
  internal static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
  internal static var stages: [MigrationStage] { [] }
}
