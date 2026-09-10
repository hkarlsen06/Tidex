import Combine

internal enum AddShiftSubmitBlocker: Hashable {
  case invalidEventDateRange
  case missingEventNote
  case missingTimes
  case noAvailableJob
  case noEventDate
  case noRecurringDays
  case noSelectedJob
  case noSingleDates
}

/// Coordinates state between AddShiftView/ViewModel and the tab bar
/// Used to:
/// - Communicate whether a shift can be submitted (for tab icon color)
/// - Trigger add action from tab bar tap
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

  /// Whether the current Add tab form has user-entered content that can be cleared.
  @Published internal private(set) var hasContent: Bool = false

  /// Whether the moved Add tab undo control should be shown in shared bottom chrome.
  @Published internal private(set) var canShowStartFreshControl: Bool = false

  private let triggerAddSubject: PassthroughSubject<Void, Never> = .init()
  private let cycleModeSubject: PassthroughSubject<Void, Never> = .init()
  private let startFreshSubject: PassthroughSubject<Void, Never> = .init()

  /// Publisher for triggering the add action from outside (tab bar tap)
  internal var triggerAddAction: AnyPublisher<Void, Never> {
    triggerAddSubject.eraseToAnyPublisher()
  }

  /// Publisher for cycling add modes when the Add tab is reselected.
  internal var cycleModeAction: AnyPublisher<Void, Never> {
    cycleModeSubject.eraseToAnyPublisher()
  }

  /// Publisher for triggering the Add tab start-fresh confirmation.
  internal var startFreshAction: AnyPublisher<Void, Never> {
    startFreshSubject.eraseToAnyPublisher()
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

  /// Update whether the Add tab form has content that can be cleared.
  internal func updateHasContent(_ hasContent: Bool) {
    self.hasContent = hasContent
  }

  internal func updateCanShowStartFreshControl(_ canShowStartFreshControl: Bool) {
    self.canShowStartFreshControl = canShowStartFreshControl
  }

  /// Trigger the add action (called from MainTabView when Add tab is tapped)
  internal func triggerAdd() {
    // swiftlint:disable:next conditional_returns_on_newline
    guard canSubmit, !isLoading else { return }
    triggerAddSubject.send()
  }

  internal func triggerModeCycle() {
    guard !isLoading else { return }
    cycleModeSubject.send()
  }

  internal func triggerStartFresh() {
    guard hasContent, !isLoading else { return }
    startFreshSubject.send()
  }

  deinit {
    triggerAddSubject.send(completion: .finished)
    cycleModeSubject.send(completion: .finished)
    startFreshSubject.send(completion: .finished)
  }
}
