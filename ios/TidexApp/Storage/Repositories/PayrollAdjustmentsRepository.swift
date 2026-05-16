import Combine
import Foundation
import SwiftData
import os.log

@MainActor
final class PayrollAdjustmentsRepository: ObservableObject {
  static let shared = PayrollAdjustmentsRepository()

  private let localStore: LocalStore
  private let syncCoordinator: SyncCoordinator
  private let logger = Logger(subsystem: "com.tidex.app", category: "PayrollAdjustmentsRepository")

  private init(
    localStore: LocalStore? = nil,
    syncCoordinator: SyncCoordinator? = nil
  ) {
    self.localStore = localStore ?? LocalStore.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
  }

  func getAdjustments(
    for userId: String,
    payoutStart: Date? = nil,
    payoutEnd: Date? = nil,
    includeDeleted: Bool = false
  ) -> [PayrollAdjustment] {
    let context = localStore.mainContext
    let descriptor = FetchDescriptor<LocalPayrollAdjustment>(
      predicate: #Predicate { $0.userId == userId },
      sortBy: [SortDescriptor(\LocalPayrollAdjustment.payoutDate)]
    )

    do {
      return try context.fetch(descriptor)
        .filter { local in
          (includeDeleted
            || (local.serverDeletedAt == nil && local.syncStatus != .pendingDelete))
            && payoutStart.map { local.payoutDate >= $0 } ?? true
            && payoutEnd.map { local.payoutDate < $0 } ?? true
        }
        .map { $0.toPayrollAdjustment() }
    } catch {
      logger.error("Failed to fetch payroll adjustments: \(error.localizedDescription)")
      return []
    }
  }

  // swiftlint:disable:next function_parameter_count
  func createAdjustment(
    userId: String,
    jobId: String?,
    amount: Double,
    currency: String,
    category: PayrollAdjustmentCategory,
    taxTreatment: PayrollAdjustmentTaxTreatment,
    description: String,
    note: String? = nil,
    earnedFromDate: Date? = nil,
    earnedToDate: Date? = nil,
    payoutDate: Date
  ) async throws -> PayrollAdjustment {
    let adjustment = try await localStore.storeActor.createPayrollAdjustment(
      userId: userId,
      jobId: jobId,
      amount: amount,
      currency: currency,
      category: category,
      taxTreatment: taxTreatment,
      description: description,
      note: note,
      earnedFromDate: earnedFromDate,
      earnedToDate: earnedToDate,
      payoutDate: payoutDate
    )
    triggerSync(userId: userId)
    return adjustment
  }

  func deleteAdjustment(id: String, userId: String) async throws {
    try await localStore.storeActor.markPayrollAdjustmentPendingDelete(id: id)
    triggerSync(userId: userId)
  }

  // swiftlint:disable:next function_parameter_count
  func updateAdjustment(
    id: String,
    userId: String,
    jobId: String?,
    amount: Double,
    currency: String,
    category: PayrollAdjustmentCategory,
    taxTreatment: PayrollAdjustmentTaxTreatment,
    description: String,
    note: String? = nil,
    earnedFromDate: Date? = nil,
    earnedToDate: Date? = nil,
    payoutDate: Date
  ) async throws -> PayrollAdjustment {
    let adjustment = try await localStore.storeActor.updatePayrollAdjustment(
      id: id,
      jobId: jobId,
      amount: amount,
      currency: currency,
      category: category,
      taxTreatment: taxTreatment,
      description: description,
      note: note,
      earnedFromDate: earnedFromDate,
      earnedToDate: earnedToDate,
      payoutDate: payoutDate
    )
    triggerSync(userId: userId)
    return adjustment
  }

  private func triggerSync(userId: String) {
    Task {
      _ = await syncCoordinator.sync(reason: .localChange, userId: userId)
    }
  }
}
