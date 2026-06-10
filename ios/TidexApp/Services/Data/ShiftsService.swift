import Foundation
import os.log
import Supabase

private let kShiftsServiceLogger: Logger = Logger(
  subsystem: "com.tidex.app",
  category: "ShiftsService"
)

/// Service for fetching shifts and recurring shifts from Supabase
@MainActor
internal final class ShiftsService: ObservableObject {
  internal static let shared: ShiftsService = ShiftsService()

  @Published internal private(set) var shifts: [ShiftRow] = []
  @Published internal private(set) var recurringShifts: [RecurringShiftRow] = []
  @Published internal private(set) var isLoading: Bool = false
  @Published internal private(set) var error: Error?

  private init() {
    // Singleton.
  }

  // MARK: - Public API

  /// Fetch shifts for a date range
  /// - Parameters:
  ///   - userId: User ID to fetch shifts for
  ///   - startDate: Start date (YYYY-MM-DD)
  ///   - endDate: End date (YYYY-MM-DD)
  ///   - limit: Maximum number of shifts to fetch
  /// - Returns: Array of shift rows
  internal func fetchShifts(
    for userId: String,
    startDate: String,
    endDate: String,
    limit: Int = 100
  ) async throws -> [ShiftRow] {
    isLoading = true
    error = nil
    defer { isLoading = false }

    return try await withTaskCancellationHandler {
      do {
        // Check for cancellation before making network request
        try Task.checkCancellation()

        let response: [ShiftRow] =
          try await supabase
          .from("user_shifts")
          .select()
          .eq("user_id", value: userId)
          .gte("shift_date", value: startDate)
          .lte("shift_date", value: endDate)
          .order("shift_date", ascending: false)
          .limit(limit)
          .execute()
          .value

        // Check for cancellation after network request
        try Task.checkCancellation()

        shifts = response
        return response
      } catch is CancellationError {
        kShiftsServiceLogger.info("Shifts fetch was cancelled")
        throw CancellationError()
      } catch {
        self.error = error
        throw error
      }
    } onCancel: {
      kShiftsServiceLogger.info("Shifts fetch cancellation requested")
    }
  }

  /// Fetch all recurring shifts for a user
  /// - Parameter userId: User ID to fetch recurring shifts for
  /// - Returns: Array of recurring shift rows
  internal func fetchRecurringShifts(for userId: String) async throws -> [RecurringShiftRow] {
    return try await withTaskCancellationHandler {
      do {
        // Check for cancellation before making network request
        try Task.checkCancellation()

        let response: [RecurringShiftRow] =
          try await supabase
          .from("recurring_shifts")
          .select()
          .eq("user_id", value: userId)
          .execute()
          .value

        // Check for cancellation after network request
        try Task.checkCancellation()

        recurringShifts = response
        return response
      } catch is CancellationError {
        kShiftsServiceLogger.info("Recurring shifts fetch was cancelled")
        throw CancellationError()
      } catch {
        self.error = error
        throw error
      }
    } onCancel: {
      kShiftsServiceLogger.info("Recurring shifts fetch cancellation requested")
    }
  }

  /// Fetch both shifts and recurring shifts for a date range
  /// - Parameters:
  ///   - userId: User ID
  ///   - startDate: Start date (YYYY-MM-DD)
  ///   - endDate: End date (YYYY-MM-DD)
  /// - Returns: Tuple of (shifts, recurringShifts)
  internal func fetchAllShifts(
    for userId: String,
    startDate: String,
    endDate: String
  ) async throws -> (shifts: [ShiftRow], recurring: [RecurringShiftRow]) {
    // Fetch both in parallel
    async let shiftsTask: [ShiftRow] = fetchShifts(
      for: userId,
      startDate: startDate,
      endDate: endDate
    )
    async let recurringTask: [RecurringShiftRow] = fetchRecurringShifts(for: userId)

    let (fetchedShifts, fetchedRecurring): ([ShiftRow], [RecurringShiftRow]) = try await (
      shiftsTask, recurringTask
    )
    return (shifts: fetchedShifts, recurring: fetchedRecurring)
  }

  deinit {
    // Singleton.
  }
}
