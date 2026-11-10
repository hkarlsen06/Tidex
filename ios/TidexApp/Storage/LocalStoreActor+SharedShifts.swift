import Foundation
import SwiftData
import os.log

extension LocalStoreActor {

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
    let zoneKey = "friends.sharedCalendarCacheZone.\(viewerId)"
    let viewerZone = TimeZone.current.identifier
    if let savedZone = UserDefaults.standard.string(forKey: zoneKey), savedZone != viewerZone {
      let staleShifts = FetchDescriptor<LocalSharedShift>(
        predicate: #Predicate { $0.viewerId == viewerId })
      for row in try modelContext.fetch(staleShifts) { modelContext.delete(row) }
      let staleRecords = FetchDescriptor<LocalSharedShiftFetchRecord>(
        predicate: #Predicate { $0.viewerId == viewerId })
      for row in try modelContext.fetch(staleRecords) { modelContext.delete(row) }
    }
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
    UserDefaults.standard.set(viewerZone, forKey: zoneKey)
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
