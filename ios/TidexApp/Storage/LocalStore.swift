// swiftlint:disable explicit_type_interface file_length sorted_imports type_body_length
// swiftlint:disable:previous blanket_disable_command
import Foundation
import SwiftData
import os.log

private let kLocalStoreLogger = Logger(subsystem: "com.tidex.app", category: "LocalStore")
private let kLogIdentifierPrefixLength = 8

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

  /// Indicates if the store fell back to in-memory storage due to persistent storage failure.
  /// When true, data will NOT be saved between app launches - user should be warned.
  internal let isUsingInMemoryFallback: Bool

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

  private init() {
    Self.ensureStoreParentDirectoryExists()

    // Create schema with all local models
    let schema = Schema([
      LocalJob.self,
      LocalUserShift.self,
      LocalEvent.self,
      LocalRecurringShift.self,
      LocalWageSnapshot.self,
      LocalPayrollAdjustment.self,
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
      LocalPendingFriendComposerDraft.self,
      LocalThread.self,
      LocalThreadState.self,
      LocalThreadFeedPlacement.self,
      LocalMessage.self,
      LocalMessageAttachment.self,
      LocalMessageReaction.self,
      LocalFriendMessagingSyncState.self,
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
      kLocalStoreLogger.info("LocalStore initialized successfully")
    } catch {
      kLocalStoreLogger.error("Failed to initialize LocalStore: \(error.localizedDescription)")

      // Try to recover by creating an in-memory container as fallback
      // This allows the app to function (without persistence) rather than crash
      kLocalStoreLogger.warning("Attempting fallback to in-memory storage")
      let fallbackConfig = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        allowsSave: true
      )

      do {
        container = try ModelContainer(for: schema, configurations: [fallbackConfig])
        storeActor = LocalStoreActor(modelContainer: container)
        isUsingInMemoryFallback = true
        kLocalStoreLogger.warning(
          "LocalStore initialized with in-memory fallback - data will not persist")
      } catch {
        let fallbackError: Error = error
        // This should essentially never happen - in-memory containers rarely fail
        // But we need to initialize the properties, so create a minimal container
        kLocalStoreLogger.critical(
          "Failed to create even in-memory storage: \(fallbackError.localizedDescription)"
        )

        // Last resort: try with default configuration
        // If this fails, there's a fundamental issue with the app's model definitions
        do {
          container = try ModelContainer(for: schema)
          storeActor = LocalStoreActor(modelContainer: container)
          isUsingInMemoryFallback = true
          kLocalStoreLogger.critical("LocalStore using default container - app may be unstable")
        } catch {
          let lastResortError: Error = error
          fatalError(
            """
            LocalStore: All storage initialization attempts failed.
            Original error: \(error.localizedDescription)
            In-memory fallback error: \(fallbackError.localizedDescription)
            Default container error: \(lastResortError.localizedDescription)
            This indicates a fundamental issue with the app's SwiftData model definitions.
            """
          )
        }
      }
    }
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
  private let isoDateFormatter: DateFormatter = FormatterCache.isoDateFormatter(
    timeZone: Date.localTimeZone
  )

  /// Delete all data from all tables
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
      try modelContext.delete(model: LocalEntitlementCache.self)
      try modelContext.delete(model: LocalPendingJWSUpload.self)
      try modelContext.delete(model: LocalSharedShift.self)
      try modelContext.delete(model: LocalSharer.self)
      try modelContext.delete(model: LocalShiftPreview.self)
      try modelContext.delete(model: LocalSharedShiftFetchRecord.self)
      try modelContext.delete(model: LocalConversation.self)
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

  // MARK: - Read Operations (Local Only)

  internal func fetchUserSettings(userId: String) -> UserSettings? {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    do {
      guard let localSettings = try modelContext.fetch(descriptor).first else {
        return nil
      }
      return localSettings.toUserSettings()
    } catch {
      kLocalStoreLogger.error("Failed to fetch settings: \(error.localizedDescription)")
      return nil
    }
  }

  private func shouldIncludeLegacyNilJobRows(userId: String, selectedJobId: String) -> Bool {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
          && job.deletedAt == nil
          && job.archivedAt == nil
          && job.isDefault == true
      }
    )

    do {
      guard let defaultJob = try modelContext.fetch(descriptor).first else {
        return false
      }
      return defaultJob.id == selectedJobId
    } catch {
      kLocalStoreLogger.error(
        "Failed to determine default job for legacy fallback: \(error.localizedDescription)"
      )
      return false
    }
  }

  internal func fetchSnapshots(  // swiftlint:disable:this function_body_length
    userId: String,
    jobId: String? = nil
  ) -> [WageSnapshot] {
    let sortDescriptors: [SortDescriptor<LocalWageSnapshot>] = [
      SortDescriptor(\LocalWageSnapshot.fromDate, order: .reverse)
    ]

    if let jobId {
      let primaryDescriptor = FetchDescriptor<LocalWageSnapshot>(
        predicate: #Predicate { snapshot in
          snapshot.userId == userId && snapshot.serverDeletedAt == nil
            && snapshot.syncStatusRaw != "pendingDelete" && snapshot.jobId == jobId
        },
        sortBy: sortDescriptors
      )

      do {
        var localSnapshots: [LocalWageSnapshot] = try modelContext.fetch(primaryDescriptor)

        if shouldIncludeLegacyNilJobRows(userId: userId, selectedJobId: jobId) {
          let legacyDescriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { snapshot in
              snapshot.userId == userId && snapshot.serverDeletedAt == nil
                && snapshot.syncStatusRaw != "pendingDelete" && snapshot.jobId == nil
            },
            sortBy: sortDescriptors
          )
          localSnapshots.append(contentsOf: try modelContext.fetch(legacyDescriptor))
          localSnapshots.sort { lhs, rhs in
            switch (lhs.fromDate, rhs.fromDate) {
            case (let leftDate?, let rightDate?):  // swiftlint:disable:this pattern_matching_keywords
              return leftDate > rightDate

            case (_?, nil):
              return true

            case (nil, _?):
              return false

            case (nil, nil):
              return lhs.localUpdatedAt > rhs.localUpdatedAt
            }
          }
        }

        return localSnapshots.map { $0.toWageSnapshot() }
      } catch {
        kLocalStoreLogger.error("Failed to fetch snapshots: \(error.localizedDescription)")
        return []
      }
    }

    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.userId == userId && snapshot.serverDeletedAt == nil
          && snapshot.syncStatusRaw != "pendingDelete"
      },
      sortBy: sortDescriptors
    )

    do {
      let localSnapshots = try modelContext.fetch(descriptor)
      return localSnapshots.map { $0.toWageSnapshot() }
    } catch {
      kLocalStoreLogger.error("Failed to fetch snapshots: \(error.localizedDescription)")
      return []
    }
  }

  internal func fetchRecurringShifts(
    userId: String,
    jobId: String? = nil
  ) -> [RecurringShiftRow] {
    if let jobId {
      let selectedJobDescriptor = FetchDescriptor<LocalRecurringShift>(
        predicate: #Predicate { shift in
          shift.userId == userId && shift.serverDeletedAt == nil
            && shift.syncStatusRaw != "pendingDelete" && shift.jobId == jobId
        },
        sortBy: [SortDescriptor(\LocalRecurringShift.localUpdatedAt, order: .reverse)]
      )

      do {
        var localRecurring = try modelContext.fetch(selectedJobDescriptor)

        if shouldIncludeLegacyNilJobRows(userId: userId, selectedJobId: jobId) {
          let legacyNilDescriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { shift in
              shift.userId == userId && shift.serverDeletedAt == nil
                && shift.syncStatusRaw != "pendingDelete" && shift.jobId == nil
            },
            sortBy: [SortDescriptor(\LocalRecurringShift.localUpdatedAt, order: .reverse)]
          )
          localRecurring.append(contentsOf: try modelContext.fetch(legacyNilDescriptor))
        }

        return localRecurring.map { $0.toRecurringShiftRow() }
      } catch {
        kLocalStoreLogger.error("Failed to fetch recurring shifts: \(error.localizedDescription)")
        return []
      }
    }

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
      kLocalStoreLogger.error("Failed to fetch recurring shifts: \(error.localizedDescription)")
      return []
    }
  }

  internal func fetchShifts(
    userId: String,
    startDate: Date,
    endDate: Date,
    jobId: String? = nil
  ) -> [ShiftRow] {
    let includeLegacyNil =
      jobId.map {
        shouldIncludeLegacyNilJobRows(userId: userId, selectedJobId: $0)
      } ?? false
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
          && shift.syncStatusRaw != "pendingDelete" && shift.shiftDate >= startDate
          && shift.shiftDate <= endDate
          && (jobId == nil || shift.jobId == jobId || (includeLegacyNil && shift.jobId == nil))
      },
      sortBy: [SortDescriptor(\LocalUserShift.shiftDate, order: .reverse)]
    )

    do {
      let localShifts: [LocalUserShift] = try modelContext.fetch(descriptor)
      return localShifts.map { $0.toShiftRow() }
    } catch {
      kLocalStoreLogger.error("Failed to fetch shifts: \(error.localizedDescription)")
      return []
    }
  }

  internal func fetchEvents(userId: String, startDate: Date, endDate: Date) -> [EventRow] {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { event in
        event.userId == userId && event.serverDeletedAt == nil
          && event.syncStatusRaw != "pendingDelete"
          && event.endDate >= startDate
          && event.startDate <= endDate
      },
      sortBy: [
        SortDescriptor(\LocalEvent.startDate, order: .forward),
        SortDescriptor(\LocalEvent.endDate, order: .forward),
      ]
    )

    do {
      let localEvents = try modelContext.fetch(descriptor)
      return localEvents.map { $0.toEventRow() }
    } catch {
      kLocalStoreLogger.error("Failed to fetch events: \(error.localizedDescription)")
      return []
    }
  }

  internal func fetchAllEvents(userId: String) -> [EventRow] {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { event in
        event.userId == userId && event.serverDeletedAt == nil
          && event.syncStatusRaw != "pendingDelete"
      },
      sortBy: [
        SortDescriptor(\LocalEvent.startDate, order: .forward),
        SortDescriptor(\LocalEvent.endDate, order: .forward),
      ]
    )

    do {
      return try modelContext.fetch(descriptor).map { $0.toEventRow() }
    } catch {
      return []
    }
  }

  // MARK: - Sync State Operations

  /// Get or create sync state for a user
  internal func getOrCreateSyncState(userId: String) throws -> LocalSyncState {
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
  internal func getSyncState(userId: String) throws -> LocalSyncState? {
    let descriptor = FetchDescriptor<LocalSyncState>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor).first
  }

  // MARK: - User Shift Operations

  // MARK: - Jobs Operations

  internal func fetchNonDeletedJobs(userId: String) -> [Job] {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
      },
      sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
    )

    do {
      return try modelContext.fetch(descriptor)
        .filter { job in
          if job.syncStatusRaw == "pendingDelete" {
            return false
          }
          return job.deletedAt == nil
        }
        .map { $0.toJob() }
    } catch {
      kLocalStoreLogger.error("Failed to fetch jobs: \(error.localizedDescription)")
      return []
    }
  }

  /// Upsert a job from server data
  internal func upsertJob(_ job: LocalJob) throws {
    let jobId = job.id
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == jobId }
    )
    let existing = try modelContext.fetch(descriptor).first

    if let existing {
      existing.userId = job.userId
      existing.name = job.name
      existing.color = job.color
      existing.currency = job.currency
      existing.isDefault = job.isDefault
      existing.sortOrder = job.sortOrder
      existing.payrollDay = job.payrollDay
      existing.halfTaxMonth = job.halfTaxMonth
      existing.monthlyGoal = job.monthlyGoal
      existing.archivedAt = job.archivedAt
      existing.deletedAt = job.deletedAt
      existing.createdAt = job.createdAt
      existing.serverUpdatedAt = job.serverUpdatedAt
      existing.serverRevision = job.serverRevision
      existing.syncStatusRaw = job.syncStatusRaw
      existing.dirtyFields = job.dirtyFields
      existing.lastSyncedSnapshot = job.lastSyncedSnapshot
      existing.localUpdatedAt = job.localUpdatedAt
      existing.conflictServerSnapshot = job.conflictServerSnapshot
    } else {
      modelContext.insert(job)
    }
  }

  internal func getJob(id: String) throws -> LocalJob? {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  internal func getAllJobs(userId: String) throws -> [LocalJob] {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty jobs that need to be pushed
  internal func getDirtyJobs(userId: String) throws -> [LocalJob] {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
          && (job.syncStatusRaw == "dirty" || job.syncStatusRaw == "pendingDelete"
            || (job.syncStatusRaw == "conflict" && job.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor)
  }

  internal func hasDirtyJobs(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
          && (job.syncStatusRaw == "dirty" || job.syncStatusRaw == "pendingDelete"
            || (job.syncStatusRaw == "conflict" && job.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local Job Write Operations

  // swiftlint:disable:next function_parameter_count
  internal func createJob(
    userId: String,
    name: String,
    color: String?,
    currency: String,
    isDefault: Bool,
    sortOrder: Int,
    payrollDay: Int?,
    halfTaxMonth: Int?,
    monthlyGoal: Int?
  ) throws -> Job {
    let id = UUID().lowercasedString
    let now = Date()
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

    if isDefault {
      let existingDescriptor = FetchDescriptor<LocalJob>(
        predicate: #Predicate { job in
          job.userId == userId && job.deletedAt == nil && job.archivedAt == nil
        }
      )
      let existingJobs = try modelContext.fetch(existingDescriptor)
      for existing in existingJobs where existing.isDefault {
        existing.isDefault = false
        existing.dirtyFieldKeys.insert(.isDefault)
        existing.localUpdatedAt = now
        if existing.syncStatus == .clean {
          existing.syncStatus = .dirty
        }
      }
    }

    let serverSnapshot = JobServerSnapshot(
      name: trimmedName,
      color: color,
      currency: currency,
      isDefault: isDefault,
      sortOrder: sortOrder,
      payrollDay: payrollDay,
      halfTaxMonth: halfTaxMonth,
      monthlyGoal: monthlyGoal,
      archivedAt: nil,
      deletedAt: nil,
      updatedAt: now,
      revision: 0
    )

    let dirtyFieldsData =
      (try? kCanonicalJSONEncoder.encode(JobField.allCases.map(\.rawValue)))
      ?? Data()

    let localJob = LocalJob(
      id: id,
      userId: userId,
      name: trimmedName,
      color: color,
      currency: currency,
      isDefault: isDefault,
      sortOrder: sortOrder,
      payrollDay: payrollDay,
      halfTaxMonth: halfTaxMonth,
      monthlyGoal: monthlyGoal,
      archivedAt: nil,
      deletedAt: nil,
      createdAt: now,
      serverUpdatedAt: now,
      serverRevision: 0,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: serverSnapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localJob)
    try modelContext.save()
    return localJob.toJob()
  }

  internal func updateJobMetadata(
    id: String,
    name: String,
    color: String?
  ) throws -> Job {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localJob.dirtyFieldKeys
    let now = Date()
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

    if localJob.name != trimmedName {
      localJob.name = trimmedName
      newDirtyFields.insert(.name)
    }

    if localJob.color != color {
      localJob.color = color
      newDirtyFields.insert(.color)
    }

    localJob.dirtyFieldKeys = newDirtyFields
    localJob.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.toJob()
  }

  internal func updateJobCurrency(
    id: String,
    currency: String
  ) throws -> Job {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localJob.currency != currency else {
      return localJob.toJob()
    }

    var newDirtyFields = localJob.dirtyFieldKeys
    let now = Date()

    localJob.currency = currency
    newDirtyFields.insert(.currency)
    localJob.dirtyFieldKeys = newDirtyFields
    localJob.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.toJob()
  }

  internal func updateJobPaySettings(
    id: String,
    payrollDay: Int,
    halfTaxMonth: Int?,
    monthlyGoal: Int?
  ) throws -> Job {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localJob.dirtyFieldKeys
    let now = Date()

    if localJob.payrollDay != payrollDay {
      localJob.payrollDay = payrollDay
      newDirtyFields.insert(.payrollDay)
    }

    if localJob.halfTaxMonth != halfTaxMonth {
      localJob.halfTaxMonth = halfTaxMonth
      newDirtyFields.insert(.halfTaxMonth)
    }

    if localJob.monthlyGoal != monthlyGoal {
      localJob.monthlyGoal = monthlyGoal
      newDirtyFields.insert(.monthlyGoal)
    }

    localJob.dirtyFieldKeys = newDirtyFields
    localJob.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.toJob()
  }

  internal func setJobDefault(userId: String, jobId: String) throws {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId && job.deletedAt == nil && job.archivedAt == nil
      }
    )
    let jobs = try modelContext.fetch(descriptor)
    let now = Date()

    for job in jobs {
      let shouldBeDefault = job.id == jobId
      guard job.isDefault != shouldBeDefault else { continue }
      job.isDefault = shouldBeDefault
      job.dirtyFieldKeys.insert(.isDefault)
      job.localUpdatedAt = now
      if job.syncStatus == .clean {
        job.syncStatus = .dirty
      }
    }

    try modelContext.save()
  }

  internal func archiveJob(id: String, archivedAt: Date = Date()) throws -> String {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )
    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localJob.archivedAt = archivedAt
    localJob.isDefault = false
    localJob.dirtyFieldKeys.insert(.archivedAt)
    localJob.dirtyFieldKeys.insert(.isDefault)
    localJob.localUpdatedAt = archivedAt
    if localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.userId
  }

  internal func restoreJob(id: String, sortOrder: Int) throws -> String {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )
    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let now = Date()
    localJob.archivedAt = nil
    localJob.sortOrder = sortOrder
    localJob.dirtyFieldKeys.insert(.archivedAt)
    localJob.dirtyFieldKeys.insert(.sortOrder)
    localJob.localUpdatedAt = now
    if localJob.syncStatus == .clean {
      localJob.syncStatus = .dirty
    }

    try modelContext.save()
    return localJob.userId
  }

  internal func reorderJobs(userId: String, orderedJobIds: [String]) throws {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId && job.deletedAt == nil && job.archivedAt == nil
      }
    )

    let jobs = try modelContext.fetch(descriptor)
    let now = Date()
    let orderById = Dictionary(uniqueKeysWithValues: orderedJobIds.enumerated().map { ($1, $0) })

    for job in jobs {
      guard let newOrder = orderById[job.id], job.sortOrder != newOrder else { continue }
      job.sortOrder = newOrder
      job.dirtyFieldKeys.insert(.sortOrder)
      job.localUpdatedAt = now
      if job.syncStatus == .clean {
        job.syncStatus = .dirty
      }
    }

    try modelContext.save()
  }

  internal func markJobPendingDelete(id: String) throws -> String {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let now = Date()
    localJob.deletedAt = now
    localJob.isDefault = false
    localJob.syncStatus = .pendingDelete
    localJob.dirtyFieldKeys.insert(.deletedAt)
    localJob.dirtyFieldKeys.insert(.isDefault)
    localJob.localUpdatedAt = now

    try modelContext.save()
    return localJob.userId
  }

  internal func resolveStoredJobConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localJob.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = JobServerSnapshot.decode(
        from: localJob.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localJob.serverRevision = serverSnapshot.revision
    localJob.serverUpdatedAt = serverSnapshot.updatedAt
    localJob.syncStatus = .dirty
    localJob.conflictServerSnapshot = nil
    localJob.localUpdatedAt = Date()

    try modelContext.save()
  }

  internal func resolveStoredJobConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localJob = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localJob.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localJob.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = JobServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localJob.name = serverSnapshot.name
    localJob.color = serverSnapshot.color
    localJob.currency = serverSnapshot.currency
    localJob.isDefault = serverSnapshot.isDefault
    localJob.sortOrder = serverSnapshot.sortOrder
    localJob.payrollDay = serverSnapshot.payrollDay
    localJob.halfTaxMonth = serverSnapshot.halfTaxMonth
    localJob.monthlyGoal = serverSnapshot.monthlyGoal
    localJob.archivedAt = serverSnapshot.archivedAt
    localJob.deletedAt = serverSnapshot.deletedAt
    localJob.serverRevision = serverSnapshot.revision
    localJob.serverUpdatedAt = serverSnapshot.updatedAt
    localJob.syncStatus = .clean
    localJob.dirtyFieldKeys = []
    localJob.lastSyncedSnapshot = conflictData
    localJob.conflictServerSnapshot = nil
    localJob.localUpdatedAt = Date()

    try modelContext.save()
  }

  /// Upsert a user shift from server data
  internal func upsertUserShift(_ shift: LocalUserShift) throws {
    let shiftId = shift.id
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == shiftId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing - copy all fields
      existing.jobId = shift.jobId
      existing.shiftDate = shift.shiftDate
      existing.startTime = shift.startTime
      existing.endTime = shift.endTime
      existing.customPauseWindows = shift.customPauseWindows
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
  internal func getUserShift(id: String) throws -> LocalUserShift? {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get all user shifts for a user (including soft-deleted for sync)
  internal func getAllUserShifts(userId: String) throws -> [LocalUserShift] {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty user shifts that need to be pushed
  internal func getDirtyUserShifts(userId: String) throws -> [LocalUserShift] {
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

  internal func hasDirtyUserShifts(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId
          && (shift.syncStatusRaw == "dirty" || shift.syncStatusRaw == "pendingDelete"
            || (shift.syncStatusRaw == "conflict" && shift.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local User Shift Write Operations

  internal func createUserShift(
    id: String? = nil,
    userId: String,
    jobId: String? = nil,
    shiftDate: Date,
    startTime: String,
    endTime: String,
    note: String? = nil,
    customPauseWindows: CustomPauseWindows? = nil,
    customSupplements: CustomSupplementsData?
  ) throws -> ShiftRow {
    let resolvedId = id ?? UUID().lowercasedString

    // Idempotent create path: when a deterministic shift ID is provided and already exists,
    // return the existing local row instead of creating a duplicate.
    if let existing = try getUserShift(id: resolvedId), existing.userId == userId {
      return existing.toShiftRow()
    }

    let now = Date()

    let pauseWindowsData = PauseWindowSupport.normalize(customPauseWindows).flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }
    let supplementsData = customSupplements.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    let normalizedNote = ShiftNoteSupport.normalize(note)

    let dateFormatter = isoDateFormatter
    let shiftDateString = dateFormatter.string(from: shiftDate)

    let snapshot = UserShiftServerSnapshot(
      jobId: jobId,
      shiftDate: shiftDateString,
      startTime: startTime,
      endTime: endTime,
      note: normalizedNote,
      customPauseWindows: pauseWindowsData,
      customSupplements: supplementsData,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = UserShiftField.allCases.map(\.rawValue)
    let dirtyFieldsData = (try? kCanonicalJSONEncoder.encode(allFields)) ?? Data()

    let localShift = LocalUserShift(
      id: resolvedId,
      userId: userId,
      jobId: jobId,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      note: normalizedNote,
      customPauseWindows: pauseWindowsData,
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

  internal func updateUserShiftCustomPauseWindows(
    id: String,
    customPauseWindows: CustomPauseWindows?
  ) throws -> ShiftRow {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let normalizedData = PauseWindowSupport.normalize(customPauseWindows).flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }

    var dirtyFields = localShift.dirtyFieldKeys
    if normalizedData != localShift.customPauseWindows {
      localShift.customPauseWindows = normalizedData
      dirtyFields.insert(.customPauseWindows)
      localShift.dirtyFieldKeys = dirtyFields
      localShift.localUpdatedAt = Date()
      if localShift.syncStatus == .clean {
        localShift.syncStatus = .dirty
      }
      try modelContext.save()
    }

    return localShift.toShiftRow()
  }

  internal func updateUserShift(
    id: String,
    jobId: String? = nil,
    shiftDate: Date?,
    startTime: String?,
    endTime: String?,
    note: String? = nil,
    noteWasEdited: Bool = false,
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

    if let newJobId = jobId, newJobId != localShift.jobId {
      localShift.jobId = newJobId
      newDirtyFields.insert(.jobId)
    }

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

    if noteWasEdited {
      let normalizedNote = ShiftNoteSupport.normalize(note)
      if normalizedNote != localShift.note {
        localShift.note = normalizedNote
        newDirtyFields.insert(.note)
      }
    }

    if let newSupplements = customSupplements {
      let newData = try? kCanonicalJSONEncoder.encode(newSupplements)
      if newData != localShift.customSupplements {
        localShift.customSupplements = newData
        newDirtyFields.insert(.customSupplements)
      }
    }

    localShift.dirtyFieldKeys = newDirtyFields
    localShift.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localShift.syncStatus == .clean {
      localShift.syncStatus = .dirty
    }

    try modelContext.save()
    return localShift.toShiftRow()
  }

  internal func markShiftPendingDelete(id: String) throws -> String {
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

  /// Mark multiple shifts for deletion in one transaction.
  /// Returns affected user IDs so callers can trigger side effects once per user.
  internal func markShiftsPendingDelete(ids: [String]) throws -> Set<String> {
    guard !ids.isEmpty else {
      return []
    }

    var affectedUserIds: Set<String> = []
    var didMutate = false
    let now = Date()

    for id in Set(ids) {
      let descriptor = FetchDescriptor<LocalUserShift>(
        predicate: #Predicate { $0.id == id }
      )

      guard let localShift = try modelContext.fetch(descriptor).first else {
        continue
      }

      localShift.syncStatus = .pendingDelete
      localShift.localUpdatedAt = now
      affectedUserIds.insert(localShift.userId)
      didMutate = true
    }

    if didMutate {
      try modelContext.save()
    }

    return affectedUserIds
  }

  internal func resolveStoredShiftConflictKeepLocal(id: String) throws {
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

  internal func resolveStoredShiftConflictKeepServer(id: String) throws {
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
    localShift.jobId = serverSnapshot.jobId
    localShift.startTime = serverSnapshot.startTime
    localShift.endTime = serverSnapshot.endTime
    localShift.note = serverSnapshot.note
    localShift.customPauseWindows = serverSnapshot.customPauseWindows
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

  // MARK: - Event Operations

  internal func upsertEvent(_ event: LocalEvent) throws {
    let eventId = event.id
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == eventId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      existing.startDate = event.startDate
      existing.endDate = event.endDate
      existing.isAllDay = event.isAllDay
      existing.startTime = event.startTime
      existing.endTime = event.endTime
      existing.note = event.note
      existing.serverUpdatedAt = event.serverUpdatedAt
      existing.serverRevision = event.serverRevision
      existing.serverDeletedAt = event.serverDeletedAt
      existing.syncStatusRaw = event.syncStatusRaw
      existing.dirtyFields = event.dirtyFields
      existing.lastSyncedSnapshot = event.lastSyncedSnapshot
      existing.localUpdatedAt = event.localUpdatedAt
      existing.conflictServerSnapshot = event.conflictServerSnapshot
    } else {
      modelContext.insert(event)
    }
  }

  internal func getEvent(id: String) throws -> LocalEvent? {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  internal func getAllEvents(userId: String) throws -> [LocalEvent] {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  internal func getDirtyEvents(userId: String) throws -> [LocalEvent] {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { event in
        event.userId == userId
          && (event.syncStatusRaw == "dirty" || event.syncStatusRaw == "pendingDelete"
            || (event.syncStatusRaw == "conflict" && event.serverRevision == 0))
      }
    )
    return try modelContext.fetch(descriptor)
  }

  internal func hasDirtyEvents(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { event in
        event.userId == userId
          && (event.syncStatusRaw == "dirty" || event.syncStatusRaw == "pendingDelete"
            || (event.syncStatusRaw == "conflict" && event.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // swiftlint:disable:next function_parameter_count
  internal func createEvent(
    id: String? = nil,
    userId: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    startTime: String?,
    endTime: String?,
    note: String,
    notificationMinutesArray: [Int]? = nil,
    notificationAnchorTime: String? = nil
  ) throws -> EventRow {
    let resolvedId = id ?? UUID().lowercasedString

    if let existing = try getEvent(id: resolvedId), existing.userId == userId {
      return existing.toEventRow()
    }

    let now = Date()
    let dateFormatter = isoDateFormatter
    let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedReminderMinutes = LocalEvent.normalizedReminderMinutesOptional(
      notificationMinutesArray
    )
    let normalizedAnchorTime =
      isAllDay ? LocalEvent.normalizedAnchorTime(notificationAnchorTime) : nil

    let snapshot = EventServerSnapshot(
      startDate: dateFormatter.string(from: startDate),
      endDate: dateFormatter.string(from: endDate),
      isAllDay: isAllDay,
      startTime: startTime,
      endTime: endTime,
      note: trimmedNote,
      notificationMinutesArray: normalizedReminderMinutes,
      notificationAnchorTime: normalizedAnchorTime,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = EventField.allCases.map(\.rawValue)
    let dirtyFieldsData = (try? kCanonicalJSONEncoder.encode(allFields)) ?? Data()

    let localEvent = LocalEvent(
      id: resolvedId,
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      startTime: startTime,
      endTime: endTime,
      note: trimmedNote,
      notificationMinutesArray: normalizedReminderMinutes ?? [],
      notificationAnchorTime: normalizedAnchorTime,
      serverUpdatedAt: now,
      serverRevision: 0,
      serverDeletedAt: nil,
      syncStatus: .dirty,
      dirtyFields: dirtyFieldsData,
      lastSyncedSnapshot: snapshot.encoded(),
      localUpdatedAt: now,
      conflictServerSnapshot: nil
    )

    modelContext.insert(localEvent)
    try modelContext.save()
    return localEvent.toEventRow()
  }

  // swiftlint:disable:next function_parameter_count
  internal func updateEvent(
    id: String,
    startDate: Date?,
    endDate: Date?,
    isAllDay: Bool?,
    startTime: String?,
    endTime: String?,
    note: String?,
    notificationMinutesArray: [Int]? = nil,
    notificationAnchorTime: String? = nil
  ) throws -> EventRow {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localEvent = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localEvent.dirtyFieldKeys
    let now = Date()

    if let startDate, startDate != localEvent.startDate {
      localEvent.startDate = startDate
      newDirtyFields.insert(.startDate)
    }

    if let endDate, endDate != localEvent.endDate {
      localEvent.endDate = endDate
      newDirtyFields.insert(.endDate)
    }

    if let isAllDay, isAllDay != localEvent.isAllDay {
      localEvent.isAllDay = isAllDay
      newDirtyFields.insert(.isAllDay)
    }

    if startTime != localEvent.startTime {
      localEvent.startTime = startTime
      newDirtyFields.insert(.startTime)
    }

    if endTime != localEvent.endTime {
      localEvent.endTime = endTime
      newDirtyFields.insert(.endTime)
    }

    if let note {
      let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedNote != localEvent.note {
        localEvent.note = trimmedNote
        newDirtyFields.insert(.note)
      }
    }

    let resolvedIsAllDay = isAllDay ?? localEvent.isAllDay
    let normalizedReminderMinutes = LocalEvent.normalizedReminderMinutes(notificationMinutesArray)
    if normalizedReminderMinutes != localEvent.notificationMinutesArray {
      localEvent.notificationMinutesArray = normalizedReminderMinutes
      newDirtyFields.insert(.notificationMinutesArray)
    }

    let normalizedAnchorTime =
      resolvedIsAllDay ? LocalEvent.normalizedAnchorTime(notificationAnchorTime) : nil
    if normalizedAnchorTime != localEvent.notificationAnchorTime {
      localEvent.notificationAnchorTime = normalizedAnchorTime
      newDirtyFields.insert(.notificationAnchorTime)
    }

    localEvent.dirtyFieldKeys = newDirtyFields
    localEvent.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localEvent.syncStatus == .clean {
      localEvent.syncStatus = .dirty
    }

    try modelContext.save()
    return localEvent.toEventRow()
  }

  internal func markEventPendingDelete(id: String) throws -> String {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localEvent = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    localEvent.syncStatus = .pendingDelete
    localEvent.localUpdatedAt = Date()

    try modelContext.save()
    return localEvent.userId
  }

  internal func resolveStoredEventConflictKeepLocal(id: String) throws {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localEvent = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localEvent.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    guard
      let serverSnapshot = EventServerSnapshot.decode(
        from: localEvent.conflictServerSnapshot ?? Data()
      )
    else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    localEvent.serverRevision = serverSnapshot.revision
    localEvent.serverUpdatedAt = serverSnapshot.updatedAt
    localEvent.syncStatus = .dirty
    localEvent.conflictServerSnapshot = nil
    localEvent.localUpdatedAt = Date()

    try modelContext.save()
  }

  internal func resolveStoredEventConflictKeepServer(id: String) throws {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localEvent = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    guard localEvent.syncStatus == .conflict else {
      throw LocalStoreWriteError.notInConflict
    }

    let conflictData = localEvent.conflictServerSnapshot ?? Data()
    guard let serverSnapshot = EventServerSnapshot.decode(from: conflictData) else {
      throw LocalStoreWriteError.missingConflictSnapshot
    }

    let dateFormatter = isoDateFormatter

    localEvent.startDate =
      dateFormatter.date(from: serverSnapshot.startDate) ?? localEvent.startDate
    localEvent.endDate =
      dateFormatter.date(from: serverSnapshot.endDate) ?? localEvent.endDate
    localEvent.isAllDay = serverSnapshot.isAllDay
    localEvent.startTime = serverSnapshot.startTime
    localEvent.endTime = serverSnapshot.endTime
    localEvent.note = serverSnapshot.note
    localEvent.notificationMinutesArray =
      LocalEvent.normalizedReminderMinutes(serverSnapshot.notificationMinutesArray)
    localEvent.notificationAnchorTime =
      LocalEvent.normalizedAnchorTime(serverSnapshot.notificationAnchorTime)
    localEvent.serverRevision = serverSnapshot.revision
    localEvent.serverUpdatedAt = serverSnapshot.updatedAt
    localEvent.serverDeletedAt = serverSnapshot.deletedAt
    localEvent.syncStatus = .clean
    localEvent.dirtyFieldKeys = []
    localEvent.lastSyncedSnapshot = conflictData
    localEvent.conflictServerSnapshot = nil
    localEvent.localUpdatedAt = Date()

    try modelContext.save()
  }

  // MARK: - Recurring Shift Operations

  /// Upsert a recurring shift from server data
  internal func upsertRecurringShift(_ shift: LocalRecurringShift) throws {
    let shiftId = shift.id
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == shiftId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing
      existing.jobId = shift.jobId
      existing.startTime = shift.startTime
      existing.endTime = shift.endTime
      existing.repeatIntervalWeeks = shift.repeatIntervalWeeks
      existing.selectedDays = shift.selectedDays
      existing.endCondition = shift.endCondition
      existing.exclusions = shift.exclusions
      existing.dateSpecificPauseWindows = shift.dateSpecificPauseWindows
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
  internal func getRecurringShift(id: String) throws -> LocalRecurringShift? {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get all recurring shifts for a user
  internal func getAllRecurringShifts(userId: String) throws -> [LocalRecurringShift] {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty recurring shifts that need to be pushed
  internal func getDirtyRecurringShifts(userId: String) throws -> [LocalRecurringShift] {
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

  internal func hasDirtyRecurringShifts(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { shift in
        shift.userId == userId
          && (shift.syncStatusRaw == "dirty" || shift.syncStatusRaw == "pendingDelete"
            || (shift.syncStatusRaw == "conflict" && shift.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local Recurring Shift Write Operations

  // swiftlint:disable:next function_parameter_count
  internal func createRecurringShift(
    userId: String,
    jobId: String? = nil,
    startTime: String,
    endTime: String,
    repeatIntervalWeeks: Int,
    selectedDays: SelectedDays,
    endCondition: EndCondition?,
    exclusions: [String]?,
    dateSpecificPauseWindows: DateSpecificPauseWindows? = nil,
    dateSpecificSupplements: [String: CustomSupplementsData]?,
    dateSpecificNotes: [String: String]? = nil
  ) throws -> RecurringShiftRow {
    let id = UUID().lowercasedString
    let now = Date()

    let selectedDaysData = (try? kCanonicalJSONEncoder.encode(selectedDays)) ?? Data()
    let endConditionData = endCondition.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    let exclusionsData = exclusions.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    let pauseWindowsData = PauseWindowSupport.normalize(dateSpecificPauseWindows).flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }
    let supplementsData = dateSpecificSupplements.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    let notesData = ShiftNoteSupport.normalizeDateSpecificNotes(dateSpecificNotes).flatMap {
      value in
      try? kCanonicalJSONEncoder.encode(value)
    }

    let serverSnapshot = RecurringShiftServerSnapshot(
      jobId: jobId,
      startTime: startTime,
      endTime: endTime,
      repeatIntervalWeeks: repeatIntervalWeeks,
      selectedDays: selectedDaysData,
      endCondition: endConditionData,
      exclusions: exclusionsData,
      dateSpecificPauseWindows: pauseWindowsData,
      dateSpecificSupplements: supplementsData,
      dateSpecificNotes: notesData,
      updatedAt: now,
      revision: 0,
      deletedAt: nil
    )

    let allFields = RecurringShiftField.allCases.map(\.rawValue)
    let dirtyFieldsData = (try? kCanonicalJSONEncoder.encode(allFields)) ?? Data()

    let localShift = LocalRecurringShift(
      id: id,
      userId: userId,
      jobId: jobId,
      startTime: startTime,
      endTime: endTime,
      repeatIntervalWeeks: repeatIntervalWeeks,
      selectedDays: selectedDaysData,
      endCondition: endConditionData,
      exclusions: exclusionsData,
      dateSpecificPauseWindows: pauseWindowsData,
      dateSpecificSupplements: supplementsData,
      dateSpecificNotes: notesData,
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
  internal func updateRecurringShift(
    id: String,
    jobId: String? = nil,
    startTime: String?,
    endTime: String?,
    repeatIntervalWeeks: Int?,
    selectedDays: SelectedDays?,
    endCondition: EndCondition?,
    exclusions: [String]?,
    dateSpecificSupplements: [String: CustomSupplementsData]?,
    dateSpecificNotes: [String: String]? = nil
  ) throws -> RecurringShiftRow {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var newDirtyFields = localShift.dirtyFieldKeys
    let now = Date()

    if let newJobId = jobId, newJobId != localShift.jobId {
      localShift.jobId = newJobId
      newDirtyFields.insert(.jobId)
    }

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
      let newData = (try? kCanonicalJSONEncoder.encode(newDays)) ?? Data()
      if newData != localShift.selectedDays {
        localShift.selectedDays = newData
        newDirtyFields.insert(.selectedDays)
      }
    }

    if let newCondition = endCondition {
      let newData = try? kCanonicalJSONEncoder.encode(newCondition)
      if newData != localShift.endCondition {
        localShift.endCondition = newData
        newDirtyFields.insert(.endCondition)
      }
    }

    if let newExclusions = exclusions {
      let newData = try? kCanonicalJSONEncoder.encode(newExclusions)
      if newData != localShift.exclusions {
        localShift.exclusions = newData
        newDirtyFields.insert(.exclusions)
      }
    }

    if let newSupplements = dateSpecificSupplements {
      let newData = try? kCanonicalJSONEncoder.encode(newSupplements)
      if newData != localShift.dateSpecificSupplements {
        localShift.dateSpecificSupplements = newData
        newDirtyFields.insert(.dateSpecificSupplements)
      }
    }

    if let newNotes = ShiftNoteSupport.normalizeDateSpecificNotes(dateSpecificNotes) {
      let newData = try? kCanonicalJSONEncoder.encode(newNotes)
      if newData != localShift.dateSpecificNotes {
        localShift.dateSpecificNotes = newData
        newDirtyFields.insert(.dateSpecificNotes)
      }
    }

    localShift.dirtyFieldKeys = newDirtyFields
    localShift.localUpdatedAt = now

    if !newDirtyFields.isEmpty, localShift.syncStatus == .clean {
      localShift.syncStatus = .dirty
    }

    try modelContext.save()
    return localShift.toRecurringShiftRow()
  }

  internal func updateRecurringShiftDateSpecificPauseWindows(
    id: String,
    dateSpecificPauseWindows: DateSpecificPauseWindows?
  ) throws -> RecurringShiftRow {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let normalizedData = PauseWindowSupport.normalize(dateSpecificPauseWindows).flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }

    var dirtyFields = localShift.dirtyFieldKeys
    if normalizedData != localShift.dateSpecificPauseWindows {
      localShift.dateSpecificPauseWindows = normalizedData
      dirtyFields.insert(.dateSpecificPauseWindows)
      localShift.dirtyFieldKeys = dirtyFields
      localShift.localUpdatedAt = Date()
      if localShift.syncStatus == .clean {
        localShift.syncStatus = .dirty
      }
      try modelContext.save()
    }

    return localShift.toRecurringShiftRow()
  }

  internal func updateRecurringShiftDateSpecificNotes(
    id: String,
    dateSpecificNotes: [String: String]?
  ) throws -> RecurringShiftRow {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    let normalizedData = ShiftNoteSupport.normalizeDateSpecificNotes(dateSpecificNotes).flatMap {
      value in
      try? kCanonicalJSONEncoder.encode(value)
    }

    var dirtyFields = localShift.dirtyFieldKeys
    if normalizedData != localShift.dateSpecificNotes {
      localShift.dateSpecificNotes = normalizedData
      dirtyFields.insert(.dateSpecificNotes)
      localShift.dirtyFieldKeys = dirtyFields
      localShift.localUpdatedAt = Date()
      if localShift.syncStatus == .clean {
        localShift.syncStatus = .dirty
      }
      try modelContext.save()
    }

    return localShift.toRecurringShiftRow()
  }

  internal func addRecurringShiftExclusion(id: String, date: String) throws -> Bool {
    try addRecurringShiftExclusions(id: id, dates: [date]) > 0
  }

  internal func addRecurringShiftExclusions(id: String, dates: [String]) throws -> Int {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let localShift = try modelContext.fetch(descriptor).first else {
      throw LocalStoreWriteError.notFound
    }

    var exclusions = localShift.decodedExclusions
    var existingExclusions = Set(exclusions)
    let datesToAdd = dates.filter { existingExclusions.insert($0).inserted }

    guard !datesToAdd.isEmpty else {
      return 0
    }

    exclusions.append(contentsOf: datesToAdd)
    localShift.decodedExclusions = exclusions

    var dirtyFields = localShift.dirtyFieldKeys
    dirtyFields.insert(.exclusions)
    localShift.dirtyFieldKeys = dirtyFields

    if localShift.syncStatus == .clean {
      localShift.syncStatus = .dirty
    }
    localShift.localUpdatedAt = Date()

    try modelContext.save()
    return datesToAdd.count
  }

  internal func markRecurringShiftPendingDelete(id: String) throws {
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

  internal func resolveStoredRecurringShiftConflictKeepLocal(id: String) throws {
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

  internal func resolveStoredRecurringShiftConflictKeepServer(id: String) throws {
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
    localShift.jobId = serverSnapshot.jobId
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
  internal func upsertWageSnapshot(_ snapshot: LocalWageSnapshot) throws {
    let snapshotId = snapshot.id
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == snapshotId }
    )

    if let existing = try modelContext.fetch(descriptor).first {
      // Update existing
      existing.jobId = snapshot.jobId
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
  internal func getWageSnapshot(id: String) throws -> LocalWageSnapshot? {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get all wage snapshots for a user
  internal func getAllWageSnapshots(userId: String) throws -> [LocalWageSnapshot] {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.userId == userId },
      sortBy: [SortDescriptor(\.fromDate, order: .reverse)]
    )
    return try modelContext.fetch(descriptor)
  }

  /// Get dirty wage snapshots that need to be pushed
  internal func getDirtyWageSnapshots(userId: String) throws -> [LocalWageSnapshot] {
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

  internal func hasDirtyWageSnapshots(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.userId == userId
          && (snapshot.syncStatusRaw == "dirty" || snapshot.syncStatusRaw == "pendingDelete"
            || (snapshot.syncStatusRaw == "conflict" && snapshot.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local Wage Snapshot Write Operations

  // swiftlint:disable:next function_parameter_count
  internal func createWageSnapshot(
    userId: String,
    jobId: String? = nil,
    fromDate: Date?,
    hourlyWage: Double,
    wageLevel: Int?,
    tariffTypeId: String?,
    supplements: SupplementRulesSnapshot,
    overtime: OvertimeConfig = .disabled,
    taxEnabled: Bool?,
    taxPercentage: Double?,
    breakEnabled: Bool?,
    breakMethod: String?,
    breakThresholdHours: Double?,
    breakDeductionMinutes: Int?
  ) throws -> WageSnapshot {
    let id = UUID().lowercasedString
    let now = Date()

    let supplementsData = (try? kCanonicalJSONEncoder.encode(supplements)) ?? Data()
    let overtimeData = (try? kCanonicalJSONEncoder.encode(overtime)) ?? Data()

    let dateFormatter = isoDateFormatter
    let fromDateString = fromDate.map { dateFormatter.string(from: $0) }

    let serverSnapshot = WageSnapshotServerSnapshot(
      jobId: jobId,
      fromDate: fromDateString,
      hourlyWage: hourlyWage,
      wageLevel: wageLevel,
      tariffTypeId: tariffTypeId,
      supplements: supplementsData,
      overtime: overtimeData,
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

    let allFields = WageSnapshotField.allCases.map(\.rawValue)
    let dirtyFieldsData = (try? kCanonicalJSONEncoder.encode(allFields)) ?? Data()

    let localSnapshot = LocalWageSnapshot(
      id: id,
      userId: userId,
      jobId: jobId,
      fromDate: fromDate,
      hourlyWage: hourlyWage,
      wageLevel: wageLevel,
      tariffTypeId: tariffTypeId,
      supplements: supplementsData,
      overtime: overtimeData,
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
  internal func updateWageSnapshot(
    id: String,
    jobId: String? = nil,
    hourlyWage: Double?,
    wageLevel: Int?,
    updateWageLevel: Bool = false,
    tariffTypeId: String?,
    updateTariffTypeId: Bool = false,
    supplements: SupplementRulesSnapshot?,
    overtime: OvertimeConfig? = nil,
    taxEnabled: Bool?,
    taxPercentage: Double?,
    updateTaxPercentage: Bool = false,
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

    if let newJobId = jobId, newJobId != localSnapshot.jobId {
      localSnapshot.jobId = newJobId
      newDirtyFields.insert(.jobId)
    }

    if let newWage = hourlyWage, newWage != localSnapshot.hourlyWage {
      localSnapshot.hourlyWage = newWage
      newDirtyFields.insert(.hourlyWage)
    }

    if updateWageLevel, wageLevel != localSnapshot.wageLevel {
      localSnapshot.wageLevel = wageLevel
      newDirtyFields.insert(.wageLevel)
    }

    if updateTariffTypeId, tariffTypeId != localSnapshot.tariffTypeId {
      localSnapshot.tariffTypeId = tariffTypeId
      newDirtyFields.insert(.tariffTypeId)
    }

    if let newSupplements = supplements {
      let newData = (try? kCanonicalJSONEncoder.encode(newSupplements)) ?? Data()
      if newData != localSnapshot.supplements {
        localSnapshot.supplements = newData
        newDirtyFields.insert(.supplements)
      }
    }

    if let newOvertime = overtime {
      let newData = (try? kCanonicalJSONEncoder.encode(newOvertime)) ?? Data()
      if newData != localSnapshot.overtime {
        localSnapshot.overtime = newData
        newDirtyFields.insert(.overtime)
      }
    }

    if let newTaxEnabled = taxEnabled, newTaxEnabled != localSnapshot.taxEnabled {
      localSnapshot.taxEnabled = newTaxEnabled
      newDirtyFields.insert(.taxEnabled)
    }

    if updateTaxPercentage, taxPercentage != localSnapshot.taxPercentage {
      localSnapshot.taxPercentage = taxPercentage
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

    if !newDirtyFields.isEmpty, localSnapshot.syncStatus == .clean {
      localSnapshot.syncStatus = .dirty
    }

    try modelContext.save()
    return localSnapshot.toWageSnapshot()
  }

  internal func markWageSnapshotPendingDelete(id: String) throws {
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

  internal func resolveStoredWageSnapshotConflictKeepLocal(id: String) throws {
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

  internal func resolveStoredWageSnapshotConflictKeepServer(id: String) throws {
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
    localSnapshot.jobId = serverSnapshot.jobId
    localSnapshot.hourlyWage = serverSnapshot.hourlyWage
    localSnapshot.wageLevel = serverSnapshot.wageLevel
    localSnapshot.tariffTypeId = serverSnapshot.tariffTypeId
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
  internal func upsertUserSettings(_ settings: LocalUserSettings) throws {
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
      existing.calendarContentColorStyle = settings.calendarContentColorStyle
      existing.showDashboardClockButtons = settings.showDashboardClockButtons
      existing.aiDataSharingEnabled = settings.aiDataSharingEnabled
      existing.halfTaxMonth = settings.halfTaxMonth
      existing.currency = settings.currency
      existing.defaultStartupTab = settings.defaultStartupTab
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
  internal func getUserSettings(userId: String) throws -> LocalUserSettings? {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )
    return try modelContext.fetch(descriptor).first
  }

  /// Get dirty user settings that need to be pushed
  internal func getDirtyUserSettings(userId: String) throws -> LocalUserSettings? {
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

  internal func hasDirtyUserSettings(userId: String) throws -> Bool {
    var descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { settings in
        settings.userId == userId
          && (settings.syncStatusRaw == "dirty"
            || (settings.syncStatusRaw == "conflict" && settings.serverRevision == 0))
      }
    )
    descriptor.fetchLimit = 1
    return try !modelContext.fetch(descriptor).isEmpty
  }

  // MARK: - Local User Settings Write Operations

  /// Create a new local user settings entry
  /// Used during onboarding when no settings exist yet
  internal func createUserSettings(
    userId: String,
    payrollDay: Int? = nil,
    currency: String? = nil,
    theme: String = "system",
    calendarContentColorStyle: String = "workplace",
    showDashboardClockButtons: Bool = true,
    aiDataSharingEnabled: Bool = false,
    wageyShowcaseSeen: Bool = false,
    monthlyGoal: Int? = nil,
    monthlyGoalsByMonth: [String: Int] = [:],
    defaultShiftsView: String? = nil,
    halfTaxMonth: Int? = nil,
    defaultStartupTab: String? = nil
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
      calendarContentColorStyle: calendarContentColorStyle,
      showDashboardClockButtons: showDashboardClockButtons,
      aiDataSharingEnabled: aiDataSharingEnabled,
      halfTaxMonth: halfTaxMonth,
      currency: currency,
      defaultStartupTab: defaultStartupTab,
      wageyShowcaseSeen: wageyShowcaseSeen,
      lastActive: now,
      updatedAt: now,
      revision: 0
    )

    // Track all non-nil fields as dirty so they get pushed to server
    var dirtyFields: [UserSettingsField] = [
      .theme, .calendarContentColorStyle, .showDashboardClockButtons, .lastActive,
    ]
    if aiDataSharingEnabled {
      dirtyFields.append(.aiDataSharingEnabled)
    }
    if payrollDay != nil { dirtyFields.append(.payrollDay) }
    if currency != nil { dirtyFields.append(.currency) }
    if monthlyGoal != nil { dirtyFields.append(.monthlyGoal) }
    if !monthlyGoalsByMonth.isEmpty { dirtyFields.append(.monthlyGoalsByMonth) }
    if defaultShiftsView != nil { dirtyFields.append(.defaultShiftsView) }
    if halfTaxMonth != nil { dirtyFields.append(.halfTaxMonth) }
    if defaultStartupTab != nil { dirtyFields.append(.defaultStartupTab) }

    let dirtyFieldsData =
      (try? kCanonicalJSONEncoder.encode(dirtyFields.map(\.rawValue))) ?? Data()

    let localSettings = LocalUserSettings(
      userId: userId,
      monthlyGoal: monthlyGoal,
      monthlyGoalsByMonthData: (try? kCanonicalJSONEncoder.encode(monthlyGoalsByMonth))
        ?? Data(),
      defaultShiftsView: defaultShiftsView,
      profilePictureUrl: nil,
      payrollDay: payrollDay,
      theme: theme,
      calendarContentColorStyle: calendarContentColorStyle,
      showDashboardClockButtons: showDashboardClockButtons,
      aiDataSharingEnabled: aiDataSharingEnabled,
      halfTaxMonth: halfTaxMonth,
      currency: currency,
      defaultStartupTab: defaultStartupTab,
      wageyShowcaseSeen: wageyShowcaseSeen,
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
  internal func getOrCreateUserSettings(
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
  internal func updateUserSettings(
    userId: String,
    monthlyGoal: Int?,
    monthlyGoalsByMonth: [String: Int]?,
    defaultShiftsView: String?,
    profilePictureUrl: String?,
    payrollDay: Int?,
    theme: String?,
    calendarContentColorStyle: String? = nil,
    showDashboardClockButtons: Bool? = nil,
    aiDataSharingEnabled: Bool? = nil,
    wageyShowcaseSeen: Bool? = nil,
    halfTaxMonth: Int?,
    currency: String?,
    defaultStartupTab: String?
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

    if let newStyle = calendarContentColorStyle {
      localSettings.calendarContentColorStyle = newStyle
      newDirtyFields.insert(.calendarContentColorStyle)
    }

    if let newShowDashboardClockButtons = showDashboardClockButtons {
      localSettings.showDashboardClockButtons = newShowDashboardClockButtons
      newDirtyFields.insert(.showDashboardClockButtons)
    }

    if let newAIDataSharingEnabled = aiDataSharingEnabled {
      localSettings.aiDataSharingEnabled = newAIDataSharingEnabled
      newDirtyFields.insert(.aiDataSharingEnabled)
    }

    if let newWageyShowcaseSeen = wageyShowcaseSeen {
      localSettings.wageyShowcaseSeen = newWageyShowcaseSeen
      newDirtyFields.insert(.wageyShowcaseSeen)
    }

    if let newHalfTax = halfTaxMonth, newHalfTax != localSettings.halfTaxMonth {
      localSettings.halfTaxMonth = newHalfTax
      newDirtyFields.insert(.halfTaxMonth)
    }

    if let newCurrency = currency, newCurrency != localSettings.currency {
      localSettings.currency = newCurrency
      newDirtyFields.insert(.currency)
    }

    if let newDefaultStartupTab = defaultStartupTab,
      newDefaultStartupTab != localSettings.defaultStartupTab
    {
      localSettings.defaultStartupTab = newDefaultStartupTab
      newDirtyFields.insert(.defaultStartupTab)
    }

    localSettings.dirtyFieldKeys = newDirtyFields
    localSettings.localUpdatedAt = now

    // Mark as dirty if we have dirty fields and status allows it
    if !newDirtyFields.isEmpty, localSettings.syncStatus == .clean {
      localSettings.syncStatus = .dirty
    }

    try modelContext.save()
    return localSettings.toUserSettings()
  }

  /// Clear the profile picture URL (set to nil)
  /// This is separate from updateUserSettings because Swift optionals can't distinguish
  /// between "not provided" and "explicitly set to nil"
  internal func clearProfilePictureUrl(userId: String) throws -> UserSettings {
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

  internal func updateUserSettingsLastActive(userId: String) throws -> Bool {
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

  internal func resolveStoredUserSettingsConflictKeepLocal(userId: String) throws {
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

  internal func resolveStoredUserSettingsConflictKeepServer(userId: String) throws {
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
    localSettings.calendarContentColorStyle = serverSnapshot.calendarContentColorStyle
    localSettings.showDashboardClockButtons = serverSnapshot.showDashboardClockButtons
    localSettings.aiDataSharingEnabled = serverSnapshot.aiDataSharingEnabled
    localSettings.halfTaxMonth = serverSnapshot.halfTaxMonth
    localSettings.currency = serverSnapshot.currency
    localSettings.defaultStartupTab = serverSnapshot.defaultStartupTab
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
  internal func getConflicts(userId: String) throws -> (
    jobs: [LocalJob],
    shifts: [LocalUserShift],
    events: [LocalEvent],
    recurringShifts: [LocalRecurringShift],
    wageSnapshots: [LocalWageSnapshot],
    settings: LocalUserSettings?
  ) {
    let jobsDescriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId && job.syncStatusRaw == "conflict"
      }
    )
    let jobs = try modelContext.fetch(jobsDescriptor)

    let shiftsDescriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.syncStatusRaw == "conflict"
      }
    )
    let shifts = try modelContext.fetch(shiftsDescriptor)

    let eventsDescriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { event in
        event.userId == userId && event.syncStatusRaw == "conflict"
      }
    )
    let events = try modelContext.fetch(eventsDescriptor)

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

    return (jobs, shifts, events, recurringShifts, wageSnapshots, settings)
  }

  /// Check if user has any conflicts
  internal func hasConflicts(userId: String) throws -> Bool {
    let conflicts = try getConflicts(userId: userId)
    return !conflicts.jobs.isEmpty || !conflicts.shifts.isEmpty
      || !conflicts.events.isEmpty || !conflicts.recurringShifts.isEmpty
      || !conflicts.wageSnapshots.isEmpty || conflicts.settings != nil
  }

  /// Check if user has any pending changes
  internal func hasPendingChanges(userId: String) throws -> Bool {
    try hasDirtyJobs(userId: userId)
      || hasDirtyUserShifts(userId: userId)
      || hasDirtyEvents(userId: userId)
      || hasDirtyRecurringShifts(userId: userId)
      || hasDirtyWageSnapshots(userId: userId)
      || hasDirtyPayrollAdjustments(userId: userId)
      || hasDirtyUserSettings(userId: userId)
  }

  /// Count total conflicts for a user
  internal func countConflicts(userId: String) throws -> Int {
    let conflicts = try getConflicts(userId: userId)
    return conflicts.jobs.count + conflicts.shifts.count + conflicts.events.count
      + conflicts.recurringShifts.count
      + conflicts.wageSnapshots.count
      + (conflicts.settings != nil ? 1 : 0)
  }

  /// Update sync state with a closure
  internal func updateSyncState(userId: String, update: (LocalSyncState) -> Void) {
    let descriptor = FetchDescriptor<LocalSyncState>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let state = try? modelContext.fetch(descriptor).first else {
      return
    }

    update(state)
    try? modelContext.save()
  }

  // MARK: - Sync Update Operations for Jobs

  // swiftlint:disable:next function_parameter_count
  internal func updateJobFromServer(
    id: String,
    serverRow: SyncJobRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    archivedAt: Date?,
    deletedAt: Date?,
    snapshot: JobServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.name = serverRow.name
    existing.color = serverRow.color
    existing.currency = serverRow.currency
    existing.isDefault = serverRow.is_default
    existing.sortOrder = serverRow.sort_order
    existing.payrollDay = serverRow.payroll_day
    existing.halfTaxMonth = serverRow.half_tax_month
    existing.monthlyGoal = serverRow.monthly_goal
    existing.archivedAt = archivedAt
    existing.deletedAt = deletedAt
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  internal func markJobConflict(id: String, serverSnapshot: JobServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateJobConflictSnapshot(id: String, serverSnapshot: JobServerSnapshot) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count
  internal func autoMergeJob(
    id: String,
    serverRow: SyncJobRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    archivedAt: Date?,
    deletedAt: Date?,
    newSnapshot: JobServerSnapshot,
    localDirtyFields: Set<JobField>
  ) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    if !localDirtyFields.contains(.name) {
      existing.name = serverRow.name
    }
    if !localDirtyFields.contains(.color) {
      existing.color = serverRow.color
    }
    if !localDirtyFields.contains(.currency) {
      existing.currency = serverRow.currency
    }
    if !localDirtyFields.contains(.isDefault) {
      existing.isDefault = serverRow.is_default
    }
    if !localDirtyFields.contains(.sortOrder) {
      existing.sortOrder = serverRow.sort_order
    }
    if !localDirtyFields.contains(.payrollDay) {
      existing.payrollDay = serverRow.payroll_day
    }
    if !localDirtyFields.contains(.halfTaxMonth) {
      existing.halfTaxMonth = serverRow.half_tax_month
    }
    if !localDirtyFields.contains(.monthlyGoal) {
      existing.monthlyGoal = serverRow.monthly_goal
    }
    if !localDirtyFields.contains(.archivedAt) {
      existing.archivedAt = archivedAt
    }
    if !localDirtyFields.contains(.deletedAt) {
      existing.deletedAt = deletedAt
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.lastSyncedSnapshot = newSnapshot.encoded()
  }

  // MARK: - Sync Update Operations for User Shifts

  /// Update a shift from server data (for clean rows)
  internal func updateShiftFromServer(
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

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    existing.jobId = serverRow.job_id
    existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
    existing.startTime = serverRow.start_time
    existing.endTime = serverRow.end_time
    existing.note = ShiftNoteSupport.normalize(serverRow.note)
    existing.customPauseWindows = PauseWindowSupport.normalize(serverRow.custom_pause_windows)
      .flatMap { value in
        try? kCanonicalJSONEncoder.encode(value)
      }
    existing.customSupplements = serverRow.custom_supplements.flatMap { value in
      try? kCanonicalJSONEncoder.encode(value)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  /// Mark a shift as having a conflict
  internal func markShiftConflict(id: String, serverSnapshot: UserShiftServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  /// Update conflict snapshot for a shift already in conflict
  internal func updateShiftConflictSnapshot(id: String, serverSnapshot: UserShiftServerSnapshot) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  /// Auto-merge a shift (apply server changes for non-dirty fields)
  internal func autoMergeShift(  // swiftlint:disable:this function_parameter_count
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

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    // Apply server changes only for non-dirty fields
    if !localDirtyFields.contains(.jobId) {
      existing.jobId = serverRow.job_id
    }
    if !localDirtyFields.contains(.shiftDate) {
      existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
    }
    if !localDirtyFields.contains(.startTime) {
      existing.startTime = serverRow.start_time
    }
    if !localDirtyFields.contains(.endTime) {
      existing.endTime = serverRow.end_time
    }
    if !localDirtyFields.contains(.note) {
      existing.note = ShiftNoteSupport.normalize(serverRow.note)
    }
    if !localDirtyFields.contains(.customPauseWindows) {
      existing.customPauseWindows = PauseWindowSupport.normalize(serverRow.custom_pause_windows)
        .flatMap { try? kCanonicalJSONEncoder.encode($0) }
    }
    if !localDirtyFields.contains(.customSupplements) {
      existing.customSupplements = serverRow.custom_supplements.flatMap { value in
        try? kCanonicalJSONEncoder.encode(value)
      }
    }

    // Update server metadata
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
    // Keep syncStatus = dirty (still needs push)
  }

  // MARK: - Sync Update Operations for Events

  internal func updateEventFromServer(
    id: String,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    snapshot: EventServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    existing.startDate = dateFormatter.date(from: serverRow.start_date) ?? existing.startDate
    existing.endDate = dateFormatter.date(from: serverRow.end_date) ?? existing.endDate
    existing.isAllDay = serverRow.is_all_day
    existing.startTime = serverRow.start_time
    existing.endTime = serverRow.end_time
    existing.note = serverRow.note
    existing.notificationMinutesArray =
      LocalEvent.normalizedReminderMinutes(serverRow.notification_minutes_array)
    existing.notificationAnchorTime =
      LocalEvent.normalizedAnchorTime(serverRow.notification_anchor_time)
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  internal func markEventConflict(id: String, serverSnapshot: EventServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateEventConflictSnapshot(id: String, serverSnapshot: EventServerSnapshot) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count
  internal func autoMergeEvent(
    id: String,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: EventServerSnapshot,
    localDirtyFields: Set<EventField>
  ) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    if !localDirtyFields.contains(.startDate) {
      existing.startDate = dateFormatter.date(from: serverRow.start_date) ?? existing.startDate
    }
    if !localDirtyFields.contains(.endDate) {
      existing.endDate = dateFormatter.date(from: serverRow.end_date) ?? existing.endDate
    }
    if !localDirtyFields.contains(.isAllDay) {
      existing.isAllDay = serverRow.is_all_day
    }
    if !localDirtyFields.contains(.startTime) {
      existing.startTime = serverRow.start_time
    }
    if !localDirtyFields.contains(.endTime) {
      existing.endTime = serverRow.end_time
    }
    if !localDirtyFields.contains(.note) {
      existing.note = serverRow.note
    }
    if !localDirtyFields.contains(.notificationMinutesArray) {
      existing.notificationMinutesArray =
        LocalEvent.normalizedReminderMinutes(serverRow.notification_minutes_array)
    }
    if !localDirtyFields.contains(.notificationAnchorTime) {
      existing.notificationAnchorTime =
        LocalEvent.normalizedAnchorTime(serverRow.notification_anchor_time)
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
  }

  // MARK: - Sync Update Operations for Recurring Shifts

  internal func updateRecurringShiftFromServer(
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

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.jobId = serverRow.job_id
    existing.startTime = serverRow.cleanStartTime
    existing.endTime = serverRow.cleanEndTime
    existing.repeatIntervalWeeks = serverRow.repeat_interval_weeks
    existing.selectedDays = (try? kCanonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
    existing.endCondition = serverRow.end_condition.flatMap { endCondition in
      try? kCanonicalJSONEncoder.encode(endCondition)
    }
    existing.exclusions = serverRow.exclusions.flatMap { exclusions in
      try? kCanonicalJSONEncoder.encode(exclusions)
    }
    existing.dateSpecificPauseWindows =
      PauseWindowSupport.normalize(serverRow.date_specific_pause_windows)
      .flatMap { pauseWindows in
        try? kCanonicalJSONEncoder.encode(pauseWindows)
      }
    existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap {
      supplements in
      try? kCanonicalJSONEncoder.encode(supplements)
    }
    existing.dateSpecificNotes = ShiftNoteSupport.normalizeDateSpecificNotes(
      serverRow.date_specific_notes
    )
    .flatMap { notes in
      try? kCanonicalJSONEncoder.encode(notes)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  internal func markRecurringShiftConflict(
    id: String, serverSnapshot: RecurringShiftServerSnapshot?
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateRecurringShiftConflictSnapshot(
    id: String, serverSnapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count
  internal func autoMergeRecurringShift(
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

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    if !localDirtyFields.contains(.jobId) {
      existing.jobId = serverRow.job_id
    }
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
      existing.selectedDays = (try? kCanonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
    }
    if !localDirtyFields.contains(.endCondition) {
      existing.endCondition = serverRow.end_condition.flatMap { value in
        try? kCanonicalJSONEncoder.encode(value)
      }
    }
    if !localDirtyFields.contains(.exclusions) {
      existing.exclusions = serverRow.exclusions.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    }
    if !localDirtyFields.contains(.dateSpecificPauseWindows) {
      existing.dateSpecificPauseWindows =
        PauseWindowSupport.normalize(serverRow.date_specific_pause_windows)
        .flatMap { try? kCanonicalJSONEncoder.encode($0) }
    }
    if !localDirtyFields.contains(.dateSpecificSupplements) {
      existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap { value in
        try? kCanonicalJSONEncoder.encode(value)
      }
    }
    if !localDirtyFields.contains(.dateSpecificNotes) {
      existing.dateSpecificNotes =
        ShiftNoteSupport.normalizeDateSpecificNotes(serverRow.date_specific_notes)
        .flatMap { try? kCanonicalJSONEncoder.encode($0) }
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.lastSyncedSnapshot = newSnapshot.encoded()
  }

  // MARK: - Sync Update Operations for Wage Snapshots

  internal func updateWageSnapshotFromServer(
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

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    existing.jobId = serverRow.job_id
    existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
    existing.hourlyWage = serverRow.hourly_wage
    existing.wageLevel = serverRow.wage_level
    existing.tariffTypeId = serverRow.tariff_type_id
    existing.supplements = (try? kCanonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
    existing.overtime =
      (try? kCanonicalJSONEncoder.encode(serverRow.overtime ?? .disabled)) ?? Data()
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

  internal func markWageSnapshotConflict(id: String, serverSnapshot: WageSnapshotServerSnapshot?) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateWageSnapshotConflictSnapshot(
    id: String, serverSnapshot: WageSnapshotServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  // swiftlint:disable:next function_parameter_count
  internal func autoMergeWageSnapshot(
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

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    if !localDirtyFields.contains(.jobId) {
      existing.jobId = serverRow.job_id
    }
    if !localDirtyFields.contains(.fromDate) {
      existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
    }
    if !localDirtyFields.contains(.hourlyWage) {
      existing.hourlyWage = serverRow.hourly_wage
    }
    if !localDirtyFields.contains(.wageLevel) {
      existing.wageLevel = serverRow.wage_level
    }
    if !localDirtyFields.contains(.tariffTypeId) {
      existing.tariffTypeId = serverRow.tariff_type_id
    }
    if !localDirtyFields.contains(.supplements) {
      existing.supplements = (try? kCanonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
    }
    if !localDirtyFields.contains(.overtime) {
      existing.overtime =
        (try? kCanonicalJSONEncoder.encode(serverRow.overtime ?? .disabled)) ?? Data()
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

  internal func updateUserSettingsFromServer(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = FormatterCache.iso8601Formatter()

    existing.monthlyGoal = serverRow.monthly_goal
    existing.monthlyGoalsByMonth = serverRow.monthly_goals_by_month ?? [:]
    existing.defaultShiftsView = serverRow.default_shifts_view
    existing.profilePictureUrl = serverRow.profile_picture_url
    existing.payrollDay = serverRow.payroll_day
    existing.theme = serverRow.theme
    existing.calendarContentColorStyle = serverRow.calendar_content_color_style ?? "workplace"
    existing.showDashboardClockButtons = serverRow.show_dashboard_clock_buttons ?? true
    existing.aiDataSharingEnabled = serverRow.ai_data_sharing_enabled ?? false
    existing.wageyShowcaseSeen = serverRow.wagey_showcase_seen ?? false
    existing.halfTaxMonth = serverRow.half_tax_month
    existing.currency = serverRow.currency
    existing.defaultStartupTab = serverRow.default_startup_tab
    existing.lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
    existing.createdAt = serverRow.created_at.flatMap { dateFormatter.date(from: $0) }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.localUpdatedAt = Date()
  }

  internal func markUserSettingsConflict(
    userId: String, serverSnapshot: UserSettingsServerSnapshot?
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .conflict
    existing.conflictServerSnapshot = serverSnapshot?.encoded()
  }

  internal func updateUserSettingsConflictSnapshot(
    userId: String, serverSnapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.conflictServerSnapshot = serverSnapshot.encoded()
  }

  internal func autoMergeUserSettings(
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

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = FormatterCache.iso8601Formatter()

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
    if !localDirtyFields.contains(.calendarContentColorStyle) {
      existing.calendarContentColorStyle = serverRow.calendar_content_color_style ?? "workplace"
    }
    if !localDirtyFields.contains(.showDashboardClockButtons) {
      existing.showDashboardClockButtons = serverRow.show_dashboard_clock_buttons ?? true
    }
    if !localDirtyFields.contains(.aiDataSharingEnabled) {
      existing.aiDataSharingEnabled = serverRow.ai_data_sharing_enabled ?? false
    }
    if !localDirtyFields.contains(.wageyShowcaseSeen) {
      existing.wageyShowcaseSeen = serverRow.wagey_showcase_seen ?? false
    }
    if !localDirtyFields.contains(.halfTaxMonth) {
      existing.halfTaxMonth = serverRow.half_tax_month
    }
    if !localDirtyFields.contains(.currency) {
      existing.currency = serverRow.currency
    }
    if !localDirtyFields.contains(.defaultStartupTab) {
      existing.defaultStartupTab = serverRow.default_startup_tab
    }
    if !localDirtyFields.contains(.lastActive) {
      existing.lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.lastSyncedSnapshot = newSnapshot.encoded()
  }

  // MARK: - Push Operations for User Shifts

  // MARK: - Push Operations for Jobs

  // swiftlint:disable:next function_parameter_count
  internal func markJobPushed(
    id: String,
    serverRow: SyncJobRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    archivedAt: Date?,
    deletedAt: Date?,
    snapshot: JobServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.name = serverRow.name
    existing.color = serverRow.color
    existing.currency = serverRow.currency
    existing.isDefault = serverRow.is_default
    existing.sortOrder = serverRow.sort_order
    existing.payrollDay = serverRow.payroll_day
    existing.halfTaxMonth = serverRow.half_tax_month
    existing.monthlyGoal = serverRow.monthly_goal
    existing.archivedAt = archivedAt
    existing.deletedAt = deletedAt
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func markJobClean(id: String) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func markJobDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    deletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.deletedAt = deletedAt
    existing.isDefault = false
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  internal func rebaseJob(
    id: String,
    serverRow: SyncJobRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    archivedAt: Date?,
    deletedAt: Date?,
    newSnapshot: JobServerSnapshot,
    localDirtyFields: Set<JobField>
  ) {
    autoMergeJob(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      archivedAt: archivedAt,
      deletedAt: deletedAt,
      newSnapshot: newSnapshot,
      localDirtyFields: localDirtyFields
    )
  }

  internal func resolveJobConflictKeepServer(id: String, serverSnapshot: JobServerSnapshot) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.name = serverSnapshot.name
    existing.color = serverSnapshot.color
    existing.currency = serverSnapshot.currency
    existing.isDefault = serverSnapshot.isDefault
    existing.sortOrder = serverSnapshot.sortOrder
    existing.payrollDay = serverSnapshot.payrollDay
    existing.halfTaxMonth = serverSnapshot.halfTaxMonth
    existing.monthlyGoal = serverSnapshot.monthlyGoal
    existing.archivedAt = serverSnapshot.archivedAt
    existing.deletedAt = serverSnapshot.deletedAt
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func resolveJobConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  /// Mark a shift as successfully pushed (clean)
  internal func markShiftPushed(
    id: String,
    serverRow: SyncShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: UserShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    // Update with canonical server values
    existing.jobId = serverRow.job_id
    existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
    existing.startTime = serverRow.start_time
    existing.endTime = serverRow.end_time
    existing.note = ShiftNoteSupport.normalize(serverRow.note)
    existing.customPauseWindows = PauseWindowSupport.normalize(serverRow.custom_pause_windows)
      .flatMap { pauseWindows in
        try? kCanonicalJSONEncoder.encode(pauseWindows)
      }
    existing.customSupplements = serverRow.custom_supplements.flatMap { supplements in
      try? kCanonicalJSONEncoder.encode(supplements)
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
  internal func markShiftClean(id: String) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  /// Mark a shift as successfully deleted
  internal func markShiftDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  /// Rebase a shift (update server metadata, keep local dirty fields)
  internal func rebaseShift(  // swiftlint:disable:this function_parameter_count
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
  internal func resolveShiftConflictKeepServer(id: String, serverSnapshot: UserShiftServerSnapshot)
  {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    // Overwrite local with server snapshot
    existing.jobId = serverSnapshot.jobId
    existing.shiftDate = dateFormatter.date(from: serverSnapshot.shiftDate) ?? existing.shiftDate
    existing.startTime = serverSnapshot.startTime
    existing.endTime = serverSnapshot.endTime
    existing.note = serverSnapshot.note
    existing.customPauseWindows = serverSnapshot.customPauseWindows
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
  internal func resolveShiftConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    // Update server revision so next push uses correct revision
    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
    // Keep dirtyFieldKeys - they contain the fields we want to push
  }

  // MARK: - Push Operations for Events

  internal func markEventPushed(
    id: String,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: EventServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    existing.startDate = dateFormatter.date(from: serverRow.start_date) ?? existing.startDate
    existing.endDate = dateFormatter.date(from: serverRow.end_date) ?? existing.endDate
    existing.isAllDay = serverRow.is_all_day
    existing.startTime = serverRow.start_time
    existing.endTime = serverRow.end_time
    existing.note = serverRow.note
    existing.notificationMinutesArray =
      LocalEvent.normalizedReminderMinutes(serverRow.notification_minutes_array)
    existing.notificationAnchorTime =
      LocalEvent.normalizedAnchorTime(serverRow.notification_anchor_time)
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func markEventClean(id: String) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func markEventDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  internal func rebaseEvent(
    id: String,
    serverRow: SyncEventRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?,
    newSnapshot: EventServerSnapshot,
    localDirtyFields: Set<EventField>
  ) {
    autoMergeEvent(
      id: id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRevision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newSnapshot,
      localDirtyFields: localDirtyFields
    )
  }

  internal func resolveEventConflictKeepServer(id: String, serverSnapshot: EventServerSnapshot) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    existing.startDate = dateFormatter.date(from: serverSnapshot.startDate) ?? existing.startDate
    existing.endDate = dateFormatter.date(from: serverSnapshot.endDate) ?? existing.endDate
    existing.isAllDay = serverSnapshot.isAllDay
    existing.startTime = serverSnapshot.startTime
    existing.endTime = serverSnapshot.endTime
    existing.note = serverSnapshot.note
    existing.notificationMinutesArray =
      LocalEvent.normalizedReminderMinutes(serverSnapshot.notificationMinutesArray)
    existing.notificationAnchorTime =
      LocalEvent.normalizedAnchorTime(serverSnapshot.notificationAnchorTime)
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.serverDeletedAt = serverSnapshot.deletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func resolveEventConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalEvent>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Push Operations for Recurring Shifts

  internal func markRecurringShiftPushed(
    id: String,
    serverRow: SyncRecurringShiftRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.jobId = serverRow.job_id
    existing.startTime = serverRow.cleanStartTime
    existing.endTime = serverRow.cleanEndTime
    existing.repeatIntervalWeeks = serverRow.repeat_interval_weeks
    existing.selectedDays = (try? kCanonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
    existing.endCondition = serverRow.end_condition.flatMap { endCondition in
      try? kCanonicalJSONEncoder.encode(endCondition)
    }
    existing.exclusions = serverRow.exclusions.flatMap { exclusions in
      try? kCanonicalJSONEncoder.encode(exclusions)
    }
    existing.dateSpecificPauseWindows =
      PauseWindowSupport.normalize(serverRow.date_specific_pause_windows)
      .flatMap { pauseWindows in
        try? kCanonicalJSONEncoder.encode(pauseWindows)
      }
    existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap {
      supplements in
      try? kCanonicalJSONEncoder.encode(supplements)
    }
    existing.dateSpecificNotes = ShiftNoteSupport.normalizeDateSpecificNotes(
      serverRow.date_specific_notes
    )
    .flatMap { notes in
      try? kCanonicalJSONEncoder.encode(notes)
    }
    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = snapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func markRecurringShiftClean(id: String) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func markRecurringShiftDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  internal func rebaseRecurringShift(
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

  internal func resolveRecurringShiftConflictKeepServer(
    id: String, serverSnapshot: RecurringShiftServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.jobId = serverSnapshot.jobId
    existing.startTime = serverSnapshot.startTime
    existing.endTime = serverSnapshot.endTime
    existing.repeatIntervalWeeks = serverSnapshot.repeatIntervalWeeks
    existing.selectedDays = serverSnapshot.selectedDays
    existing.endCondition = serverSnapshot.endCondition
    existing.exclusions = serverSnapshot.exclusions
    existing.dateSpecificPauseWindows = serverSnapshot.dateSpecificPauseWindows
    existing.dateSpecificSupplements = serverSnapshot.dateSpecificSupplements
    existing.dateSpecificNotes = serverSnapshot.dateSpecificNotes
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.serverDeletedAt = serverSnapshot.deletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func resolveRecurringShiftConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Push Operations for Wage Snapshots

  internal func markWageSnapshotPushed(
    id: String,
    serverRow: SyncWageSnapshotRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: WageSnapshotServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    existing.jobId = serverRow.job_id
    existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
    existing.hourlyWage = serverRow.hourly_wage
    existing.wageLevel = serverRow.wage_level
    existing.tariffTypeId = serverRow.tariff_type_id
    existing.supplements = (try? kCanonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
    existing.overtime =
      (try? kCanonicalJSONEncoder.encode(serverRow.overtime ?? .disabled)) ?? Data()
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

  internal func markWageSnapshotClean(id: String) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func markWageSnapshotDeleted(
    id: String,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    serverDeletedAt: Date?
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverUpdatedAt = serverUpdatedAt
    existing.serverRevision = serverRevision
    existing.serverDeletedAt = serverDeletedAt
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  // swiftlint:disable:next function_parameter_count
  internal func rebaseWageSnapshot(
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

  internal func resolveWageSnapshotConflictKeepServer(
    id: String, serverSnapshot: WageSnapshotServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = isoDateFormatter

    existing.jobId = serverSnapshot.jobId
    existing.fromDate = serverSnapshot.fromDate.flatMap { dateFormatter.date(from: $0) }
    existing.hourlyWage = serverSnapshot.hourlyWage
    existing.wageLevel = serverSnapshot.wageLevel
    existing.tariffTypeId = serverSnapshot.tariffTypeId
    existing.supplements = serverSnapshot.supplements
    existing.overtime = serverSnapshot.overtime
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

  internal func resolveWageSnapshotConflictKeepLocal(id: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalWageSnapshot>(
      predicate: #Predicate { $0.id == id }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Push Operations for User Settings

  internal func markUserSettingsPushed(
    userId: String,
    serverRow: SyncUserSettingsRow,
    serverUpdatedAt: Date,
    serverRevision: Int64,
    snapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    let dateFormatter = FormatterCache.iso8601Formatter()

    existing.monthlyGoal = serverRow.monthly_goal
    existing.monthlyGoalsByMonth = serverRow.monthly_goals_by_month ?? [:]
    existing.defaultShiftsView = serverRow.default_shifts_view
    existing.profilePictureUrl = serverRow.profile_picture_url
    existing.payrollDay = serverRow.payroll_day
    existing.theme = serverRow.theme
    existing.calendarContentColorStyle = serverRow.calendar_content_color_style ?? "workplace"
    existing.showDashboardClockButtons = serverRow.show_dashboard_clock_buttons ?? true
    existing.aiDataSharingEnabled = serverRow.ai_data_sharing_enabled ?? false
    existing.wageyShowcaseSeen = serverRow.wagey_showcase_seen ?? false
    existing.halfTaxMonth = serverRow.half_tax_month
    existing.currency = serverRow.currency
    existing.defaultStartupTab = serverRow.default_startup_tab
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

  internal func markUserSettingsClean(userId: String) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.conflictServerSnapshot = nil
  }

  internal func rebaseUserSettings(
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

  internal func resolveUserSettingsConflictKeepServer(
    userId: String, serverSnapshot: UserSettingsServerSnapshot
  ) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.monthlyGoal = serverSnapshot.monthlyGoal
    existing.monthlyGoalsByMonth = serverSnapshot.monthlyGoalsByMonth
    existing.defaultShiftsView = serverSnapshot.defaultShiftsView
    existing.profilePictureUrl = serverSnapshot.profilePictureUrl
    existing.payrollDay = serverSnapshot.payrollDay
    existing.theme = serverSnapshot.theme
    existing.calendarContentColorStyle = serverSnapshot.calendarContentColorStyle
    existing.showDashboardClockButtons = serverSnapshot.showDashboardClockButtons
    existing.aiDataSharingEnabled = serverSnapshot.aiDataSharingEnabled
    existing.wageyShowcaseSeen = serverSnapshot.wageyShowcaseSeen
    existing.halfTaxMonth = serverSnapshot.halfTaxMonth
    existing.currency = serverSnapshot.currency
    existing.defaultStartupTab = serverSnapshot.defaultStartupTab
    existing.lastActive = serverSnapshot.lastActive
    existing.serverUpdatedAt = serverSnapshot.updatedAt
    existing.serverRevision = serverSnapshot.revision
    existing.syncStatus = .clean
    existing.dirtyFieldKeys = []
    existing.lastSyncedSnapshot = serverSnapshot.encoded()
    existing.conflictServerSnapshot = nil
    existing.localUpdatedAt = Date()
  }

  internal func resolveUserSettingsConflictKeepLocal(userId: String, serverRevision: Int64) {
    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    guard let existing = try? modelContext.fetch(descriptor).first else {

      return

    }

    existing.serverRevision = serverRevision
    existing.syncStatus = .dirty
    existing.conflictServerSnapshot = nil
  }

  // MARK: - Entitlement Cache Operations

  /// Upsert entitlement cache from server entitlement
  internal func upsertEntitlementCache(userId: String, entitlement: ServerEntitlement) throws {
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
  internal func deleteEntitlementCache(userId: String) throws {
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
  internal func insertPendingJWSUpload(_ upload: LocalPendingJWSUpload) throws {
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
  internal func deletePendingJWSUpload(transactionId: String) throws {
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
      predicate: #Predicate { $0.transactionId == transactionId }
    )

    for upload in try modelContext.fetch(descriptor) {
      modelContext.delete(upload)
    }

    try modelContext.save()
  }

  /// Schedule next retry for a failed upload (exponential backoff)
  internal func schedulePendingJWSUploadRetry(transactionId: String) throws {
    let descriptor = FetchDescriptor<LocalPendingJWSUpload>(
      predicate: #Predicate { $0.transactionId == transactionId }
    )

    if let upload = try modelContext.fetch(descriptor).first {
      upload.scheduleNextRetry()
      try modelContext.save()
    }
  }

  // MARK: - Shared Shifts Operations

  /// Save friend rows to cache, replacing existing entries for this viewer
  internal func saveSharers(
    _ sharers: [SharedUser],
    chatOnlyUserIds: Set<String> = [],
    for viewerId: String
  ) throws {
    // Delete existing sharers for this viewer
    let descriptor = FetchDescriptor<LocalSharer>(
      predicate: #Predicate { $0.viewerId == viewerId }
    )
    for existing in try modelContext.fetch(descriptor) {
      modelContext.delete(existing)
    }

    // Insert new sharers
    for sharer in sharers {
      let localSharer = LocalSharer.from(
        sharedUser: sharer,
        viewerId: viewerId,
        canViewSharedShifts: !chatOnlyUserIds.contains(sharer.id)
      )
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
  internal func saveSharedShifts(
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
    if shifts.isEmpty, !existing.isEmpty, !forceReplace {
      kLocalStoreLogger.warning(
        """
        API returned empty shared shifts for \(year)-\(month) \
        (owner: \(ownerId.prefix(kLogIdentifierPrefixLength))...), \
        keeping \(existing.count) cached shifts
        """
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
  internal func clearSharedData(for viewerId: String) throws {
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
  internal func clearSharedShifts(ownerId: String, viewerId: String) throws {
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
  internal func saveShiftPreviews(_ previews: [SharerShiftPreview], for viewerId: String) throws {
    // Delete existing previews for this viewer (only for sharers in this batch)
    let sharerIds = Set(previews.map(\.sharerId))
    if !sharerIds.isEmpty {
      let descriptor = FetchDescriptor<LocalShiftPreview>(
        predicate: #Predicate { $0.viewerId == viewerId }
      )
      for existing in try modelContext.fetch(descriptor)
      where sharerIds.contains(existing.sharerId) {
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
