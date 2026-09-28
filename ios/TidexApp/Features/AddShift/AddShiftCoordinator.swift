import Combine

internal enum AddShiftSubmitBlocker: Hashable {
  case eventCrossesMidnight
  case invalidEventDateRange
  case missingEventNote
  case missingTimes
  case noAvailableJob
  case noEventDate
  case noRecurringDays
  case noSelectedJob
  case noSingleDates
}

/// Coordinates state between AddShiftViewModel and the Add screen's save button
/// Used to:
/// - Communicate whether a shift can be submitted (for save button state)
/// - Trigger the add action from the save button
/// - Track current mode for proper action routing
@MainActor
internal final class AddShiftCoordinator: ObservableObject {
  internal static let shared: AddShiftCoordinator = .init()

  /// Whether a shift can currently be submitted (dates/days selected + valid times)
  @Published internal private(set) var canSubmit: Bool = false

  /// Current add mode - determines which action to trigger
  @Published internal private(set) var currentMode: AddShiftMode = .single

  /// Whether the view is currently loading (submitting)
  @Published internal private(set) var isLoading: Bool = false

  /// Whether the current add-shift context requires explicit job selection before submit.
  @Published internal private(set) var requiresJobSelection: Bool = false

  /// Currently selected job for add-shift context.
  @Published internal private(set) var selectedJobId: String?

  /// Reasons the Add action is currently blocked.
  @Published internal private(set) var submitBlockers: [AddShiftSubmitBlocker] = []

  private let triggerAddSubject: PassthroughSubject<Void, Never> = .init()

  /// Publisher for triggering the add action from the save button
  internal var triggerAddAction: AnyPublisher<Void, Never> {
    triggerAddSubject.eraseToAnyPublisher()
  }

  private init() {
    // Singleton.
  }

  /// Update the can submit state (called by AddShiftViewModel)
  internal func updateCanSubmit(_ canSubmit: Bool) {
    self.canSubmit = canSubmit
  }

  /// Update the current mode (called by AddShiftViewModel)
  internal func updateMode(_ mode: AddShiftMode) {
    self.currentMode = mode
  }

  /// Update the loading state (called by AddShiftViewModel)
  internal func updateIsLoading(_ isLoading: Bool) {
    self.isLoading = isLoading
  }

  /// Update job selection context (called by AddShiftViewModel)
  internal func updateJobSelection(selectedJobId: String?, requiresJobSelection: Bool) {
    self.selectedJobId = selectedJobId
    self.requiresJobSelection = requiresJobSelection
  }

  /// Update blockers that explain why submit is unavailable.
  internal func updateSubmitBlockers(_ blockers: [AddShiftSubmitBlocker]) {
    submitBlockers = blockers
  }

  /// Trigger the add action (called when the save button is tapped)
  internal func triggerAdd() {
    // swiftlint:disable:next conditional_returns_on_newline
    guard canSubmit, !isLoading else { return }
    triggerAddSubject.send()
  }

  deinit {
    triggerAddSubject.send(completion: .finished)
  }
}
