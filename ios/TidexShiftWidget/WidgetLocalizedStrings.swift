import Foundation

// MARK: - Widget Localized String Resources
// These mirror the pattern used in the main app for type-safe localization

extension LocalizedStringResource {
    // MARK: - Common Labels
    static var widgetDays: LocalizedStringResource { "days" }
    static var widgetDay: LocalizedStringResource { "day" }
    static var widgetAgo: LocalizedStringResource { "ago" }
    static var widgetDone: LocalizedStringResource { "done" }
    static var widgetDoneCapitalized: LocalizedStringResource { "Done" }
    static var widgetLeft: LocalizedStringResource { "left" }
    static var widgetStart: LocalizedStringResource { "start" }
    static var widgetEnds: LocalizedStringResource { "Ends" }
    static var widgetHours: LocalizedStringResource { "hours" }
    static var widgetActive: LocalizedStringResource { "Active" }

    // MARK: - Date Labels
    static var widgetToday: LocalizedStringResource { "Today" }
    static var widgetYesterday: LocalizedStringResource { "Yesterday" }
    static var widgetTomorrow: LocalizedStringResource { "Tomorrow" }

    // MARK: - Shift Labels
    static var widgetNoShift: LocalizedStringResource { "No shift" }
    static var widgetNoShifts: LocalizedStringResource { "No shifts" }
    static var widgetShift: LocalizedStringResource { "shift" }
    static var widgetShifts: LocalizedStringResource { "shifts" }
    static var widgetShiftPlanned: LocalizedStringResource { "shift planned" }
    static var widgetShiftsPlanned: LocalizedStringResource { "shifts planned" }

    // MARK: - Friend Labels
    static var widgetFriend: LocalizedStringResource { "Friend" }
    static var widgetSelectAFriend: LocalizedStringResource { "Select a friend" }
    static var widgetAddFriendsToSeeTheirShifts: LocalizedStringResource { "Add friends to see their shifts" }

    // MARK: - Widget Names
    static var widgetNameShift: LocalizedStringResource { "Shift" }
    static var widgetNameNextShift: LocalizedStringResource { "Next Shift" }
    static var widgetNameFriendsShift: LocalizedStringResource { "Friend's Shift" }
    static var widgetNameFriendsShifts: LocalizedStringResource { "Friends' Shifts" }
    static var widgetNameMonthlyTotal: LocalizedStringResource { "Monthly Total" }

    // MARK: - Widget Descriptions
    static var widgetDescLockScreen: LocalizedStringResource { "See your next shift on the lock screen" }
    static var widgetDescNextShift: LocalizedStringResource { "See your next shift at a glance" }
    static var widgetDescFriendsShift: LocalizedStringResource { "See a friend's next shift" }
    static var widgetDescFriendsShifts: LocalizedStringResource { "See your friends' upcoming shifts" }
    static var widgetDescMonthlyTotal: LocalizedStringResource { "See your monthly total at a glance" }

    // MARK: - TotalCard Labels
    static var widgetToDate: LocalizedStringResource { "to date" }
    static var widgetBeforeTax: LocalizedStringResource { "before tax" }
}
