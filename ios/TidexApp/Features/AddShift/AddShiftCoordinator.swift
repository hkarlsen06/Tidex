import Combine

enum AddShiftSubmitBlocker: Hashable {
  case noAvailableJob
  case noSelectedJob
  case noSingleDates
  case noRecurringDays
  case missingTimes
  case noEventDate
  case invalidEventDateRange
  case missingEventNote
}

/// Coordinates state between AddShiftView/ViewModel and the tab bar
/// Used to:
/// - Communicate whether a shift can be submitted (for tab icon color)
/// - Trigger add action from tab bar tap
/// - Track current mode for proper action routing
@MainActor
final class AddShiftCoordinator: ObservableObject {
  static let shared = AddShiftCoordinator()

  /// Whether a shift can currently be submitted (dates/days selected + valid times)
  @Published private(set) var canSubmit: Bool = false

  /// Current add mode - determines which action to trigger
  @Published private(set) var currentMode: AddShiftMode = .single

  /// Whether the view is currently loading (submitting)
  @Published private(set) var isLoading: Bool = false

  /// Whether the current add-shift context requires explicit job selection before submit.
  @Published private(set) var requiresJobSelection: Bool = false

  /// Currently selected job for add-shift context.
  @Published private(set) var selectedJobId: String?

  /// Reasons the Add action is currently blocked.
  @Published private(set) var submitBlockers: [AddShiftSubmitBlocker] = []

  /// Publisher for triggering the add action from outside (tab bar tap)
  let triggerAddAction = PassthroughSubject<Void, Never>()

  /// Publisher for cycling add modes when the Add tab is reselected.
  let cycleModeAction = PassthroughSubject<Void, Never>()

  private init() {}

  /// Update the can submit state (called by AddShiftViewModel)
  func updateCanSubmit(_ canSubmit: Bool) {
    self.canSubmit = canSubmit
  }

  /// Update the current mode (called by AddShiftViewModel)
  func updateMode(_ mode: AddShiftMode) {
    self.currentMode = mode
  }

  /// Update the loading state (called by AddShiftViewModel)
  func updateIsLoading(_ isLoading: Bool) {
    self.isLoading = isLoading
  }

  /// Update job selection context (called by AddShiftViewModel)
  func updateJobSelection(selectedJobId: String?, requiresJobSelection: Bool) {
    self.selectedJobId = selectedJobId
    self.requiresJobSelection = requiresJobSelection
  }

  /// Update blockers that explain why submit is unavailable.
  func updateSubmitBlockers(_ blockers: [AddShiftSubmitBlocker]) {
    submitBlockers = blockers
  }

  /// Trigger the add action (called from MainTabView when Add tab is tapped)
  func triggerAdd() {
    guard canSubmit && !isLoading else { return }
    triggerAddAction.send()
  }

  func triggerModeCycle() {
    cycleModeAction.send()
  }
}
