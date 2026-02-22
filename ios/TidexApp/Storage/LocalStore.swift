import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "LocalStore")

enum LocalStoreWriteError: Error {
  case notFound
  case notInConflict
  case missingConflictSnapshot
}

// MARK: - Local Store

/// Central SwiftData container for offline storage
/// Manages the ModelContainer and provides thread-safe access via ModelActor
@MainActor
final class LocalStore {
  private static let appGroupId = "group.no.tidex.app"

  /// Shared instance for the app
  static let shared = LocalStore()

  /// The SwiftData model container
  let container: ModelContainer

  /// Actor for serialized writes (sync operations)
  let storeActor: LocalStoreActor

  /// Indicates if the store fell back to in-memory storage due to persistent storage failure.
  /// When true, data will NOT be saved between app launches - user should be warned.
  let isUsingInMemoryFallback: Bool

  private static func ensureStoreParentDirectoryExists() {
    guard
      let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupId)
    else {
      logger.error("Missing App Group container for local store")
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
      logger.error("Failed to create local store directory: \(error.localizedDescription)")
    }
  }

  private init() {
    Self.ensureStoreParentDirectoryExists()

    // Create schema with all local models
    let schema = Schema([
      LocalUserShift.self,
      LocalRecurringShift.self,
      LocalWageSnapshot.self,
      LocalUserSettings.self,
      LocalNotificationPreferences.self,
      LocalSyncState.self,
      LocalEntitlementCache.self,
      LocalPendingJWSUpload.self,
      LocalSharedShift.self,
      LocalSharer.self,
      LocalShiftPreview.self,
      LocalSharedShiftFetchRecord.self,
      LocalConversation.self,
    ])

    // Configure container for persistent storage
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false,
      allowsSave: true
    )

    do {
      container = try ModelContainer(for: schema, configurations: [configuration])
      storeActor = LocalStoreActor(modelContainer: container)
      isUsingInMemoryFallback = false
      logger.info("LocalStore initialized successfully")
    } catch {
      logger.error("Failed to initialize LocalStore: \(error.localizedDescription)")

      // Try to recover by creating an in-memory container as fallback
      // This allows the app to function (without persistence) rather than crash
      logger.warning("Attempting fallback to in-memory storage")
      let fallbackConfig = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        allowsSave: true
      )

      do {
        container = try ModelContainer(for: schema, configurations: [fallbackConfig])
        storeActor = LocalStoreActor(modelContainer: container)
        isUsingInMemoryFallback = true
        logger.warning("LocalStore initialized with in-memory fallback - data will not persist")
      } catch let fallbackError {
        // This should essentially never happen - in-memory containers rarely fail
        // But we need to initialize the properties, so create a minimal container
        logger.critical(
          "Failed to create even in-memory storage: \(fallbackError.localizedDescription)")

        // Last resort: try with default configuration
        // If this fails, there's a fundamental issue with the app's model definitions
        do {
          container = try ModelContainer(for: schema)
          storeActor = LocalStoreActor(modelContainer: container)
          isUsingInMemoryFallback = true
          logger.critical("LocalStore using default container - app may be unstable")
        } catch let lastResortError {
          fatalError(
            """
            LocalStore: All storage initialization attempts failed.
            Original error: \(error.localizedDescription)
            In-memory fallback error: \(fallbackError.localizedDescription)
            Default container error: \(lastResortError.localizedDescription)
            This indicates a fundamental issue with the app's SwiftData model definitions.
            """)
        }
      }
    }
  }

  /// Get a fresh ModelContext for main actor operations
  /// Creates a new context each time to ensure it sees the latest persisted data
  /// (avoids stale cache issues when actor writes and main thread reads)
  var mainContext: ModelContext {
    ModelContext(container)
  }

  /// Reset all local data (for debugging or logout)
  func resetAllData() async {
    await storeActor.resetAllData()
    logger.info("All local data has been reset")
  }
}

// MARK: - Local Store Actor

