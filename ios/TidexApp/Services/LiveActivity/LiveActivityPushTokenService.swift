import ActivityKit
import Foundation
import Supabase
import UIKit
import os

private let liveActivityPushLogger = Logger(
  subsystem: "no.tidex.app",
  category: "LiveActivityPushTokens"
)

enum LiveActivityTokenCodec {
  static func hexString(for data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
}

@MainActor
final class LiveActivityPushTokenService {
  static let shared = LiveActivityPushTokenService()

  private struct PendingUpdateToken: Codable, Hashable {
    let activityId: String
    let shiftId: String
    let pushToken: String
  }

  private static let pushToStartTokenDefaultsKey = "live_activity.push_to_start_token"
  private static let pendingUpdateTokensDefaultsKey = "live_activity.pending_update_tokens"
  private static let fallbackDeviceIdDefaultsKey = "live_activity.fallback_device_id"

  private var pushToStartObservationTask: Task<Void, Never>?
  private var activityUpdatesObservationTask: Task<Void, Never>?
  private var activityPushTokenTasks: [String: Task<Void, Never>] = [:]
  private var activityStateTasks: [String: Task<Void, Never>] = [:]
  private var locallyStartedActivityIds: Set<String> = []

  private init() {}

  func startObserving() {
    guard pushToStartObservationTask == nil, activityUpdatesObservationTask == nil else {
      return
    }

    for activity in Activity<ShiftActivityAttributes>.activities {
      observe(activity)
    }

    if let token = Activity<ShiftActivityAttributes>.pushToStartToken {
      handlePushToStartToken(token)
    }

    pushToStartObservationTask = Task { @MainActor [weak self] in
      for await token in Activity<ShiftActivityAttributes>.pushToStartTokenUpdates {
        guard !Task.isCancelled else { return }
        self?.handlePushToStartToken(token)
      }
    }

    activityUpdatesObservationTask = Task { @MainActor [weak self] in
      for await activity in Activity<ShiftActivityAttributes>.activityUpdates {
        guard !Task.isCancelled else { return }
        self?.observe(activity)
      }
    }

    Task { @MainActor [weak self] in
      await self?.registerCachedTokensIfNeeded()
    }
  }

  func observe(
    _ activity: Activity<ShiftActivityAttributes>,
    locallyStarted: Bool = false
  ) {
    if locallyStarted {
      locallyStartedActivityIds.insert(activity.id)
    }

    guard !isTemporaryClockActivity(activity.attributes) else {
      return
    }

    startPushTokenObservationIfNeeded(for: activity)
    startStateObservationIfNeeded(for: activity)
  }

  func registerCachedTokensIfNeeded() async {
    guard await hasAuthenticatedRegistrationContext() else { return }

    if let token = UserDefaults.standard.string(forKey: Self.pushToStartTokenDefaultsKey) {
      await registerPushToStartToken(token)
    } else if let token = Activity<ShiftActivityAttributes>.pushToStartToken {
      handlePushToStartToken(token)
    }

    let activities = Activity<ShiftActivityAttributes>.activities.filter {
      !isTerminal($0.activityState) && !isTemporaryClockActivity($0.attributes)
    }
    let currentActivityIds = Set(activities.map(\.id))
    removePendingUpdateTokens(excluding: currentActivityIds)

    for activity in activities {
      observe(activity)
      if let token = activity.pushToken {
        await registerUpdateToken(token, for: activity)
      }
    }

    for pendingToken in pendingUpdateTokens()
    where currentActivityIds.contains(pendingToken.activityId) {
      await registerUpdateToken(pendingToken)
    }
  }

