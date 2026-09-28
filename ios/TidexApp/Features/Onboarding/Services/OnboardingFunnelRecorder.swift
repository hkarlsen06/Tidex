import Foundation
import Supabase

/// One row in `public.onboarding_funnel_steps`.
struct OnboardingFunnelStepRow: Encodable, Equatable {
  let user_id: String  // swiftlint:disable:this identifier_name
  let step: String
  let reached_at: String  // swiftlint:disable:this identifier_name
}

/// Records the first time a user reaches each onboarding step, for funnel analysis.
///
/// Rows go to `public.onboarding_funnel_steps`, where the insert ignores duplicates so the
/// first timestamp wins. Pre-auth pages wait in UserDefaults until post-auth onboarding
/// records its first step. Writes run in the background and never block onboarding. A
/// failed write stays pending and goes out with the next recorded step. Each step is sent
/// at most once per user from this device.
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

  private let defaults: UserDefaults
  private let currentUserId: () -> String?
  private let send: ([OnboardingFunnelStepRow]) async throws -> Void
  private var isSending = false
  private var hasQueuedSend = false

  init(
    defaults: UserDefaults = .standard,
    currentUserId: @escaping () -> String? = { supabase.auth.currentUser?.normalizedId },
    send: @escaping ([OnboardingFunnelStepRow]) async throws -> Void = { rows in
      _ =
        try await supabase
        .from("onboarding_funnel_steps")
        .upsert(rows, onConflict: "user_id,step", returning: .minimal, ignoreDuplicates: true)
        .execute()
    }
  ) {
    self.defaults = defaults
    self.currentUserId = currentUserId
    self.send = send
  }

  /// Keeps a pre-auth page locally. It is sent once post-auth onboarding records a step.
  func recordPreAuth(_ page: String) {
    addPending(Self.preAuthPrefix + page, userId: nil)
  }

  /// Records a post-auth onboarding step and sends everything pending.
  func record(_ step: String) {
    addPending(step, userId: currentUserId())
    sendPending()
  }

  /// Records the first shift and how it was created, for example "manual", "recurring",
  /// "clock" or "calendar_import". A first shift pre-filled from the pre-auth demo is
  /// recorded separately as the "demo_shift_prefilled" step. Only users who went through tracked
  /// onboarding on this device count, so existing users do not get a late "first" shift.
  func recordShiftCreated(method: String) {
    guard let userId = currentUserId() else { return }
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
    guard let userId = currentUserId() else { return }

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
        try await send(rows)
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
