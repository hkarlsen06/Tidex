import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "com.tidex.app", category: "SharedShiftsRepository")

// MARK: - Shared Shifts Repository

/// Repository for locally cached shared shifts
/// Server is source of truth - local data is replaced on each fetch
@MainActor
final class SharedShiftsRepository {
  static let shared = SharedShiftsRepository()

  struct CachedFriendsSnapshot {
    let sharers: [SharedUser]
    let chatOnlyUserIds: Set<String>
  }

  private let localStore: LocalStore

  private init(localStore: LocalStore? = nil) {
    self.localStore = localStore ?? LocalStore.shared
  }

  // MARK: - Sharer Operations

  /// Get all cached sharers for a viewer
  /// - Parameter viewerId: The current user's ID
  /// - Returns: Array of SharedUser objects
  func getSharers(for viewerId: String) -> [SharedUser] {
    getSharers(for: viewerId, includeHidden: false)
  }

  /// Get cached sharers for a viewer, optionally including hidden rows.
  func getSharers(for viewerId: String, includeHidden: Bool) -> [SharedUser] {
    let snapshot = getCachedFriends(for: viewerId, includeHidden: includeHidden)
    return snapshot.sharers.filter { !snapshot.chatOnlyUserIds.contains($0.id) }
  }

  /// Get cached friend rows for a viewer, including chat-only entries.
  func getCachedFriends(for viewerId: String, includeHidden: Bool) -> CachedFriendsSnapshot {
    let context = localStore.mainContext

    let descriptor: FetchDescriptor<LocalSharer>
    if includeHidden {
      descriptor = FetchDescriptor<LocalSharer>(
        predicate: #Predicate { sharer in
          sharer.viewerId == viewerId
        },
        sortBy: [SortDescriptor(\LocalSharer.cachedAt, order: .reverse)]
      )
    } else {
      descriptor = FetchDescriptor<LocalSharer>(
        predicate: #Predicate { sharer in
          sharer.viewerId == viewerId && !sharer.hidden
        },
        sortBy: [SortDescriptor(\LocalSharer.cachedAt, order: .reverse)]
      )
    }

    do {
      let localSharers = try context.fetch(descriptor)
      return CachedFriendsSnapshot(
        sharers: localSharers.map { $0.toSharedUser() },
        chatOnlyUserIds: Set(
          localSharers
            .filter { !$0.canViewSharedShifts }
            .map(\.sharerId)
        )
      )
    } catch {
      logger.error("Failed to fetch cached sharers: \(error.localizedDescription)")
      return CachedFriendsSnapshot(sharers: [], chatOnlyUserIds: [])
    }
  }

  /// Save friend rows to local cache, replacing existing entries
  /// - Parameters:
  ///   - sharers: Array of friend rows shown in the Friends tab
  ///   - chatOnlyUserIds: IDs that should open chat directly instead of shift details
  ///   - viewerId: The current user's ID
  func saveSharers(
    _ sharers: [SharedUser],
    chatOnlyUserIds: Set<String> = [],
    for viewerId: String
  ) async {
    do {
      try await localStore.storeActor.saveSharers(
        sharers,
        chatOnlyUserIds: chatOnlyUserIds,
        for: viewerId
      )
      logger.info("Saved \(sharers.count) sharers to cache")
    } catch {
      logger.error("Failed to save sharers: \(error.localizedDescription)")
    }
  }

  /// Get a specific sharer by ID
  /// - Parameters:
  ///   - sharerId: The sharer's user ID
  ///   - viewerId: The current user's ID
  /// - Returns: SharedUser if found
  func getSharer(sharerId: String, viewerId: String) -> SharedUser? {
    let context = localStore.mainContext
    let compositeKey = "\(viewerId):\(sharerId)"

    let descriptor = FetchDescriptor<LocalSharer>(
      predicate: #Predicate { $0.compositeKey == compositeKey }
    )

    do {
      guard let localSharer = try context.fetch(descriptor).first else {
        return nil
      }
      return localSharer.toSharedUser()
    } catch {
      logger.error("Failed to fetch sharer: \(error.localizedDescription)")
      return nil
    }
  }

  // MARK: - Shared Shift Operations

  /// Get cached shared shifts for a specific owner and month
  /// - Parameters:
  ///   - ownerId: The owner's user ID
  ///   - viewerId: The current user's ID
  ///   - year: Year
  ///   - month: Month (1-12)
  /// - Returns: Array of ShiftWithComputations
  func getSharedShifts(
    ownerId: String,
    viewerId: String,
    year: Int,
    month: Int
  ) -> [ShiftWithComputations] {
    let context = localStore.mainContext

    let descriptor = FetchDescriptor<LocalSharedShift>(
      predicate: #Predicate { shift in
        shift.ownerId == ownerId && shift.viewerId == viewerId && shift.year == year
          && shift.month == month
      },
      sortBy: [SortDescriptor(\LocalSharedShift.shiftDate, order: .reverse)]
    )

    do {
      let localShifts = try context.fetch(descriptor)
      return localShifts.map { $0.toShiftWithComputations() }
    } catch {
      logger.error("Failed to fetch cached shared shifts: \(error.localizedDescription)")
      return []
    }
  }

  /// Save shared shifts from API response, replacing existing entries for the month
  /// - Parameters:
  ///   - shifts: Array of SharedShiftData from API
  ///   - ownerId: The owner's user ID
  ///   - viewerId: The current user's ID
  ///   - showEarnings: Whether earnings are visible for this share
  ///   - year: Year
  ///   - month: Month (1-12)
  func saveSharedShifts(
    _ shifts: [SharedShiftData],
    ownerId: String,
    viewerId: String,
    showEarnings: Bool,
    year: Int,
    month: Int
  ) async {
    do {
      try await localStore.storeActor.saveSharedShifts(
        shifts,
        ownerId: ownerId,
        viewerId: viewerId,
        showEarnings: showEarnings,
        year: year,
        month: month
      )
      logger.info("Saved \(shifts.count) shared shifts to cache for \(year)-\(month)")
    } catch {
      logger.error("Failed to save shared shifts: \(error.localizedDescription)")
    }
  }

  /// Get the last cache time for shared shifts from a specific owner/month
  /// - Parameters:
  ///   - ownerId: The owner's user ID
  ///   - viewerId: The current user's ID
  ///   - year: Year
  ///   - month: Month (1-12)
  /// - Returns: Cache timestamp or nil if not cached
  func getLastCacheTime(
    ownerId: String,
    viewerId: String,
    year: Int,
    month: Int
  ) -> Date? {
    let context = localStore.mainContext

    var descriptor = FetchDescriptor<LocalSharedShift>(
      predicate: #Predicate { shift in
        shift.ownerId == ownerId && shift.viewerId == viewerId && shift.year == year
          && shift.month == month
      },
      sortBy: [SortDescriptor(\LocalSharedShift.cachedAt, order: .reverse)]
    )
    descriptor.fetchLimit = 1

    do {
      let result = try context.fetch(descriptor)
      return result.first?.cachedAt
    } catch {
      logger.error("Failed to get cache time: \(error.localizedDescription)")
      return nil
    }
  }

  /// Clear all cached shared shifts for a viewer
  /// - Parameter viewerId: The current user's ID
  func clearAllCachedData(for viewerId: String) async {
    do {
      try await localStore.storeActor.clearSharedData(for: viewerId)
      logger.info("Cleared all shared data cache for viewer")
    } catch {
      logger.error("Failed to clear shared data cache: \(error.localizedDescription)")
    }
  }

  /// Clear cached shared shifts for a specific owner
  /// - Parameters:
  ///   - ownerId: The owner's user ID
  ///   - viewerId: The current user's ID
  func clearCachedShifts(ownerId: String, viewerId: String) async {
    do {
      try await localStore.storeActor.clearSharedShifts(ownerId: ownerId, viewerId: viewerId)
      logger.info("Cleared shared shifts cache for owner \(ownerId)")
    } catch {
      logger.error("Failed to clear shared shifts cache: \(error.localizedDescription)")
    }
  }

  // MARK: - Fetch Record Operations

  /// Check whether a specific owner/month has been fetched before.
  /// Used to distinguish "never fetched" from "fetched but empty" so that
  /// revisiting an empty month skips the loading state.
  func hasFetchRecord(
    ownerId: String,
    viewerId: String,
    year: Int,
    month: Int
  ) -> Bool {
    let context = localStore.mainContext
    let compositeKey = "\(viewerId):\(ownerId):\(year):\(month)"

    var descriptor = FetchDescriptor<LocalSharedShiftFetchRecord>(
      predicate: #Predicate { $0.compositeKey == compositeKey }
    )
    descriptor.fetchLimit = 1

    do {
      return try !context.fetch(descriptor).isEmpty
    } catch {
      logger.error("Failed to check fetch record: \(error.localizedDescription)")
      return false
    }
  }

  // MARK: - Shift Preview Operations

  /// Get cached shift previews for a viewer
  /// - Parameter viewerId: The current user's ID
  /// - Returns: Dictionary of sharer ID to SharerShiftPreview
  func getShiftPreviews(for viewerId: String) -> [String: SharerShiftPreview] {
    let context = localStore.mainContext

    let descriptor = FetchDescriptor<LocalShiftPreview>(
      predicate: #Predicate { $0.viewerId == viewerId }
    )

    do {
      let localPreviews = try context.fetch(descriptor)
      logger.info(
        "📦 Found \(localPreviews.count) cached shift previews for viewer \(viewerId.prefix(8))..."
      )
      var previewMap: [String: SharerShiftPreview] = [:]
      for localPreview in localPreviews {
        previewMap[localPreview.sharerId] = localPreview.toSharerShiftPreview()
      }
      return previewMap
    } catch {
      logger.error("Failed to fetch cached shift previews: \(error.localizedDescription)")
      return [:]
    }
  }

  /// Save shift previews to local cache
  /// - Parameters:
  ///   - previews: Array of SharerShiftPreview from API
  ///   - viewerId: The current user's ID
  func saveShiftPreviews(_ previews: [SharerShiftPreview], for viewerId: String) async {
    do {
      try await localStore.storeActor.saveShiftPreviews(previews, for: viewerId)
      logger.info("Saved \(previews.count) shift previews to cache")
    } catch {
      logger.error("Failed to save shift previews: \(error.localizedDescription)")
    }
  }
}