  func unregisterCurrentDevice() async {
    guard await hasAuthenticatedRegistrationContext() else { return }

    do {
      try await supabase
        .rpc(
          "unregister_live_activity_device",
          params: ["p_device_id": deviceId()]
        )
        .execute()
    } catch {
      liveActivityPushLogger.warning(
        "Failed to unregister Live Activity device: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}

extension LiveActivityPushTokenService {
  fileprivate func startPushTokenObservationIfNeeded(
    for activity: Activity<ShiftActivityAttributes>
  ) {
    guard activityPushTokenTasks[activity.id] == nil else { return }

    activityPushTokenTasks[activity.id] = Task { @MainActor [weak self] in
      guard let self else { return }

      if !locallyStartedActivityIds.contains(activity.id),
        !(await hasAuthenticatedRegistrationContext())
      {
        await activity.end(nil, dismissalPolicy: .immediate)
        removeObservation(for: activity.id)
        return
      }

      if let token = activity.pushToken {
        await registerUpdateToken(token, for: activity)
      }

      for await token in activity.pushTokenUpdates {
        guard !Task.isCancelled else { return }
        await registerUpdateToken(token, for: activity)
      }
    }
  }

  fileprivate func startStateObservationIfNeeded(
    for activity: Activity<ShiftActivityAttributes>
  ) {
    guard activityStateTasks[activity.id] == nil else { return }

    activityStateTasks[activity.id] = Task { @MainActor [weak self] in
      guard let self else { return }

      if isTerminal(activity.activityState) {
        await handleTerminalActivity(activity)
        return
      }

      for await state in activity.activityStateUpdates {
        guard !Task.isCancelled else { return }
        if isTerminal(state) {
          await handleTerminalActivity(activity)
          return
        }
      }
    }
  }

  private func handlePushToStartToken(_ token: Data) {
    let tokenString = LiveActivityTokenCodec.hexString(for: token)
    UserDefaults.standard.set(tokenString, forKey: Self.pushToStartTokenDefaultsKey)

    Task { @MainActor [weak self] in
      await self?.registerPushToStartToken(tokenString)
    }
  }

  private func registerPushToStartToken(_ token: String) async {
    guard await hasAuthenticatedRegistrationContext() else { return }

    var params: [String: AnyJSON] = [
      "p_device_id": .string(deviceId()),
      "p_push_to_start_token": .string(token),
      "p_time_zone": .string(TimeZone.current.identifier),
    ]
    if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
      params["p_app_version"] = .string(appVersion)
    }

    do {
      try await supabase
        .rpc("register_live_activity_device", params: params)
        .execute()
    } catch {
      liveActivityPushLogger.warning(
        "Failed to register push-to-start token: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func registerUpdateToken(
    _ token: Data,
    for activity: Activity<ShiftActivityAttributes>
  ) async {
    let pendingToken = PendingUpdateToken(
      activityId: activity.id,
      shiftId: activity.attributes.shiftId,
      pushToken: LiveActivityTokenCodec.hexString(for: token)
    )
    storePendingUpdateToken(pendingToken)
    await registerUpdateToken(pendingToken)
  }

  private func registerUpdateToken(_ pendingToken: PendingUpdateToken) async {
    guard await hasAuthenticatedRegistrationContext() else { return }

    let params: [String: AnyJSON] = [
      "p_device_id": .string(deviceId()),
      "p_shift_id": .string(pendingToken.shiftId),
      "p_activity_id": .string(pendingToken.activityId),
      "p_push_token": .string(pendingToken.pushToken),
    ]

    do {
      try await supabase
        .rpc("register_live_activity_update_token", params: params)
        .execute()
      removePendingUpdateToken(activityId: pendingToken.activityId)
    } catch {
      liveActivityPushLogger.warning(
        "Failed to register Live Activity update token: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func handleTerminalActivity(_ activity: Activity<ShiftActivityAttributes>) async {
    removePendingUpdateToken(activityId: activity.id)

    if await hasAuthenticatedRegistrationContext() {
      do {
        let params: [String: AnyJSON] = [
          "p_device_id": .string(deviceId()),
          "p_activity_id": .string(activity.id),
        ]
        try await supabase
          .rpc("end_live_activity_registration", params: params)
          .execute()
      } catch {
        liveActivityPushLogger.warning(
          "Failed to end Live Activity registration: \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    removeObservation(for: activity.id)
  }

  private func hasAuthenticatedRegistrationContext() async -> Bool {
    guard !ImpersonationManager.shared.isImpersonating else { return false }
    return await AuthSessionManager.shared.getSessionIfAvailable() != nil
  }

  private func isTemporaryClockActivity(_ attributes: ShiftActivityAttributes) -> Bool {
    if let explicitFlag = attributes.isTemporaryClock {
      return explicitFlag
    }

    return attributes.endTime == "00:00"
      && attributes.totalGrossEstimate == 0
      && attributes.hourlyWage == 0
      && attributes.supplementRatePerHour == 0
  }

  private func isTerminal(_ state: ActivityState) -> Bool {
    switch state {
    case .ended, .dismissed:
      return true

    default:
      return false
    }
  }

  private func removeObservation(for activityId: String) {
    activityPushTokenTasks.removeValue(forKey: activityId)?.cancel()
    activityStateTasks.removeValue(forKey: activityId)?.cancel()
    locallyStartedActivityIds.remove(activityId)
  }

  private func deviceId() -> String {
    if let identifier = UIDevice.current.identifierForVendor?.uuidString {
      return identifier
    }

    if let cached = UserDefaults.standard.string(forKey: Self.fallbackDeviceIdDefaultsKey) {
      return cached
    }

    let generated = UUID().uuidString
    UserDefaults.standard.set(generated, forKey: Self.fallbackDeviceIdDefaultsKey)
    return generated
  }

  private func pendingUpdateTokens() -> [PendingUpdateToken] {
    guard
      let data = UserDefaults.standard.data(forKey: Self.pendingUpdateTokensDefaultsKey),
      let tokens = try? JSONDecoder().decode([PendingUpdateToken].self, from: data)
    else {
      return []
    }
    return tokens
  }

  private func storePendingUpdateToken(_ token: PendingUpdateToken) {
    var tokens = pendingUpdateTokens()
    tokens.removeAll { $0.activityId == token.activityId }
    tokens.append(token)
    persistPendingUpdateTokens(tokens)
  }

  private func removePendingUpdateToken(activityId: String) {
    let tokens = pendingUpdateTokens().filter { $0.activityId != activityId }
    persistPendingUpdateTokens(tokens)
  }

  private func removePendingUpdateTokens(excluding activityIds: Set<String>) {
    let tokens = pendingUpdateTokens().filter { activityIds.contains($0.activityId) }
    persistPendingUpdateTokens(tokens)
  }

  private func persistPendingUpdateTokens(_ tokens: [PendingUpdateToken]) {
    guard !tokens.isEmpty else {
      UserDefaults.standard.removeObject(forKey: Self.pendingUpdateTokensDefaultsKey)
      return
    }

    if let data = try? JSONEncoder().encode(tokens) {
      UserDefaults.standard.set(data, forKey: Self.pendingUpdateTokensDefaultsKey)
    }
  }
}
