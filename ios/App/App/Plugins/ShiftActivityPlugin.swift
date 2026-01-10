@preconcurrency import ActivityKit
import Capacitor
import Foundation
import WidgetKit

// MARK: - Activity Update Manager

/// MainActor-isolated manager for Live Activity timer updates
/// Separating this into its own class avoids Sendable issues with the plugin
@available(iOS 16.2, *)
@MainActor
private final class ActivityUpdateManager {
    private var updateTimer: Timer?
    private var currentActivityId: String?

    var activityId: String? {
        get { currentActivityId }
        set { currentActivityId = newValue }
    }

    func startTimer(
        for activity: Activity<ShiftActivityAttributes>,
        startDateTime: Date,
        endDateTime: Date,
        totalRate: Double
    ) {
        // Cancel any existing timer
        updateTimer?.invalidate()

        // Update every 60 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                await self.performUpdate(
                    activity: activity,
                    startDateTime: startDateTime,
                    endDateTime: endDateTime,
                    totalRate: totalRate
                )
            }
        }

        // Fire immediately for initial update
        updateTimer?.fire()
    }

    private func performUpdate(
        activity: Activity<ShiftActivityAttributes>,
        startDateTime: Date,
        endDateTime: Date,
        totalRate: Double
    ) async {
        let now = Date()

        // Check if shift has ended
        guard now < endDateTime else {
            // Shift ended - end the activity
            await activity.end(nil, dismissalPolicy: .default)
            cleanup()
            return
        }

        // Calculate current state
        let elapsed = now.timeIntervalSince(startDateTime)
        let total = endDateTime.timeIntervalSince(startDateTime)
        let progress = min(100, max(0, (elapsed / total) * 100))
        let hoursWorked = elapsed / 3600
        let earnings = hoursWorked * totalRate
        let remainingMinutes = max(0, Int((total - elapsed) / 60))

        let newState = ShiftActivityAttributes.ContentState(
            currentEarnings: earnings,
            remainingMinutes: remainingMinutes,
            progressPercent: progress
        )

        await activity.update(.init(state: newState, staleDate: nil))
    }

    func cleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
        currentActivityId = nil
    }
}

// MARK: - Shift Activity Plugin

