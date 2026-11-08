import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

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
    let visibleShifts = #Predicate<LocalUserShift> { shift in
      shift.userId == userId && shift.serverDeletedAt == nil
        && shift.syncStatusRaw != "pendingDelete"
    }
    let matchingJob = #Predicate<LocalUserShift> { shift in
      jobId == nil || shift.jobId == jobId || (includeLegacyNil && shift.jobId == nil)
    }
    let withinDates = #Predicate<LocalUserShift> { shift in
      shift.shiftDate >= startDate && shift.shiftDate <= endDate
    }
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate<LocalUserShift> { shift in
        visibleShifts.evaluate(shift) && matchingJob.evaluate(shift)
          && withinDates.evaluate(shift)
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
}
