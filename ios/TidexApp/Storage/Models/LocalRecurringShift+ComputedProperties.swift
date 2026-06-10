import Foundation

extension LocalRecurringShift {
  internal var syncStatus: SyncStatus {
    get { SyncStatus(rawValue: syncStatusRaw) ?? .clean }
    set { syncStatusRaw = newValue.rawValue }
  }

  /// Decoded dirty fields
  /// When decoding fails (corrupted data), treats record as fully dirty to prevent silent data loss
  internal var dirtyFieldKeys: Set<RecurringShiftField> {
    get {
      guard !dirtyFields.isEmpty else {
        return []
      }

      do {
        let keys: [String] = try kSyncJSONDecoder.decode([String].self, from: dirtyFields)
        return Set(keys.compactMap { RecurringShiftField(rawValue: $0) })
      } catch {
        SyncLogger.shared.log(
          "Corrupted dirtyFields for recurring shift \(id), treating as fully dirty: \(error.localizedDescription)",
          level: .error
        )
        return Set(RecurringShiftField.allCases)
      }
    }
    set {
      let keys: [String] = newValue.map(\.rawValue)
      dirtyFields = (try? kCanonicalJSONEncoder.encode(keys)) ?? Data()
    }
  }

  /// Decoded selected days
  internal var decodedSelectedDays: SelectedDays {
    get {
      if let decoded = try? kSyncJSONDecoder.decode(SelectedDays.self, from: selectedDays),
        !decoded.isEmpty
      {
        return decoded
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = try? kSyncJSONDecoder.decode(SelectedDays.self, from: snapshot.selectedDays),
        !fallback.isEmpty
      {
        SyncLogger.shared.log(
          "Recovered corrupt selectedDays for recurring shift \(id) from last synced snapshot",
          level: .warning
        )
        return fallback
      }

      return [:]
    }
    set {
      selectedDays = (try? kCanonicalJSONEncoder.encode(newValue)) ?? Data()
    }
  }

  /// Decoded end condition
  internal var decodedEndCondition: EndCondition? {
    get {
      guard let data: Data = endCondition else {
        return nil
      }
      if let decoded = try? kSyncJSONDecoder.decode(EndCondition.self, from: data) {
        return decoded
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = snapshot.endCondition.flatMap({ endCondition in
          try? kSyncJSONDecoder.decode(EndCondition.self, from: endCondition)
        })
      {
        SyncLogger.shared.log(
          "Recovered corrupt endCondition for recurring shift \(id) from last synced snapshot",
          level: .warning
        )
        return fallback
      }

      return nil
    }
    set {
      endCondition = newValue.flatMap { try? kCanonicalJSONEncoder.encode($0) }
    }
  }

  /// Decoded exclusions
  internal var decodedExclusions: [String] {
    get {
      guard let data: Data = exclusions else {
        return []
      }
      if let decoded = try? kSyncJSONDecoder.decode([String].self, from: data) {
        return decoded
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = snapshot.exclusions.flatMap({ exclusions in
          try? kSyncJSONDecoder.decode([String].self, from: exclusions)
        })
      {
        SyncLogger.shared.log(
          "Recovered corrupt exclusions for recurring shift \(id) from last synced snapshot",
          level: .warning
        )
        return fallback
      }

      return []
    }
    set {
      exclusions = newValue.isEmpty ? nil : (try? kCanonicalJSONEncoder.encode(newValue))
    }
  }

  /// Decoded date-specific supplements
  internal var decodedDateSpecificSupplements: [String: CustomSupplementsData] {
    get {
      guard let data: Data = dateSpecificSupplements else {
        return [:]
      }
      if let decoded = try? kSyncJSONDecoder.decode(
        [String: CustomSupplementsData].self,
        from: data
      ) {
        return decoded
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = snapshot.dateSpecificSupplements.flatMap({ supplements in
          try? kSyncJSONDecoder.decode([String: CustomSupplementsData].self, from: supplements)
        })
      {
        SyncLogger.shared.log(
          """
          Recovered corrupt dateSpecificSupplements for recurring shift \(id) from last synced snapshot
          """,
          level: .warning
        )
        return fallback
      }

      return [:]
    }
    set {
      dateSpecificSupplements =
        newValue.isEmpty ? nil : (try? kCanonicalJSONEncoder.encode(newValue))
    }
  }

  /// Decoded date-specific pause windows
  internal var decodedDateSpecificPauseWindows: DateSpecificPauseWindows {
    get {
      guard let data: Data = dateSpecificPauseWindows else {
        return [:]
      }
      if let decoded = try? kSyncJSONDecoder.decode(DateSpecificPauseWindows.self, from: data),
        let normalized = PauseWindowSupport.normalize(decoded)
      {
        return normalized
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = snapshot.dateSpecificPauseWindows.flatMap({ pauseWindows in
          try? kSyncJSONDecoder.decode(DateSpecificPauseWindows.self, from: pauseWindows)
        }),
        let normalized = PauseWindowSupport.normalize(fallback)
      {
        SyncLogger.shared.log(
          """
          Recovered corrupt dateSpecificPauseWindows for recurring shift \(id) from last synced snapshot
          """,
          level: .warning
        )
        return normalized
      }

      return [:]
    }
    set {
      dateSpecificPauseWindows = PauseWindowSupport.normalize(newValue).flatMap { pauseWindows in
        try? kCanonicalJSONEncoder.encode(pauseWindows)
      }
    }
  }

  /// Decoded date-specific notes
  internal var decodedDateSpecificNotes: [String: String] {
    get {
      guard let data: Data = dateSpecificNotes else {
        return [:]
      }
      if let decoded = try? kSyncJSONDecoder.decode([String: String].self, from: data),
        let normalized = ShiftNoteSupport.normalizeDateSpecificNotes(decoded)
      {
        return normalized
      }

      if let snapshot = RecurringShiftServerSnapshot.decode(from: lastSyncedSnapshot),
        let fallback = snapshot.dateSpecificNotes.flatMap({ notes in
          try? kSyncJSONDecoder.decode([String: String].self, from: notes)
        }),
        let normalized = ShiftNoteSupport.normalizeDateSpecificNotes(fallback)
      {
        SyncLogger.shared.log(
          """
          Recovered corrupt dateSpecificNotes for recurring shift \(id) from last synced snapshot
          """,
          level: .warning
        )
        return normalized
      }

      return [:]
    }
    set {
      dateSpecificNotes = ShiftNoteSupport.normalizeDateSpecificNotes(newValue).flatMap { notes in
        try? kCanonicalJSONEncoder.encode(notes)
      }
    }
  }

  /// Whether this recurring shift is soft-deleted
  internal var isDeleted: Bool {
    serverDeletedAt != nil
  }
}