/// Capacitor plugin for managing Shift Live Activities
/// Allows the web layer to start, update, and end Live Activities for ongoing shifts
@objc(ShiftActivityPlugin)
public class ShiftActivityPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ShiftActivityPlugin"
    public let jsName = "ShiftActivity"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startActivity", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateActivity", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endActivity", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endAllActivities", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getActiveActivity", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveShiftsToSharedStorage", returnType: CAPPluginReturnPromise),
    ]

    // Activity update manager - lazy initialization for iOS 16.2+ only
    private var _activityManager: Any?

    @available(iOS 16.2, *)
    @MainActor
    private var activityManager: ActivityUpdateManager {
        if let manager = _activityManager as? ActivityUpdateManager {
            return manager
        }
        let manager = ActivityUpdateManager()
        _activityManager = manager
        return manager
    }

    // App Group identifier for shared storage
    private let appGroupId = "group.no.tidex.app"

    // MARK: - Plugin Methods

    /// Check if Live Activities are available on this device
    @objc func isAvailable(_ call: CAPPluginCall) {
        if #available(iOS 16.2, *) {
            let info = ActivityAuthorizationInfo()
            call.resolve([
                "available": info.areActivitiesEnabled,
                "frequentUpdatesEnabled": info.frequentPushesEnabled
            ])
        } else {
            call.resolve([
                "available": false,
                "frequentUpdatesEnabled": false
            ])
        }
    }

    /// Start a new Live Activity for an ongoing shift
    @objc func startActivity(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.reject("Live Activities require iOS 16.2+")
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            call.reject("Live Activities are disabled by the user")
            return
        }

        // Extract shift data from call
        guard let shiftId = call.getString("shiftId"),
              let shiftDate = call.getString("shiftDate"),
              let startTime = call.getString("startTime"),
              let endTime = call.getString("endTime"),
              let hourlyWage = call.getDouble("hourlyWage"),
              let supplementRate = call.getDouble("supplementRatePerHour"),
              let totalGross = call.getDouble("totalGrossEstimate") else {
            call.reject("Missing required parameters")
            return
        }

        let locale = call.getString("locale") ?? "no"
        let currencySymbol = call.getString("currencySymbol") ?? "kr"
        let initialProgress = call.getDouble("initialProgress") ?? 0.0
        let initialEarnings = call.getDouble("initialEarnings") ?? 0.0
        let remainingMinutes = call.getInt("remainingMinutes") ?? 0

        // End any existing activity first
        Task { @MainActor in
            await self.endAllActivitiesAsync()

            // Create attributes and initial state
            let attributes = ShiftActivityAttributes(
                shiftId: shiftId,
                shiftDate: shiftDate,
                startTime: startTime,
                endTime: endTime,
                hourlyWage: hourlyWage,
                supplementRatePerHour: supplementRate,
                totalGrossEstimate: totalGross,
                locale: locale,
                currencySymbol: currencySymbol
            )

            let initialState = ShiftActivityAttributes.ContentState(
                currentEarnings: initialEarnings,
                remainingMinutes: remainingMinutes,
                progressPercent: initialProgress
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: initialState, staleDate: nil),
                    pushType: nil // No push updates - local timer only
                )

                // Parse shift times for timer
                let startDateTime = self.parseShiftTime(attributes.shiftDate, attributes.startTime)
                let endDateTime = self.parseShiftTime(
                    attributes.shiftDate,
                    attributes.endTime,
                    crossMidnight: attributes.endTime < attributes.startTime
                )
                let totalRate = attributes.hourlyWage + attributes.supplementRatePerHour

                self.activityManager.activityId = activity.id
                self.activityManager.startTimer(
                    for: activity,
                    startDateTime: startDateTime,
                    endDateTime: endDateTime,
                    totalRate: totalRate
                )

                call.resolve([
                    "activityId": activity.id,
                    "success": true
                ])
            } catch {
                call.reject("Failed to start activity: \(error.localizedDescription)")
            }
        }
    }

    /// Manually update the activity's earnings and progress
    @objc func updateActivity(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.reject("Live Activities require iOS 16.2+")
            return
        }

        Task { @MainActor in
            let activityId = call.getString("activityId") ?? self.activityManager.activityId
            guard let activityId = activityId else {
                call.reject("No active activity to update")
                return
            }

            let earnings = call.getDouble("earnings") ?? 0
            let progress = call.getDouble("progress") ?? 0
            let remainingMinutes = call.getInt("remainingMinutes") ?? 0

            for activity in Activity<ShiftActivityAttributes>.activities {
                if activity.id == activityId {
                    let newState = ShiftActivityAttributes.ContentState(
                        currentEarnings: earnings,
                        remainingMinutes: remainingMinutes,
                        progressPercent: progress
                    )
                    await activity.update(.init(state: newState, staleDate: nil))
                    call.resolve(["success": true])
                    return
                }
            }
            call.reject("Activity not found")
        }
    }

    /// End a specific activity or the current one
    @objc func endActivity(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.reject("Live Activities require iOS 16.2+")
            return
        }

        Task { @MainActor in
            let activityId = call.getString("activityId") ?? self.activityManager.activityId

            // Stop the update timer and cleanup
            self.activityManager.cleanup()

            for activity in Activity<ShiftActivityAttributes>.activities {
                if activityId == nil || activity.id == activityId {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }

            call.resolve(["success": true])
        }
    }

    /// End all active shift activities
    @objc func endAllActivities(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.reject("Live Activities require iOS 16.2+")
            return
        }

        Task { @MainActor in
            await self.endAllActivitiesAsync()
            call.resolve(["success": true])
        }
    }

    /// Get the currently active shift activity
    @objc func getActiveActivity(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.resolve(["hasActivity": false])
            return
        }

        let activities = Activity<ShiftActivityAttributes>.activities
        if let activity = activities.first {
            call.resolve([
                "hasActivity": true,
                "activityId": activity.id,
                "shiftId": activity.attributes.shiftId
            ])
        } else {
            call.resolve(["hasActivity": false])
        }
    }

    /// Save upcoming shifts to shared storage for background task access and home widget
    @objc func saveShiftsToSharedStorage(_ call: CAPPluginCall) {
        guard let shiftsJson = call.getString("shifts") else {
            call.reject("Missing shifts parameter")
            return
        }

        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            call.reject("Could not access shared storage")
            return
        }

        userDefaults.set(shiftsJson, forKey: "upcoming_shifts")

        // Trigger widget refresh so ShiftHomeWidget updates with new data
        WidgetCenter.shared.reloadAllTimelines()

        call.resolve(["success": true])
    }

    // MARK: - Private Helpers

    @available(iOS 16.2, *)
    @MainActor
    private func endAllActivitiesAsync() async {
        // Cleanup the timer first
        activityManager.cleanup()

        for activity in Activity<ShiftActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func parseShiftTime(_ date: String, _ time: String, crossMidnight: Bool = false) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current

        var dateTime = formatter.date(from: "\(date) \(time)") ?? Date()
        if crossMidnight {
            dateTime = Calendar.current.date(byAdding: .day, value: 1, to: dateTime) ?? dateTime
        }
        return dateTime
    }
}
