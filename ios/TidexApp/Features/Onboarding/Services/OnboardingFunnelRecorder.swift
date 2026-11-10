import Foundation

/// One row in the `onboarding_funnel_steps` table.
struct OnboardingFunnelStepRow: Encodable, Equatable {
  let user_id: String  // swiftlint:disable:this identifier_name
  let step: String
  let reached_at: String  // swiftlint:disable:this identifier_name
}

/// Records the first time a user reaches each onboarding step, for funnel analysis.
///
/// Rows go to the `onboarding_funnel_steps` table through `onboarding:recordSteps`, which ignores duplicates so the
/// first timestamp wins. Pre-auth pages wait in UserDefaults until post-auth onboarding
/// records its first step. Each pre-auth page is also sent right away without a user,
/// keyed by a random install id, so people who never sign up are counted too. Writes run
/// in the background and never block onboarding. A failed write stays pending and goes out
/// with the next recorded step. Each step is sent at most once per user from this device.
@MainActor
final class OnboardingFunnelRecorder {
  static let shared = OnboardingFunnelRecorder()

  static let preAuthPrefix = "preauth_"
  static let postAuthPrefix = "postauth_"
  static let onboardingCompletedStep = "onboarding_completed"
  static let firstShiftStep = "first_shift_added"
  static let firstShiftMethodPrefix = "first_shift_via_"
  static let pendingDefaultsKey = "onboardingFunnel.pendingSteps"
  static let sentDefaultsKeyPrefix = "onboardingFunnel.sentSteps."
  static let installIdDefaultsKey = "onboardingFunnel.installId"
  static let anonymousSentDefaultsKey = "onboardingFunnel.anonymousSentSteps"

  /// The two backend calls. Debug builds have none, so simulator runs, UI tests and fixtures
  /// never write test rows into the production funnel.
  struct Transport: Sendable {
    let send: @Sendable ([OnboardingFunnelStepRow]) async throws -> Void
    let sendPreAuth: @Sendable (_ installId: String, _ step: String, _ reachedAt: String) async throws -> Void

    /// Built in every configuration, so a Debug build also compiles what Release sends.
    static let production = Transport(send: sendSteps, sendPreAuth: sendPreAuthStep)

    #if DEBUG
      static let live: Transport? = nil
    #else
      static let live: Transport? = production
    #endif

    private static func sendSteps(_ rows: [OnboardingFunnelStepRow]) async throws {
      struct Step: Encodable, Sendable {
        let step: String
        let reachedAt: String
        enum CodingKeys: String, CodingKey {
          case step
          case reachedAt = "reached_at"
        }
      }
      struct Args: Encodable, Sendable { let steps: [Step] }
      let args = Args(steps: rows.map { Step(step: $0.step, reachedAt: $0.reached_at) })
      _ = try await ConvexAPI.app.mutation("onboarding:recordSteps", args, as: ConvexAPI.Ignored.self)
    }

    private static func sendPreAuthStep(installId: String, step: String, reachedAt: String) async throws {
      struct Args: Encodable, Sendable {
        let installId: String
        let step: String
        let reachedAt: String
        enum CodingKeys: String, CodingKey {
          case installId = "install_id"
          case step
          case reachedAt = "reached_at"
        }
      }
      _ = try await ConvexAPI.anonymous.mutation(
        "onboarding:recordPreauthStep",
        Args(installId: installId, step: step, reachedAt: reachedAt),
        as: ConvexAPI.Ignored.self)
    }
  }

  private let defaults: UserDefaults
  private let currentUserId: @MainActor () -> String?
  /// Without a transport the recorder keeps no state and sends nothing.
  private let transport: Transport?
  private var isSending = false
  private var hasQueuedSend = false

  init(
    defaults: UserDefaults = .standard,
    currentUserId: @escaping @MainActor () -> String? = {
      AuthSessionManager.shared.localSession()?.normalizedUserId
    },
    transport: Transport? = Transport.live
  ) {
    self.defaults = defaults
    self.currentUserId = currentUserId
    self.transport = transport
  }