/// ModelActor for serialized write operations
/// All sync operations should use this actor to prevent data races
@ModelActor
actor LocalStoreActor {
  private let isoDateFormatter: DateFormatter = FormatterCache.isoDateFormatter(
    timeZone: Date.localTimeZone)

  /// Delete all data from all tables
  func resetAllData() {
    do {
      try modelContext.delete(model: LocalUserShift.self)
      try modelContext.delete(model: LocalRecurringShift.self)
      try modelContext.delete(model: LocalWageSnapshot.self)
      try modelContext.delete(model: LocalUserSettings.self)
      try modelContext.delete(model: LocalNotificationPreferences.self)
      try modelContext.delete(model: LocalSyncState.self)
      try modelContext.delete(model: LocalEntitlementCache.self)
      try modelContext.delete(model: LocalPendingJWSUpload.self)
      try modelContext.delete(model: LocalSharedShift.self)
      try modelContext.delete(model: LocalSharer.self)
      try modelContext.delete(model: LocalShiftPreview.self)
      try modelContext.delete(model: LocalSharedShiftFetchRecord.self)
      try modelContext.delete(model: LocalConversation.self)
      try modelContext.save()
    } catch {
      logger.error("Failed to reset all data: \(error.localizedDescription)")
    }
  }

  /// Save changes to the context
  func save() throws {
    try modelContext.save()
  }

  // MARK: - Read Operations (Local Only)

  func fetchUserSettings(userId: String) -> UserSettings? {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    do {
      guard let localSettings = try modelContext.fetch(descriptor).first else {
        return nil
      }
      return localSettings.toUserSettings()
    } catch {
      logger.error("Failed to fetch settings: \(error.localizedDescription)")
      return nil
    }
  }

  func fetchSnapshots(userId: String) -> [WageSnapshot] {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.userId == userId },
      sortBy: [SortDescriptor(\LocalWageSnapshot.localUpdatedAt, order: .reverse)]
    )

    do {
      let localSnapshots = try modelContext.fetch(descriptor)
      return localSnapshots.map { $0.toWageSnapshot() }
    } catch {
      logger.error("Failed to fetch snapshots: \(error.localizedDescription)")
      return []
    }
  }

  func fetchRecurringShifts(userId: String) -> [RecurringShiftRow] {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
          && shift.syncStatusRaw != "pendingDelete"
      },
      sortBy: [SortDescriptor(\LocalRecurringShift.localUpdatedAt, order: .reverse)]
    )

    do {
      let localRecurring = try modelContext.fetch(descriptor)
      return localRecurring.map { $0.toRecurringShiftRow() }
    } catch {
      logger.error("Failed to fetch recurring shifts: \(error.localizedDescription)")
      return []
    }
  }

  func fetchShifts(userId: String, startDate: Date, endDate: Date) -> [ShiftRow] {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
          && shift.syncStatusRaw != "pendingDelete" && shift.shiftDate >= startDate
          && shift.shiftDate <= endDate
      },
      sortBy: [SortDescriptor(\LocalUserShift.shiftDate, order: .reverse)]
    )

    do {
      let localShifts: [LocalUserShift] = try modelContext.fetch(descriptor)
      return localShifts.map { $0.toShiftRow() }
    } catch {
      logger.error("Failed to fetch shifts: \(error.localizedDescription)")
      return []
    }
  }

  // MARK: - Sync State Operations

  /// Get or create sync state for a user
  func getOrCreateSyncState(userId: String) throws -> LocalSyncState {
    let descriptor = FetchDescriptor<LocalSyncState>(
      predicate: #Predicate { $0.userId == userId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      return existing
    }

    let newState = LocalSyncState(userId: userId)
    modelContext.insert(newState)
    try modelContext.save()
    return newState
  }

  /// Get sync state for a user (returns nil if not found)
  func getSyncState(userId: String) throws -> LocalSyncState? {
    let descriptor = FetchDescriptor<LocalSyncState>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor).first
  }

  // MARK: - User Shift Operations

  /// Upsert a user shift from server data
  func upsertUserShift(_ shift: LocalUserShift) throws {
    let shiftId = shift.id
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == shiftId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing - copy all fields
      existing.shiftDate = shift.shiftDate
      existing.startTime = shift.startTime
      existing.endTime = shift.endTime
      existing.customSupplements = shift.customSupplements
      existing.serverUpdatedAt = shift.serverUpdatedAt
      existing.serverRevision = shift.serverRevision
      existing.serverDeletedAt = shift.serverDeletedAt
      existing.syncStatusRaw = shift.syncStatusRaw
      existing.dirtyFields = shift.dirtyFields
      existing.lastSyncedSnapshot = shift.lastSyncedSnapshot
      existing.localUpdatedAt = shift.localUpdatedAt
      existing.conflictServerSnapshot = shift.conflictServerSnapshot
    } else {
      // Insert new
      modelContext.insert(shift)
    }
  }

  /// Get user shift by ID
  func getUserShift(id: String) throws -> LocalUserShift? {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get all user shifts for a user (including soft-deleted for sync)
  func getAllUserShifts(userId: String) throws -> [LocalUserShift] {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty user shifts that need to be pushed
  func getDirtyUserShifts(userId: String) throws -> [LocalUserShift] {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId
          && (shift.syncStatusRaw == "dirty" || shift.syncStatusRaw == "pendingDelete"
            // Include conflict records that were never synced (serverRevision=0)
            // These are new local records that failed initial sync and need INSERT
            || (shift.syncStatusRaw == "conflict" && shift.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor)
  }

  // MARK: - Local User Shift Write Operations

  func createUserShift(
    userId: String,
    shiftDate: Date,
    startTime: String,
    endTime: String,
    customSupplements: CustomSupplementsData?
  ) throws -> ShiftRow {
    let id = UUID().lowercasedString
    let now = Date()

    let supplementsData = customSupplements.flatMap { try? canonicalJSONEncoder.encode($0) }

    let dateFormatter = isoDateFormatter
    let shiftDateString = dateFormatter.string(from: shiftDate)

    let snapshot = UserShiftServerSnapshot(
      shiftDate: shiftDateString,
      startTime: startTime,
      endTime: endTime,
      customSupplements: supplementsData,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = UserShiftField.allCases.map { $0.rawValue }
    let dirtyFieldsData = (try? canonicalJSONEncoder.encode(allFields)) ?? Data()

    let localShift = LocalUserShift(
      id: id,
      userId: userId,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      customSupplements: supplementsData,
      serverUpdatedAt: now,
      serverRevision: 0,
      serverDeletedAt: nil,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: snapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localShift)
    try modelContext.save()
    return localShift.toShiftRow()
  }

  func updateUserShift(
    id: String,
    shiftDate: Date?,
    startTime: String?,
    endTime: String?,
    customSupplements: CustomSupplementsData?
  ) throws -> ShiftRow {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localShift.dirtyFieldKeys
    let now = Date()

    if let newDate = shiftDate, newDate != localShift.shiftDate {
      localShift.shiftDate = newDate
      newDirtyFields.insert(.shiftDate)
    }

    if let newStart = startTime, newStart != localShift.startTime {
      localShift.startTime = newStart
      newDirtyFields.insert(.startTime)
    }

    if let newEnd = endTime, newEnd != localShift.endTime {
      localShift.endTime = newEnd
      newDirtyFields.insert(.endTime)
    }

    if let newSupplements = customSupplements {
      let newData = try? canonicalJSONEncoder.encode(newSupplements)
      if newData != localShift.customSupplements {
        localShift.customSupplements = newData
        newDirtyFields.insert(.customSupplements)
      }
    }

    localShift.dirtyFieldKeys = newDirtyFields
    localShift.localUpdatedAt = now

    if !newDirtyFields.isEmpty && localShift.syncStatus == .clean {
      localShift.syncStatus = .dirty
    }

    try modelContext.save()
    return localShift.toShiftRow()
  }

  func markShiftPendingDelete(id: String) throws -> String {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localShift.syncStatus = .pendingDelete
    localShift.localUpdatedAt = Date()

    try modelContext.save()
    return localShift.userId
  }

  func resolveStoredShiftConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localShift.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = UserShiftServerSnapshot.decode(
        from: localShift.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localShift.serverRevision = serverSnapshot.revision
    localShift.serverUpdatedAt = serverSnapshot.updatedAt
    localShift.syncStatus = .dirty
    localShift.conflictServerSnapshot = nil
    localShift.localUpdatedAt = Date()

    try modelContext.save()
  }

  func resolveStoredShiftConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localShift.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localShift.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = UserShiftServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    let dateFormatter = isoDateFormatter

    localShift.shiftDate =
      dateFormatter.date(from: serverSnapshot.shiftDate) ?? localShift.shiftDate
    localShift.startTime = serverSnapshot.startTime
    localShift.endTime = serverSnapshot.endTime
    localShift.customSupplements = serverSnapshot.customSupplements
    localShift.serverRevision = serverSnapshot.revision
    localShift.serverUpdatedAt = serverSnapshot.updatedAt
    localShift.serverDeletedAt = serverSnapshot.deletedAt
    localShift.syncStatus = .clean
    localShift.dirtyFieldKeys = []
    localShift.lastSyncedSnapshot = conflictData
    localShift.conflictServerSnapshot = nil
    localShift.localUpdatedAt = Date()

    try modelContext.save()
  }

  // MARK: - Recurring Shift Operations

  /// Upsert a recurring shift from server data
  func upsertRecurringShift(_ shift: LocalRecurringShift) throws {
    let shiftId = shift.id
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == shiftId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing
      existing.startTime = shift.startTime
      existing.endTime = shift.endTime
      existing.repeatIntervalWeeks = shift.repeatIntervalWeeks
      existing.selectedDays = shift.selectedDays
      existing.endCondition = shift.endCondition
      existing.exclusions = shift.exclusions
      existing.dateSpecificSupplements = shift.dateSpecificSupplements
      existing.serverUpdatedAt = shift.serverUpdatedAt
      existing.serverRevision = shift.serverRevision
      existing.serverDeletedAt = shift.serverDeletedAt
      existing.syncStatusRaw = shift.syncStatusRaw
      existing.dirtyFields = shift.dirtyFields
      existing.lastSyncedSnapshot = shift.lastSyncedSnapshot
      existing.localUpdatedAt = shift.localUpdatedAt
      existing.conflictServerSnapshot = shift.conflictServerSnapshot
    } else {
      // Insert new
      modelContext.insert(shift)
    }
  }

  /// Get recurring shift by ID
  func getRecurringShift(id: String) throws -> LocalRecurringShift? {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get all recurring shifts for a user
  func getAllRecurringShifts(userId: String) throws -> [LocalRecurringShift] {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty recurring shifts that need to be pushed
  func getDirtyRecurringShifts(userId: String) throws -> [LocalRecurringShift] {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { shift in
        shift.userId == userId
          && (shift.syncStatusRaw == "dirty" || shift.syncStatusRaw == "pendingDelete"
            // Include conflict records that were never synced (serverRevision=0)
            // These are new local records that failed initial sync and need INSERT
            || (shift.syncStatusRaw == "conflict" && shift.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor)
  }

  // MARK: - Local Recurring Shift Write Operations

  // swiftlint:disable:next function_parameter_count
  func createRecurringShift(
    userId: String,
    startTime: String,
    endTime: String,
    repeatIntervalWeeks: Int,
    selectedDays: SelectedDays,
    endCondition: EndCondition?,
    exclusions: [String]?,
    dateSpecificSupplements: [String: CustomSupplementsData]?
  ) throws -> RecurringShiftRow {
    let id = UUID().lowercasedString
    let now = Date()

    let selectedDaysData = (try? canonicalJSONEncoder.encode(selectedDays)) ?? Data()
    let endConditionData = endCondition.flatMap { try? canonicalJSONEncoder.encode($0) }
    let exclusionsData = exclusions.flatMap { try? canonicalJSONEncoder.encode($0) }
    let supplementsData = dateSpecificSupplements.flatMap { try? canonicalJSONEncoder.encode($0) }

    let serverSnapshot = RecurringShiftServerSnapshot(
      startTime: startTime,
      endTime: endTime,
      repeatIntervalWeeks: repeatIntervalWeeks,
      selectedDays: selectedDaysData,
      endCondition: endConditionData,
      exclusions: exclusionsData,
      dateSpecificSupplements: supplementsData,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = RecurringShiftField.allCases.map { $0.rawValue }
    let dirtyFieldsData = (try? canonicalJSONEncoder.encode(allFields)) ?? Data()

    let localShift = LocalRecurringShift(
      id: id,
      userId: userId,
      startTime: startTime,
      endTime: endTime,
      repeatIntervalWeeks: repeatIntervalWeeks,
      selectedDays: selectedDaysData,
      endCondition: endConditionData,
      exclusions: exclusionsData,
      dateSpecificSupplements: supplementsData,
      serverUpdatedAt: now,
      serverRevision: 0,
      serverDeletedAt: nil,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: serverSnapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localShift)
    try modelContext.save()
    return localShift.toRecurringShiftRow()
  }

  // swiftlint:disable:next function_parameter_count
  func updateRecurringShift(
    id: String,
    startTime: String?,
    endTime: String?,
    repeatIntervalWeeks: Int?,
    selectedDays: SelectedDays?,
    endCondition: EndCondition?,
    exclusions: [String]?,
    dateSpecificSupplements: [String: CustomSupplementsData]?
  ) throws -> RecurringShiftRow {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localShift.dirtyFieldKeys
    let now = Date()

    if let newStart = startTime, newStart != localShift.startTime {
      localShift.startTime = newStart
      newDirtyFields.insert(.startTime)
    }

    if let newEnd = endTime, newEnd != localShift.endTime {
      localShift.endTime = newEnd
      newDirtyFields.insert(.endTime)
    }

    if let newInterval = repeatIntervalWeeks, newInterval != localShift.repeatIntervalWeeks {
      localShift.repeatIntervalWeeks = newInterval
      newDirtyFields.insert(.repeatIntervalWeeks)
    }

    if let newDays = selectedDays {
      let newData = (try? canonicalJSONEncoder.encode(newDays)) ?? Data()
      if newData != localShift.selectedDays {
        localShift.selectedDays = newData
        newDirtyFields.insert(.selectedDays)
      }
    }

    if let newCondition = endCondition {
      let newData = try? canonicalJSONEncoder.encode(newCondition)
      if newData != localShift.endCondition {
        localShift.endCondition = newData
        newDirtyFields.insert(.endCondition)
      }
    }

    if let newExclusions = exclusions {
      let newData = try? canonicalJSONEncoder.encode(newExclusions)
      if newData != localShift.exclusions {
        localShift.exclusions = newData
        newDirtyFields.insert(.exclusions)
      }
    }

    if let newSupplements = dateSpecificSupplements {
      let newData = try? canonicalJSONEncoder.encode(newSupplements)
      if newData != localShift.dateSpecificSupplements {
        localShift.dateSpecificSupplements = newData
        newDirtyFields.insert(.dateSpecificSupplements)
      }
    }

    localShift.dirtyFieldKeys = newDirtyFields
    localShift.localUpdatedAt = now

    if !newDirtyFields.isEmpty && localShift.syncStatus == .clean {
      localShift.syncStatus = .dirty
    }

    try modelContext.save()
    return localShift.toRecurringShiftRow()
  }

  func addRecurringShiftExclusion(id: String, date: String) throws -> Bool {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var exclusions = localShift.decodedExclusions
    if exclusions.contains(date) {
      return false
    }

    exclusions.append(date)
    localShift.decodedExclusions = exclusions

    var dirtyFields = localShift.dirtyFieldKeys
    dirtyFields.insert(.exclusions)
    localShift.dirtyFieldKeys = dirtyFields

    if localShift.syncStatus == .clean {
      localShift.syncStatus = .dirty
    }
    localShift.localUpdatedAt = Date()

    try modelContext.save()
    return true
  }

  func markRecurringShiftPendingDelete(id: String) throws {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localShift.syncStatus = .pendingDelete
    localShift.localUpdatedAt = Date()

    try modelContext.save()
  }

  func resolveStoredRecurringShiftConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localShift.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = RecurringShiftServerSnapshot.decode(
        from: localShift.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localShift.serverRevision = serverSnapshot.revision
    localShift.serverUpdatedAt = serverSnapshot.updatedAt
    localShift.syncStatus = .dirty
    localShift.conflictServerSnapshot = nil
    localShift.localUpdatedAt = Date()

    try modelContext.save()
  }

  func resolveStoredRecurringShiftConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localShift.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localShift.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = RecurringShiftServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localShift.startTime = serverSnapshot.startTime
    localShift.endTime = serverSnapshot.endTime
    localShift.repeatIntervalWeeks = serverSnapshot.repeatIntervalWeeks
    localShift.selectedDays = serverSnapshot.selectedDays
    localShift.endCondition = serverSnapshot.endCondition
    localShift.exclusions = serverSnapshot.exclusions
    localShift.dateSpecificSupplements = serverSnapshot.dateSpecificSupplements
    localShift.serverRevision = serverSnapshot.revision
    localShift.serverUpdatedAt = serverSnapshot.updatedAt
    localShift.serverDeletedAt = serverSnapshot.deletedAt
    localShift.syncStatus = .clean
    localShift.dirtyFieldKeys = []
    localShift.lastSyncedSnapshot = conflictData
    localShift.conflictServerSnapshot = nil
    localShift.localUpdatedAt = Date()

    try modelContext.save()
  }

  // MARK: - Wage Snapshot Operations

  /// Upsert a wage snapshot from server data
  func upsertWageSnapshot(_ snapshot: LocalWageSnapshot) throws {
    let snapshotId = snapshot.id
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == snapshotId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing
      existing.fromDate = snapshot.fromDate
      existing.hourlyWage = snapshot.hourlyWage
      existing.wageLevel = snapshot.wageLevel
      existing.supplements = snapshot.supplements
      existing.taxEnabled = snapshot.taxEnabled
      existing.taxPercentage = snapshot.taxPercentage
      existing.breakEnabled = snapshot.breakEnabled
      existing.breakMethod = snapshot.breakMethod
      existing.breakThresholdHours = snapshot.breakThresholdHours
      existing.breakDeductionMinutes = snapshot.breakDeductionMinutes
      existing.serverUpdatedAt = snapshot.serverUpdatedAt
      existing.serverRevision = snapshot.serverRevision
      existing.serverDeletedAt = snapshot.serverDeletedAt
      existing.syncStatusRaw = snapshot.syncStatusRaw
      existing.dirtyFields = snapshot.dirtyFields
      existing.lastSyncedSnapshot = snapshot.lastSyncedSnapshot
      existing.localUpdatedAt = snapshot.localUpdatedAt
      existing.conflictServerSnapshot = snapshot.conflictServerSnapshot
    } else {
      // Insert new
      modelContext.insert(snapshot)
    }
  }

  /// Get wage snapshot by ID
  func getWageSnapshot(id: String) throws -> LocalWageSnapshot? {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get all wage snapshots for a user
  func getAllWageSnapshots(userId: String) throws -> [LocalWageSnapshot] {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.userId == userId },
      sortBy: [SortDescriptor(\.fromDate, order: .reverse)]
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty wage snapshots that need to be pushed
  func getDirtyWageSnapshots(userId: String) throws -> [LocalWageSnapshot] {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.userId == userId
          && (snapshot.syncStatusRaw == "dirty" || snapshot.syncStatusRaw == "pendingDelete"
            // Include conflict records that were never synced (serverRevision=0)
            // These are new local records that failed initial sync and need INSERT
            || (snapshot.syncStatusRaw == "conflict" && snapshot.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor)
  }

  // MARK: - Local Wage Snapshot Write Operations

  // swiftlint:disable:next function_parameter_count
  func createWageSnapshot(
    userId: String,
    fromDate: Date?,
    hourlyWage: Double,
    wageLevel: Int?,
    tariffTypeId: String?,
    supplements: SupplementRulesSnapshot,
    taxEnabled: Bool?,
    taxPercentage: Double?,
    breakEnabled: Bool?,
    breakMethod: String?,
    breakThresholdHours: Double?,
    breakDeductionMinutes: Int?
  ) throws -> WageSnapshot {
    let id = UUID().lowercasedString
    let now = Date()

    let supplementsData = (try? canonicalJSONEncoder.encode(supplements)) ?? Data()

    let dateFormatter = isoDateFormatter
    let fromDateString = fromDate.map { dateFormatter.string(from: $0) }

    let serverSnapshot = WageSnapshotServerSnapshot(
      fromDate: fromDateString,
      hourlyWage: hourlyWage,
      wageLevel: wageLevel,
      tariffTypeId: tariffTypeId,
      supplements: supplementsData,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage,
      breakEnabled: breakEnabled,
      breakMethod: breakMethod,
      breakThresholdHours: breakThresholdHours,
      breakDeductionMinutes: breakDeductionMinutes,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = WageSnapshotField.allCases.map { $0.rawValue }
    let dirtyFieldsData = (try? canonicalJSONEncoder.encode(allFields)) ?? Data()

    let localSnapshot = LocalWageSnapshot(
      id: id,
      userId: userId,
      fromDate: fromDate,
      hourlyWage: hourlyWage,
      wageLevel: wageLevel,
      tariffTypeId: tariffTypeId,
      supplements: supplementsData,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage,
      breakEnabled: breakEnabled,
      breakMethod: breakMethod,
      breakThresholdHours: breakThresholdHours,
      breakDeductionMinutes: breakDeductionMinutes,
      serverUpdatedAt: now,
      serverRevision: 0,
      serverDeletedAt: nil,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: serverSnapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localSnapshot)
    try modelContext.save()
    return localSnapshot.toWageSnapshot()
  }

  // swiftlint:disable:next function_parameter_count
  func updateWageSnapshot(
    id: String,
    hourlyWage: Double?,
    wageLevel: Int?,
    supplements: SupplementRulesSnapshot?,
    taxEnabled: Bool?,
    taxPercentage: Double?,
    breakEnabled: Bool?,
    breakMethod: String?,
    breakThresholdHours: Double?,
    breakDeductionMinutes: Int?
  ) throws -> WageSnapshot {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localSnapshot = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localSnapshot.dirtyFieldKeys
    let now = Date()

    if let newWage = hourlyWage, newWage != localSnapshot.hourlyWage {
      localSnapshot.hourlyWage = newWage
      newDirtyFields.insert(.hourlyWage)
    }

    if let newLevel = wageLevel, newLevel != localSnapshot.wageLevel {
      localSnapshot.wageLevel = newLevel
      newDirtyFields.insert(.wageLevel)
    }

    if let newSupplements = supplements {
      let newData = (try? canonicalJSONEncoder.encode(newSupplements)) ?? Data()
      if newData != localSnapshot.supplements {
        localSnapshot.supplements = newData
        newDirtyFields.insert(.supplements)
      }
    }

    if let newTaxEnabled = taxEnabled, newTaxEnabled != localSnapshot.taxEnabled {
      localSnapshot.taxEnabled = newTaxEnabled
      newDirtyFields.insert(.taxEnabled)
    }

    if let newTaxPct = taxPercentage, newTaxPct != localSnapshot.taxPercentage {
      localSnapshot.taxPercentage = newTaxPct
      newDirtyFields.insert(.taxPercentage)
    }

    if let newBreakEnabled = breakEnabled, newBreakEnabled != localSnapshot.breakEnabled {
      localSnapshot.breakEnabled = newBreakEnabled
      newDirtyFields.insert(.breakEnabled)
    }

    if let newBreakMethod = breakMethod, newBreakMethod != localSnapshot.breakMethod {
      localSnapshot.breakMethod = newBreakMethod
      newDirtyFields.insert(.breakMethod)
    }

    if let newThreshold = breakThresholdHours, newThreshold != localSnapshot.breakThresholdHours {
      localSnapshot.breakThresholdHours = newThreshold
      newDirtyFields.insert(.breakThresholdHours)
    }

    if let newDeduction = breakDeductionMinutes, newDeduction != localSnapshot.breakDeductionMinutes
    {
      localSnapshot.breakDeductionMinutes = newDeduction
      newDirtyFields.insert(.breakDeductionMinutes)
    }

    localSnapshot.dirtyFieldKeys = newDirtyFields
    localSnapshot.localUpdatedAt = now

    if !newDirtyFields.isEmpty && localSnapshot.syncStatus == .clean {
      localSnapshot.syncStatus = .dirty
    }

    try modelContext.save()
    return localSnapshot.toWageSnapshot()
  }

  func markWageSnapshotPendingDelete(id: String) throws {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localSnapshot = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localSnapshot.syncStatus = .pendingDelete
    localSnapshot.localUpdatedAt = Date()

    try modelContext.save()
  }

  func resolveStoredWageSnapshotConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localSnapshot = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localSnapshot.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = WageSnapshotServerSnapshot.decode(
        from: localSnapshot.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localSnapshot.serverRevision = serverSnapshot.revision
    localSnapshot.serverUpdatedAt = serverSnapshot.updatedAt
    localSnapshot.syncStatus = .dirty
    localSnapshot.conflictServerSnapshot = nil
    localSnapshot.localUpdatedAt = Date()

    try modelContext.save()
  }

  func resolveStoredWageSnapshotConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localSnapshot = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localSnapshot.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localSnapshot.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = WageSnapshotServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    let dateFormatter = isoDateFormatter

    localSnapshot.fromDate = serverSnapshot.fromDate.flatMap { dateFormatter.date(from: $0) }
    localSnapshot.hourlyWage = serverSnapshot.hourlyWage
    localSnapshot.wageLevel = serverSnapshot.wageLevel
    localSnapshot.supplements = serverSnapshot.supplements
    localSnapshot.taxEnabled = serverSnapshot.taxEnabled
    localSnapshot.taxPercentage = serverSnapshot.taxPercentage
    localSnapshot.breakEnabled = serverSnapshot.breakEnabled
    localSnapshot.breakMethod = serverSnapshot.breakMethod
    localSnapshot.breakThresholdHours = serverSnapshot.breakThresholdHours
    localSnapshot.breakDeductionMinutes = serverSnapshot.breakDeductionMinutes
    localSnapshot.serverRevision = serverSnapshot.revision
    localSnapshot.serverUpdatedAt = serverSnapshot.updatedAt
    localSnapshot.serverDeletedAt = serverSnapshot.deletedAt
    localSnapshot.syncStatus = .clean
    localSnapshot.dirtyFieldKeys = []
    localSnapshot.lastSyncedSnapshot = conflictData
    localSnapshot.conflictServerSnapshot = nil
    localSnapshot.localUpdatedAt = Date()

    try modelContext.save()
  }

  // MARK: - User Settings Operations

  /// Upsert user settings from server data
  func upsertUserSettings(_ settings: LocalUserSettings) throws {
    let settingsUserId = settings.userId
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == settingsUserId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing
      existing.monthlyGoal = settings.monthlyGoal
      existing.monthlyGoalsByMonthData = settings.monthlyGoalsByMonthData
      existing.defaultShiftsView = settings.defaultShiftsView
      existing.profilePictureUrl = settings.profilePictureUrl
      existing.payrollDay = settings.payrollDay
      existing.theme = settings.theme
      existing.halfTaxMonth = settings.halfTaxMonth
      existing.currency = settings.currency
      existing.lastActive = settings.lastActive
      existing.createdAt = settings.createdAt
      existing.serverUpdatedAt = settings.serverUpdatedAt
      existing.serverRevision = settings.serverRevision
      existing.syncStatusRaw = settings.syncStatusRaw
      existing.dirtyFields = settings.dirtyFields
      existing.lastSyncedSnapshot = settings.lastSyncedSnapshot
      existing.localUpdatedAt = settings.localUpdatedAt
      existing.conflictServerSnapshot = settings.conflictServerSnapshot
    } else {
      // Insert new
      modelContext.insert(settings)
    }
  }

  /// Get user settings by user ID
  func getUserSettings(userId: String) throws -> LocalUserSettings? {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get dirty user settings that need to be pushed
  func getDirtyUserSettings(userId: String) throws -> LocalUserSettings? {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { settings in
        settings.userId == userId
          && (settings.syncStatusRaw == "dirty"
            // Include conflict records that were never synced (serverRevision=0)
            // These are new local records that failed initial sync and need INSERT
            || (settings.syncStatusRaw == "conflict" && settings.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor).first
  }

  // MARK: - Local User Settings Write Operations

  /// Create a new local user settings entry
  /// Used during onboarding when no settings exist yet
  func createUserSettings(
    userId: String,
    payrollDay: Int? = nil,
    currency: String? = nil,
    theme: String = "system",
    calendarAnimationStyle: String = "horizontal",
    monthlyGoal: Int? = nil,
    monthlyGoalsByMonth: [String: Int] = [:],
    defaultShiftsView: String? = nil,
    halfTaxMonth: Int? = nil
  ) throws -> UserSettings {
    let now = Date()

    // Build the server snapshot for sync tracking
    let serverSnapshot = UserSettingsServerSnapshot(
      monthlyGoal: monthlyGoal,
      monthlyGoalsByMonth: monthlyGoalsByMonth,
      defaultShiftsView: defaultShiftsView,
      profilePictureUrl: nil,
      payrollDay: payrollDay,
      theme: theme,
      calendarAnimationStyle: calendarAnimationStyle,
      halfTaxMonth: halfTaxMonth,
      currency: currency,
      lastActive: now,
      updatedAt: now,
      revision: 0
    )

    // Track all non-nil fields as dirty so they get pushed to server
    var dirtyFields: [UserSettingsField] = [.theme, .calendarAnimationStyle, .lastActive]
    if payrollDay != nil { dirtyFields.append(.payrollDay) }
    if currency != nil { dirtyFields.append(.currency) }
    if monthlyGoal != nil { dirtyFields.append(.monthlyGoal) }
    if !monthlyGoalsByMonth.isEmpty { dirtyFields.append(.monthlyGoalsByMonth) }
    if defaultShiftsView != nil { dirtyFields.append(.defaultShiftsView) }
    if halfTaxMonth != nil { dirtyFields.append(.halfTaxMonth) }

    let dirtyFieldsData =
      (try? canonicalJSONEncoder.encode(dirtyFields.map { $0.rawValue })) ?? Data()

    let localSettings = LocalUserSettings(
      userId: userId,
      monthlyGoal: monthlyGoal,
      monthlyGoalsByMonthData: (try? canonicalJSONEncoder.encode(monthlyGoalsByMonth))
        ?? Data(),
      defaultShiftsView: defaultShiftsView,
      profilePictureUrl: nil,
      payrollDay: payrollDay,
      theme: theme,
      calendarAnimationStyle: calendarAnimationStyle,
      halfTaxMonth: halfTaxMonth,
      currency: currency,
      lastActive: now,
      createdAt: now,
      serverUpdatedAt: now,
      serverRevision: 0,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: serverSnapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localSettings)
    try modelContext.save()
    return localSettings.toUserSettings()
  }

  /// Get or create user settings for a user
  /// Returns existing settings if found, otherwise creates new settings
  func getOrCreateUserSettings(
    userId: String,
    payrollDay: Int? = nil,
    currency: String? = nil
  ) throws -> UserSettings {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      return existing.toUserSettings()
    }

    // Create new settings
    return try createUserSettings(
      userId: userId,
      payrollDay: payrollDay,
      currency: currency
    )
  }

  // swiftlint:disable:next function_parameter_count
  func updateUserSettings(
    userId: String,
    monthlyGoal: Int?,
    monthlyGoalsByMonth: [String: Int]?,
    defaultShiftsView: String?,
    profilePictureUrl: String?,
    payrollDay: Int?,
    theme: String?,
    calendarAnimationStyle: String?,
    halfTaxMonth: Int?,
    currency: String?
  ) throws -> UserSettings {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let localSettings = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localSettings.dirtyFieldKeys
    let now = Date()

    if let newGoal = monthlyGoal, newGoal != localSettings.monthlyGoal {
      localSettings.monthlyGoal = newGoal
      newDirtyFields.insert(.monthlyGoal)
    }

    if let newMonthlyGoalsByMonth = monthlyGoalsByMonth,
      newMonthlyGoalsByMonth != localSettings.monthlyGoalsByMonth
    {
      localSettings.monthlyGoalsByMonth = newMonthlyGoalsByMonth
      newDirtyFields.insert(.monthlyGoalsByMonth)
    }

    if let newView = defaultShiftsView, newView != localSettings.defaultShiftsView {
      localSettings.defaultShiftsView = newView
      newDirtyFields.insert(.defaultShiftsView)
    }

    if let newUrl = profilePictureUrl, newUrl != localSettings.profilePictureUrl {
      localSettings.profilePictureUrl = newUrl
      newDirtyFields.insert(.profilePictureUrl)
    }

    if let newDay = payrollDay, newDay != localSettings.payrollDay {
      localSettings.payrollDay = newDay
      newDirtyFields.insert(.payrollDay)
    }

    // Theme: Always mark dirty when explicitly set, even if value appears unchanged
    // This handles the case where UserDefaults cache differs from SwiftData
    // (e.g., user changed theme but sync failed, SwiftData has old server value)
    if let newTheme = theme {
      localSettings.theme = newTheme
      newDirtyFields.insert(.theme)
    }

    // Calendar animation style: Same treatment as theme
    if let newStyle = calendarAnimationStyle {
      localSettings.calendarAnimationStyle = newStyle
      newDirtyFields.insert(.calendarAnimationStyle)
    }

    if let newHalfTax = halfTaxMonth, newHalfTax != localSettings.halfTaxMonth {
      localSettings.halfTaxMonth = newHalfTax
      newDirtyFields.insert(.halfTaxMonth)
    }

    if let newCurrency = currency, newCurrency != localSettings.currency {
      localSettings.currency = newCurrency
      newDirtyFields.insert(.currency)
    }

    localSettings.dirtyFieldKeys = newDirtyFields
    localSettings.localUpdatedAt = now

    // Mark as dirty if we have dirty fields and status allows it
    if !newDirtyFields.isEmpty && localSettings.syncStatus == .clean {
      localSettings.syncStatus = .dirty
    }

    try modelContext.save()
    return localSettings.toUserSettings()
  }

  /// Clear the profile picture URL (set to nil)
  /// This is separate from updateUserSettings because Swift optionals can't distinguish
  /// between "not provided" and "explicitly set to nil"
  func clearProfilePictureUrl(userId: String) throws -> UserSettings {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let localSettings = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localSettings.profilePictureUrl = nil
    localSettings.dirtyFieldKeys.insert(.profilePictureUrl)
    localSettings.localUpdatedAt = Date()

    if localSettings.syncStatus == .clean {
      localSettings.syncStatus = .dirty
    }

    try modelContext.save()
    return localSettings.toUserSettings()
  }

  func updateUserSettingsLastActive(userId: String) throws -> Bool {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let localSettings = try modelContext.fetch(descriptor).first else {
      return false
    }

    let now = Date()
    localSettings.lastActive = now
    localSettings.localUpdatedAt = now

    try modelContext.save()
    return true
  }

  func resolveStoredUserSettingsConflictKeepLocal(userId: String) throws {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let localSettings = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localSettings.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = UserSettingsServerSnapshot.decode(
        from: localSettings.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localSettings.serverRevision = serverSnapshot.revision
    localSettings.serverUpdatedAt = serverSnapshot.updatedAt
    localSettings.syncStatus = .dirty
    localSettings.conflictServerSnapshot = nil
    localSettings.localUpdatedAt = Date()

    try modelContext.save()
  }

  func resolveStoredUserSettingsConflictKeepServer(userId: String) throws {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let localSettings = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localSettings.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localSettings.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = UserSettingsServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localSettings.monthlyGoal = serverSnapshot.monthlyGoal
    localSettings.monthlyGoalsByMonth = serverSnapshot.monthlyGoalsByMonth
    localSettings.defaultShiftsView = serverSnapshot.defaultShiftsView
    localSettings.profilePictureUrl = serverSnapshot.profilePictureUrl
    localSettings.payrollDay = serverSnapshot.payrollDay
    localSettings.theme = serverSnapshot.theme
    localSettings.halfTaxMonth = serverSnapshot.halfTaxMonth
    localSettings.currency = serverSnapshot.currency
    localSettings.lastActive = serverSnapshot.lastActive
    localSettings.serverRevision = serverSnapshot.revision
    localSettings.serverUpdatedAt = serverSnapshot.updatedAt
    localSettings.syncStatus = .clean
    localSettings.dirtyFieldKeys = []
    localSettings.lastSyncedSnapshot = conflictData
    localSettings.conflictServerSnapshot = nil
    localSettings.localUpdatedAt = Date()

    try modelContext.save()
  }

  // MARK: - Conflict Helpers

  /// Get all records with conflicts for a user
  func getConflicts(userId: String) throws -> (
    shifts: [LocalUserShift],
    recurringShifts: [LocalRecurringShift],
    wageSnapshots: [LocalWageSnapshot],
    settings: LocalUserSettings?
  ) {
    let shiftsDescriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.syncStatusRaw == "conflict"
      }
    )
    let shifts = try modelContext.fetch(shiftsDescriptor)

    let recurringDescriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.syncStatusRaw == "conflict"
      }
    )
    let recurringShifts = try modelContext.fetch(recurringDescriptor)

    let snapshotsDescriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.userId == userId && snapshot.syncStatusRaw == "conflict"
      }
    )
    let wageSnapshots = try modelContext.fetch(snapshotsDescriptor)

    let settingsDescriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { settings in
        settings.userId == userId && settings.syncStatusRaw == "conflict"
      }
    )
    let settings = try modelContext.fetch(settingsDescriptor).first

    return (shifts, recurringShifts, wageSnapshots, settings)
  }

  /// Check if user has any conflicts
  func hasConflicts(userId: String) throws -> Bool {
    let conflicts = try getConflicts(userId: userId)
    return !conflicts.shifts.isEmpty || !conflicts.recurringShifts.isEmpty
      || !conflicts.wageSnapshots.isEmpty || conflicts.settings != nil
  }

  /// Check if user has any pending changes
  func hasPendingChanges(userId: String) throws -> Bool {
    let dirtyShifts = try getDirtyUserShifts(userId: userId)
    let dirtyRecurring = try getDirtyRecurringShifts(userId: userId)
    let dirtySnapshots = try getDirtyWageSnapshots(userId: userId)
    let dirtySettings = try getDirtyUserSettings(userId: userId)

    return !dirtyShifts.isEmpty || !dirtyRecurring.isEmpty || !dirtySnapshots.isEmpty
      || dirtySettings != nil
  }

  /// Count total conflicts for a user
  func countConflicts(userId: String) throws -> Int {
    let conflicts = try getConflicts(userId: userId)
    return conflicts.shifts.count + conflicts.recurringShifts.count + conflicts.wageSnapshots.count
      + (conflicts.settings != nil ? 1 : 0)
  }

  /// Update sync state with a closure
  func updateSyncState(userId: String, update: (LocalSyncState) -> Void) {
    let descriptor = FetchDescriptor<LocalSyncState>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let state = try? modelContext.fetch(descriptor).first else {
      return
    }

    update(state)
    try? modelContext.save()
  }

  // MARK: - Sync Update Operations for User Shifts

  /// Update a shift from server data (for clean rows)
  func updateShiftFromServer(
    id: String,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    snapshot: UserShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = isoDateFormatter

    existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
    existing.startTime = serverRow.start_time
    existing.endTime = serverRow.end_time
    existing.customSupplements = serverRow.custom_supplements.flatMap {
      try? canonicalJSONEncoder.encode($0)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  /// Mark a shift as having a conflict
  func markShiftConflict(id: String, serverSnapshot: UserShiftServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  /// Update conflict snapshot for a shift already in conflict
  func updateShiftConflictSnapshot(id: String, serverSnapshot: UserShiftServerSnapshot) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  /// Auto-merge a shift (apply server changes for non-dirty fields)
  func autoMergeShift(  // swiftlint:disable:this function_parameter_count
    id: String,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: UserShiftServerSnapshot,
    localDirtyFields: Set<UserShiftField>
  ) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = isoDateFormatter

    // Apply server changes only for non-dirty fields
    if !localDirtyFields.contains(.shiftDate) {
      existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
    }
    if !localDirtyFields.contains(.startTime) {
      existing.startTime = serverRow.start_time
    }
    if !localDirtyFields.contains(.endTime) {
      existing.endTime = serverRow.end_time
    }
    if !localDirtyFields.contains(.customSupplements) {
      existing.customSupplements = serverRow.custom_supplements.flatMap {
        try? canonicalJSONEncoder.encode($0)
      }
    }

    // Update server metadata
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
    // Keep syncStatus = dirty (still needs push)
  }

  // MARK: - Sync Update Operations for Recurring Shifts

  func updateRecurringShiftFromServer(
    id: String,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    snapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.startTime = serverRow.cleanStartTime
    existing.endTime = serverRow.cleanEndTime
    existing.repeatIntervalWeeks = serverRow.repeat_interval_weeks
    existing.selectedDays = (try? canonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
    existing.endCondition = serverRow.end_condition.flatMap { try? canonicalJSONEncoder.encode($0) }
    existing.exclusions = serverRow.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) }
    existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap {
      try? canonicalJSONEncoder.encode($0)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  func markRecurringShiftConflict(id: String, serverSnapshot: RecurringShiftServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  func updateRecurringShiftConflictSnapshot(
    id: String, serverSnapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count
  func autoMergeRecurringShift(
    id: String,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: RecurringShiftServerSnapshot,
    localDirtyFields: Set<RecurringShiftField>
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    if !localDirtyFields.contains(.startTime) {
      existing.startTime = serverRow.cleanStartTime
    }
    if !localDirtyFields.contains(.endTime) {
      existing.endTime = serverRow.cleanEndTime
    }
    if !localDirtyFields.contains(.repeatIntervalWeeks) {
      existing.repeatIntervalWeeks = serverRow.repeat_interval_weeks
    }
    if !localDirtyFields.contains(.selectedDays) {
      existing.selectedDays = (try? canonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
    }
    if !localDirtyFields.contains(.endCondition) {
      existing.endCondition = serverRow.end_condition.flatMap {
        try? canonicalJSONEncoder.encode($0)
      }
    }
    if !localDirtyFields.contains(.exclusions) {
      existing.exclusions = serverRow.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) }
    }
    if !localDirtyFields.contains(.dateSpecificSupplements) {
      existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap {
        try? canonicalJSONEncoder.encode($0)
      }
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
  }

  // MARK: - Sync Update Operations for Wage Snapshots

  func updateWageSnapshotFromServer(
    id: String,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    snapshot: WageSnapshotServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = isoDateFormatter

    existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
    existing.hourlyWage = serverRow.hourly_wage
    existing.wageLevel = serverRow.wage_level
    existing.supplements = (try? canonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
    existing.taxEnabled = serverRow.tax_enabled
    existing.taxPercentage = serverRow.tax_percentage
    existing.breakEnabled = serverRow.break_enabled
    existing.breakMethod = serverRow.break_method
    existing.breakThresholdHours = serverRow.break_threshold_hours
    existing.breakDeductionMinutes = serverRow.break_deduction_minutes
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  func markWageSnapshotConflict(id: String, serverSnapshot: WageSnapshotServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  func updateWageSnapshotConflictSnapshot(id: String, serverSnapshot: WageSnapshotServerSnapshot) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count
  func autoMergeWageSnapshot(
    id: String,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: WageSnapshotServerSnapshot,
    localDirtyFields: Set<WageSnapshotField>
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = isoDateFormatter

    if !localDirtyFields.contains(.fromDate) {
      existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
    }
    if !localDirtyFields.contains(.hourlyWage) {
      existing.hourlyWage = serverRow.hourly_wage
    }
    if !localDirtyFields.contains(.wageLevel) {
      existing.wageLevel = serverRow.wage_level
    }
    if !localDirtyFields.contains(.supplements) {
      existing.supplements = (try? canonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
    }
    if !localDirtyFields.contains(.taxEnabled) {
      existing.taxEnabled = serverRow.tax_enabled
    }
    if !localDirtyFields.contains(.taxPercentage) {
      existing.taxPercentage = serverRow.tax_percentage
    }
    if !localDirtyFields.contains(.breakEnabled) {
      existing.breakEnabled = serverRow.break_enabled
    }
    if !localDirtyFields.contains(.breakMethod) {
      existing.breakMethod = serverRow.break_method
    }
    if !localDirtyFields.contains(.breakThresholdHours) {
      existing.breakThresholdHours = serverRow.break_threshold_hours
    }
    if !localDirtyFields.contains(.breakDeductionMinutes) {
      existing.breakDeductionMinutes = serverRow.break_deduction_minutes
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
  }

  // MARK: - Sync Update Operations for User Settings

  func updateUserSettingsFromServer(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = ISO8601DateFormatter()

    existing.monthlyGoal = serverRow.monthly_goal
    existing.monthlyGoalsByMonth = serverRow.monthly_goals_by_month ?? [:]
    existing.defaultShiftsView = serverRow.default_shifts_view
    existing.profilePictureUrl = serverRow.profile_picture_url
    existing.payrollDay = serverRow.payroll_day
    existing.theme = serverRow.theme
    existing.calendarAnimationStyle = serverRow.calendar_animation_style
    existing.halfTaxMonth = serverRow.half_tax_month
    existing.currency = serverRow.currency
    existing.lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
    existing.createdAt = serverRow.created_at.flatMap { dateFormatter.date(from: $0) }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  func markUserSettingsConflict(userId: String, serverSnapshot: UserSettingsServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  func updateUserSettingsConflictSnapshot(
    userId: String, serverSnapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  func autoMergeUserSettings(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    newSnapshot: UserSettingsServerSnapshot,
    localDirtyFields: Set<UserSettingsField>
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = ISO8601DateFormatter()

    if !localDirtyFields.contains(.monthlyGoal) {
      existing.monthlyGoal = serverRow.monthly_goal
    }
    if !localDirtyFields.contains(.monthlyGoalsByMonth) {
      existing.monthlyGoalsByMonth = serverRow.monthly_goals_by_month ?? [:]
    }
    if !localDirtyFields.contains(.defaultShiftsView) {
      existing.defaultShiftsView = serverRow.default_shifts_view
    }
    if !localDirtyFields.contains(.profilePictureUrl) {
      existing.profilePictureUrl = serverRow.profile_picture_url
    }
    if !localDirtyFields.contains(.payrollDay) {
      existing.payrollDay = serverRow.payroll_day
    }
    if !localDirtyFields.contains(.theme) {
      existing.theme = serverRow.theme
    }
    if !localDirtyFields.contains(.calendarAnimationStyle) {
      existing.calendarAnimationStyle = serverRow.calendar_animation_style
    }
    if !localDirtyFields.contains(.halfTaxMonth) {
      existing.halfTaxMonth = serverRow.half_tax_month
    }
    if !localDirtyFields.contains(.currency) {
      existing.currency = serverRow.currency
    }
    if !localDirtyFields.contains(.lastActive) {
      existing.lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.lastSyncedSnapshot = newSnapshot.encoded()
  }

  // MARK: - Push Operations for User Shifts

  /// Mark a shift as successfully pushed (clean)
  func markShiftPushed(
    id: String,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: UserShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = isoDateFormatter

    // Update with canonical server values
    existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
    existing.startTime = serverRow.start_time
    existing.endTime = serverRow.end_time
    existing.customSupplements = serverRow.custom_supplements.flatMap {
      try? canonicalJSONEncoder.encode($0)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  /// Mark a shift as clean (no dirty fields)
  func markShiftClean(id: String) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  /// Mark a shift as successfully deleted
  func markShiftDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  /// Rebase a shift (update server metadata, keep local dirty fields)
  func rebaseShift(  // swiftlint:disable:this function_parameter_count
    id: String,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: UserShiftServerSnapshot,
    localDirtyFields: Set<UserShiftField>
  ) {
    // Same as autoMergeShift - apply server changes for non-dirty fields
    autoMergeShift(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newSnapshot,
      localDirtyFields: localDirtyFields
    )
  }

  /// Resolve shift conflict by keeping server version
  func resolveShiftConflictKeepServer(id: String, serverSnapshot: UserShiftServerSnapshot) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = isoDateFormatter

    // Overwrite local with server snapshot
    existing.shiftDate = dateFormatter.date(from: serverSnapshot.shiftDate) ?? existing.shiftDate
    existing.startTime = serverSnapshot.startTime
    existing.endTime = serverSnapshot.endTime
    existing.customSupplements = serverSnapshot.customSupplements
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.serverDeletedAt = serverSnapshot.deletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  /// Resolve shift conflict by keeping local version (prepare for push)
  func resolveShiftConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    // Update server revision so next push uses correct revision
    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
    // Keep dirtyFieldKeys - they contain the fields we want to push
  }

  // MARK: - Push Operations for Recurring Shifts

  func markRecurringShiftPushed(
    id: String,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.startTime = serverRow.cleanStartTime
    existing.endTime = serverRow.cleanEndTime
    existing.repeatIntervalWeeks = serverRow.repeat_interval_weeks
    existing.selectedDays = (try? canonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
    existing.endCondition = serverRow.end_condition.flatMap { try? canonicalJSONEncoder.encode($0) }
    existing.exclusions = serverRow.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) }
    existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap {
      try? canonicalJSONEncoder.encode($0)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  func markRecurringShiftClean(id: String) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  func markRecurringShiftDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  func rebaseRecurringShift(
    id: String,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: RecurringShiftServerSnapshot,
    localDirtyFields: Set<RecurringShiftField>
  ) {
    autoMergeRecurringShift(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newSnapshot,
      localDirtyFields: localDirtyFields
    )
  }

  func resolveRecurringShiftConflictKeepServer(
    id: String, serverSnapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.startTime = serverSnapshot.startTime
    existing.endTime = serverSnapshot.endTime
    existing.repeatIntervalWeeks = serverSnapshot.repeatIntervalWeeks
    existing.selectedDays = serverSnapshot.selectedDays
    existing.endCondition = serverSnapshot.endCondition
    existing.exclusions = serverSnapshot.exclusions
    existing.dateSpecificSupplements = serverSnapshot.dateSpecificSupplements
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.serverDeletedAt = serverSnapshot.deletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  func resolveRecurringShiftConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Push Operations for Wage Snapshots

  func markWageSnapshotPushed(
    id: String,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: WageSnapshotServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = isoDateFormatter

    existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
    existing.hourlyWage = serverRow.hourly_wage
    existing.wageLevel = serverRow.wage_level
    existing.supplements = (try? canonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
    existing.taxEnabled = serverRow.tax_enabled
    existing.taxPercentage = serverRow.tax_percentage
    existing.breakEnabled = serverRow.break_enabled
    existing.breakMethod = serverRow.break_method
    existing.breakThresholdHours = serverRow.break_threshold_hours
    existing.breakDeductionMinutes = serverRow.break_deduction_minutes
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  func markWageSnapshotClean(id: String) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  func markWageSnapshotDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  func rebaseWageSnapshot(
    id: String,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: WageSnapshotServerSnapshot,
    localDirtyFields: Set<WageSnapshotField>
  ) {
    autoMergeWageSnapshot(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newSnapshot,
      localDirtyFields: localDirtyFields
    )
  }

  func resolveWageSnapshotConflictKeepServer(id: String, serverSnapshot: WageSnapshotServerSnapshot)
  {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = isoDateFormatter

    existing.fromDate = serverSnapshot.fromDate.flatMap { dateFormatter.date(from: $0) }
    existing.hourlyWage = serverSnapshot.hourlyWage
    existing.wageLevel = serverSnapshot.wageLevel
    existing.supplements = serverSnapshot.supplements
    existing.taxEnabled = serverSnapshot.taxEnabled
    existing.taxPercentage = serverSnapshot.taxPercentage
    existing.breakEnabled = serverSnapshot.breakEnabled
    existing.breakMethod = serverSnapshot.breakMethod
    existing.breakThresholdHours = serverSnapshot.breakThresholdHours
    existing.breakDeductionMinutes = serverSnapshot.breakDeductionMinutes
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.serverDeletedAt = serverSnapshot.deletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  func resolveWageSnapshotConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Push Operations for User Settings

  func markUserSettingsPushed(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    let dateFormatter = ISO8601DateFormatter()

    existing.monthlyGoal = serverRow.monthly_goal
    existing.monthlyGoalsByMonth = serverRow.monthly_goals_by_month ?? [:]
    existing.defaultShiftsView = serverRow.default_shifts_view
    existing.profilePictureUrl = serverRow.profile_picture_url
    existing.payrollDay = serverRow.payroll_day
    existing.theme = serverRow.theme
    existing.halfTaxMonth = serverRow.half_tax_month
    existing.currency = serverRow.currency
    existing.lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
    existing.createdAt = serverRow.created_at.flatMap { dateFormatter.date(from: $0) }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  func markUserSettingsClean(userId: String) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  func rebaseUserSettings(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    newSnapshot: UserSettingsServerSnapshot,
    localDirtyFields: Set<UserSettingsField>
  ) {
    autoMergeUserSettings(
      userId: userId,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      newSnapshot: newSnapshot,
      localDirtyFields: localDirtyFields
    )
  }

  func resolveUserSettingsConflictKeepServer(
    userId: String, serverSnapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.monthlyGoal = serverSnapshot.monthlyGoal
    existing.monthlyGoalsByMonth = serverSnapshot.monthlyGoalsByMonth
    existing.defaultShiftsView = serverSnapshot.defaultShiftsView
    existing.profilePictureUrl = serverSnapshot.profilePictureUrl
    existing.payrollDay = serverSnapshot.payrollDay
    existing.theme = serverSnapshot.theme
    existing.halfTaxMonth = serverSnapshot.halfTaxMonth
    existing.currency = serverSnapshot.currency
    existing.lastActive = serverSnapshot.lastActive
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  func resolveUserSettingsConflictKeepLocal(userId: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else { return }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Entitlement Cache Operations

  /// Upsert entitlement cache from server entitlement
  func upsertEntitlementCache(userId: String, entitlement: ServerEntitlement) throws {
    let descriptor = FetchDescriptor<LocalEntitlementCache>(
      predicate: #Predicate { $0.userId == userId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing cache
      existing.update(from: entitlement)
    } else {
      // Insert new cache entry
      let cache = LocalEntitlementCache(userId: userId, entitlement: entitlement)
      modelContext.insert(cache)
    }

    try modelContext.save()
  }

  /// Delete entitlement cache for a user (on logout)
  func deleteEntitlementCache(userId: String) throws {
    let descriptor = FetchDescriptor<LocalEntitlementCache>(
      predicate: #Predicate { $0.userId == userId }
    )

    for cache in try modelContext.fetch(descriptor) {
      modelContext.delete(cache)
    }

    try modelContext.save()
  }

  // MARK: - JWS Upload Queue Operations

  /// Insert pending JWS upload (upsert by transactionId)
  /// Since transactionId is unique, attempting to insert a duplicate will be skipped
  func insertPendingJWSUpload(_ upload: LocalPendingJWSUpload) throws {
    // Check if already exists (don't reset attempt count for existing entries)
    let transactionId = upload.transactionId
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
      predicate: #Predicate { $0.transactionId == transactionId }
    )

    if try modelContext.fetch(descriptor).first != nil {
      // Already queued - skip to avoid resetting retry state
      return
    }

    modelContext.insert(upload)
    try modelContext.save()
  }

  /// Delete pending JWS upload after successful upload
  func deletePendingJWSUpload(transactionId: String) throws {
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
      predicate: #Predicate { $0.transactionId == transactionId }
    )

    for upload in try modelContext.fetch(descriptor) {
      modelContext.delete(upload)
    }

    try modelContext.save()
  }

  /// Schedule next retry for a failed upload (exponential backoff)
  func schedulePendingJWSUploadRetry(transactionId: String) throws {
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
      predicate: #Predicate { $0.transactionId == transactionId }
    )

    if let upload = try modelContext.fetch(descriptor).first {
      upload.scheduleNextRetry()
      try modelContext.save()
    }
  }

  // MARK: - Shared Shifts Operations

  /// Save sharers to cache, replacing existing entries for this viewer
  func saveSharers(_ sharers: [SharedUser], for viewerId: String) throws {
    // Delete existing sharers for this viewer
    let descriptor = FetchDescriptor<LocalSharer>(
      predicate: #Predicate { $0.viewerId == viewerId }
    )
    for existing in try modelContext.fetch(descriptor) {
      modelContext.delete(existing)
    }

    // Insert new sharers
    for sharer in sharers {
      let localSharer = LocalSharer.from(sharedUser: sharer, viewerId: viewerId)
      modelContext.insert(localSharer)
    }

    try modelContext.save()
  }

  /// Save shared shifts to cache, replacing existing entries for this owner/month
  /// - Parameters:
  ///   - shifts: Array of SharedShiftData from API
  ///   - ownerId: The owner's user ID
  ///   - viewerId: The current user's ID
  ///   - showEarnings: Whether earnings are visible for this share
  ///   - year: Year
  ///   - month: Month (1-12)
  ///   - forceReplace: If true, replace cache even when new data is empty (default false)
  func saveSharedShifts(
    _ shifts: [SharedShiftData],
    ownerId: String,
    viewerId: String,
    showEarnings: Bool,
    year: Int,
    month: Int,
    forceReplace: Bool = false
  ) throws {
    // Fetch existing shifts for this owner/viewer/month
    let descriptor = FetchDescriptor<LocalSharedShift>(
      predicate: #Predicate { shift in
        shift.ownerId == ownerId && shift.viewerId == viewerId && shift.year == year
          && shift.month == month
      }
    )
    let existing = try modelContext.fetch(descriptor)

    // Don't delete existing cached data if new data is empty (unless forced)
    // This prevents data loss when the API returns an empty array due to errors
    if shifts.isEmpty && !existing.isEmpty && !forceReplace {
      logger.warning(
        "API returned empty shared shifts for \(year)-\(month) (owner: \(ownerId.prefix(8))...), keeping \(existing.count) cached shifts"
      )
      return
    }

    // Delete existing shifts
    for item in existing {
      modelContext.delete(item)
    }

    // Insert new shifts
    for shift in shifts {
      let localShift = LocalSharedShift.from(
        apiShift: shift,
        ownerId: ownerId,
        viewerId: viewerId,
        showEarnings: showEarnings
      )
      modelContext.insert(localShift)
    }

    // Upsert fetch record so we know this month was fetched (even if empty)
    let fetchRecordKey = "\(viewerId):\(ownerId):\(year):\(month)"
    let fetchRecordDescriptor = FetchDescriptor<LocalSharedShiftFetchRecord>(
      predicate: #Predicate { $0.compositeKey == fetchRecordKey }
    )
    let existingRecords = try modelContext.fetch(fetchRecordDescriptor)
    for record in existingRecords {
      modelContext.delete(record)
    }
    modelContext.insert(
      LocalSharedShiftFetchRecord(
        ownerId: ownerId,
        viewerId: viewerId,
        year: year,
        month: month,
        shiftCount: shifts.count
      )
    )

    try modelContext.save()
  }

  /// Clear all shared data for a viewer
  func clearSharedData(for viewerId: String) throws {
    // Clear sharers
    let sharerDescriptor = FetchDescriptor<LocalSharer>(
      predicate: #Predicate { $0.viewerId == viewerId }
    )
    for sharer in try modelContext.fetch(sharerDescriptor) {
      modelContext.delete(sharer)
    }

    // Clear shared shifts
    let shiftDescriptor = FetchDescriptor<LocalSharedShift>(
      predicate: #Predicate { $0.viewerId == viewerId }
    )
    for shift in try modelContext.fetch(shiftDescriptor) {
      modelContext.delete(shift)
    }

    // Clear shift previews
    let previewDescriptor = FetchDescriptor<LocalShiftPreview>(
      predicate: #Predicate { $0.viewerId == viewerId }
    )
    for preview in try modelContext.fetch(previewDescriptor) {
      modelContext.delete(preview)
    }

    // Clear fetch records
    let fetchRecordDescriptor = FetchDescriptor<LocalSharedShiftFetchRecord>(
      predicate: #Predicate { $0.viewerId == viewerId }
    )
    for record in try modelContext.fetch(fetchRecordDescriptor) {
      modelContext.delete(record)
    }

    try modelContext.save()
  }

  /// Clear shared shifts for a specific owner
  func clearSharedShifts(ownerId: String, viewerId: String) throws {
    let descriptor = FetchDescriptor<LocalSharedShift>(
      predicate: #Predicate { shift in
        shift.ownerId == ownerId && shift.viewerId == viewerId
      }
    )
    for shift in try modelContext.fetch(descriptor) {
      modelContext.delete(shift)
    }

    // Clear fetch records for this owner
    let fetchRecordDescriptor = FetchDescriptor<LocalSharedShiftFetchRecord>(
      predicate: #Predicate { record in
        record.ownerId == ownerId && record.viewerId == viewerId
      }
    )
    for record in try modelContext.fetch(fetchRecordDescriptor) {
      modelContext.delete(record)
    }

    try modelContext.save()
  }

  // MARK: - Shift Preview Operations

  /// Save shift previews to cache, replacing existing entries for this viewer
  func saveShiftPreviews(_ previews: [SharerShiftPreview], for viewerId: String) throws {
    // Delete existing previews for this viewer (only for sharers in this batch)
    let sharerIds = previews.map { $0.sharerId }
    for sharerId in sharerIds {
      let compositeKey = "\(viewerId):\(sharerId)"
      let descriptor = FetchDescriptor<LocalShiftPreview>(
        predicate: #Predicate { $0.compositeKey == compositeKey }
      )
      for existing in try modelContext.fetch(descriptor) {
        modelContext.delete(existing)
      }
    }

    // Insert new previews
    for preview in previews {
      let localPreview = LocalShiftPreview.from(preview: preview, viewerId: viewerId)
      modelContext.insert(localPreview)
    }

    try modelContext.save()
  }
}
