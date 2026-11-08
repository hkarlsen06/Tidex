// swiftlint:disable explicit_type_interface sorted_imports
// swiftlint:disable:previous blanket_disable_command
import Foundation
import SwiftData
import os.log

let kLocalStoreLogger = Logger(subsystem: "com.tidex.app", category: "LocalStore")
let kLogIdentifierPrefixLength = 8

internal enum LocalStoreWriteError: Error {
  case missingConflictSnapshot
  case notFound
  case notInConflict
}

// MARK: - Local Store

/// Central SwiftData container for offline storage
/// Manages the ModelContainer and provides thread-safe access via ModelActor
@MainActor
internal final class LocalStore {
  private static let appGroupId = "group.no.tidex.app"

  /// Shared instance for the app
  internal static let shared = LocalStore()

  /// The SwiftData model container
  internal let container: ModelContainer

  /// Actor for serialized writes (sync operations)
  internal let storeActor: LocalStoreActor

  /// Blocks editing and sync when the persistent store could not be opened.
  internal let isStorageUnavailable: Bool

  private static func ensureStoreParentDirectoryExists() {
    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupId
      )
    else {
      kLocalStoreLogger.error("Missing App Group container for local store")
      return
    }

    let applicationSupportURL =
      appGroupURL
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)

    do {
      try FileManager.default.createDirectory(
        at: applicationSupportURL,
        withIntermediateDirectories: true
      )
    } catch {
      kLocalStoreLogger.error(
        "Failed to create local store directory: \(error.localizedDescription)")
    }
  }

  private convenience init() {
    Self.ensureStoreParentDirectoryExists()

    var usesScreenshotMemoryStore = false
    #if DEBUG
      usesScreenshotMemoryStore = AppStoreScreenshotFixture.isActive
    #endif
    self.init(configuration: ModelConfiguration(
      schema: Schema(versionedSchema: SchemaV1.self),
      isStoredInMemoryOnly: usesScreenshotMemoryStore,
      allowsSave: true
    ))
  }

  internal init(configuration: ModelConfiguration) {
    let schema = Schema(versionedSchema: SchemaV1.self)
    do {
      container = try ModelContainer(
        for: schema,
        migrationPlan: LocalStoreMigrationPlan.self,
        configurations: [configuration]
      )
      isStorageUnavailable = false
      kLocalStoreLogger.info("LocalStore initialized successfully")
    } catch {
      kLocalStoreLogger.error(
        "Failed to open LocalStore: \(String(reflecting: error), privacy: .public)")
      kLocalStoreLogger.error(
        "LocalStore error details: \(String(reflecting: (error as NSError).userInfo), privacy: .private)")
      do {
        container = try Self.makeUnavailableContainer(schema: schema)
      } catch {
        fatalError("LocalStore could not create its read-only container: \(error)")
      }
      isStorageUnavailable = true
    }
    storeActor = LocalStoreActor(modelContainer: container)
  }

  private static func makeUnavailableContainer(schema: Schema) throws -> ModelContainer {
    // Keep the failed store untouched. SwiftData cannot open an in-memory store read-only,
    // so create an empty temporary store for readers while the root view blocks editing.
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("unavailable-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("default.store")
    try autoreleasepool {
      _ = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
      )
    }
    return try ModelContainer(
      for: schema,
      configurations: [ModelConfiguration(
        schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none
      )]
    )
  }

  /// Get a fresh ModelContext for main actor operations
  /// Creates a new context each time to ensure it sees the latest persisted data
  /// (avoids stale cache issues when actor writes and main thread reads)
  internal var mainContext: ModelContext {
    ModelContext(container)
  }

  /// Reset all local data (for debugging or logout)
  internal func resetAllData() async {
    await storeActor.resetAllData()
    kLocalStoreLogger.info("All local data has been reset")
  }
}

// MARK: - Local Store Actor

/// ModelActor for serialized write operations
/// All sync operations should use this actor to prevent data races
@ModelActor
internal actor LocalStoreActor {
  let isoDateFormatter: DateFormatter = FormatterCache.isoDateFormatter(
    timeZone: Date.localTimeZone
  )

  /// Delete all data from all tables.
  /// Kept manual: `testResetAllDataClearsExistingRowsAndLeavesTheContainerUsable` crashed the
  /// test process when this called `modelContext.container.erase()`, so the container doesn't
  /// reliably stay usable afterward. Per-model batch deletes don't have that problem.
  internal func resetAllData() {
    do {
      try modelContext.delete(model: LocalUserShift.self)
      try modelContext.delete(model: LocalEvent.self)
      try modelContext.delete(model: LocalJob.self)
      try modelContext.delete(model: LocalRecurringShift.self)
      try modelContext.delete(model: LocalWageSnapshot.self)
      try modelContext.delete(model: LocalPayrollAdjustment.self)
      try modelContext.delete(model: LocalUserSettings.self)
      try modelContext.delete(model: LocalNotificationPreferences.self)
      try modelContext.delete(model: LocalSyncState.self)
      try modelContext.delete(model: LocalSharedShift.self)
      try modelContext.delete(model: LocalSharer.self)
      try modelContext.delete(model: LocalShiftPreview.self)
      try modelContext.delete(model: LocalSharedShiftFetchRecord.self)
      try modelContext.delete(model: LocalPendingFriendComposerDraft.self)
      try modelContext.delete(model: LocalThread.self)
      try modelContext.delete(model: LocalThreadState.self)
      try modelContext.delete(model: LocalThreadFeedPlacement.self)
      try modelContext.delete(model: LocalMessage.self)
      try modelContext.delete(model: LocalMessageAttachment.self)
      try modelContext.delete(model: LocalMessageReaction.self)
      try modelContext.delete(model: LocalFriendMessagingSyncState.self)
      try modelContext.save()
    } catch {
      kLocalStoreLogger.error("Failed to reset all data: \(error.localizedDescription)")
    }
  }

  /// Save changes to the context
  internal func save() throws {
    try modelContext.save()
  }

  /// Save changes and return an error description instead of throwing.
  internal func saveErrorDescription() -> String? {
    do {
      try modelContext.save()
      return nil
    } catch {
      return error.localizedDescription
    }
  }
}