  /// Sends a pre-auth page without a user and keeps it locally until post-auth onboarding
  /// records a step. Pages whose anonymous send failed are retried with the next page.
  func recordPreAuth(_ page: String) {
    guard let transport else { return }
    addPending(Self.preAuthPrefix + page, userId: nil)
    let anonymousSent = Set(defaults.stringArray(forKey: Self.anonymousSentDefaultsKey) ?? [])
    let installId = self.installId
    for (step, reachedAt) in pending
    where step.hasPrefix(Self.preAuthPrefix) && !anonymousSent.contains(step) {
      Task {
        do {
          try await transport.sendPreAuth(installId, String(step.dropFirst(Self.preAuthPrefix.count)), reachedAt)
          let sent = Set(defaults.stringArray(forKey: Self.anonymousSentDefaultsKey) ?? [])
          defaults.set(Array(sent.union([step])), forKey: Self.anonymousSentDefaultsKey)
        } catch {
          // Stays unsent. The next pre-auth page retries it.
        }
      }
    }
  }

  /// Records a post-auth onboarding step and sends everything pending.
  func record(_ step: String) {
    guard transport != nil else { return }
    addPending(step, userId: currentUserId())
    sendPending()
  }

  /// Records the first shift and how it was created, for example "manual", "recurring",
  /// "clock" or "calendar_import". A first shift pre-filled from the pre-auth demo is
  /// recorded separately as the "demo_shift_prefilled" step. Only users who went through tracked
  /// onboarding on this device count, so existing users do not get a late "first" shift.
  func recordShiftCreated(method: String) {
    guard transport != nil, let userId = currentUserId() else { return }
    let sent = sentSteps(for: userId)
    guard !sent.contains(Self.firstShiftStep) else { return }
    if pending[Self.firstShiftStep] == nil {
      let isTracked = (sent.union(pending.keys)).contains { !$0.hasPrefix(Self.preAuthPrefix) }
      guard isTracked else { return }
      addPending(Self.firstShiftStep, userId: userId)
      addPending(Self.firstShiftMethodPrefix + method, userId: userId)
    }
    sendPending()
  }

  // MARK: - Private

  private var pending: [String: String] {
    defaults.dictionary(forKey: Self.pendingDefaultsKey) as? [String: String] ?? [:]
  }

  private func sentSteps(for userId: String) -> Set<String> {
    Set(defaults.stringArray(forKey: Self.sentDefaultsKeyPrefix + userId) ?? [])
  }

  private var installId: String {
    if let existing = defaults.string(forKey: Self.installIdDefaultsKey) { return existing }
    let created = UUID().uuidString
    defaults.set(created, forKey: Self.installIdDefaultsKey)
    return created
  }

  private func addPending(_ step: String, userId: String?) {
    var steps = pending
    guard steps[step] == nil else { return }
    if let userId, sentSteps(for: userId).contains(step) { return }
    steps[step] = Date().toISO8601String()
    defaults.set(steps, forKey: Self.pendingDefaultsKey)
  }

  private func removePending(_ keys: some Sequence<String>) {
    var steps = pending
    for key in keys {
      steps.removeValue(forKey: key)
    }
    defaults.set(steps, forKey: Self.pendingDefaultsKey)
  }

  private func sendPending() {
    guard !isSending else {
      hasQueuedSend = true
      return
    }
    guard let transport, let userId = currentUserId() else { return }

    let snapshot = pending
    let sent = sentSteps(for: userId)
    let rows =
      snapshot
      .filter { !sent.contains($0.key) }
      .map { OnboardingFunnelStepRow(user_id: userId, step: $0.key, reached_at: $0.value) }
    guard !rows.isEmpty else {
      removePending(snapshot.keys)
      return
    }

    isSending = true
    Task {
      do {
        try await transport.send(rows)
        let updatedSent = sentSteps(for: userId).union(rows.map(\.step))
        defaults.set(Array(updatedSent), forKey: Self.sentDefaultsKeyPrefix + userId)
        removePending(snapshot.keys)
      } catch {
        // Keep the steps pending. The next recorded step retries them.
      }
      isSending = false
      if hasQueuedSend {
        hasQueuedSend = false
        sendPending()
      }
    }
  }
}
