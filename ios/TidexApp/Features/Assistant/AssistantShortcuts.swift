import AppIntents

// Phrases are keys in AppShortcuts.xcstrings, which holds their Norwegian versions.
struct TidexShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: NextShiftIntent(),
      phrases: [
        "What's my next shift in \(.applicationName)",
        "When do I work next in \(.applicationName)",
      ],
      shortTitle: "assistant.nextShift.title",
      systemImageName: "calendar")
    AppShortcut(
      intent: EarningsIntent(),
      phrases: [
        "How much have I earned in \(.applicationName)",
        "Show earnings for \(\.$period) in \(.applicationName)",
      ],
      shortTitle: "assistant.earnings.title",
      systemImageName: "banknote")
    AppShortcut(
      intent: HoursWorkedIntent(),
      phrases: [
        "How many hours have I worked in \(.applicationName)",
        "Show hours for \(\.$period) in \(.applicationName)",
      ],
      shortTitle: "assistant.hours.title",
      systemImageName: "clock")
    AppShortcut(
      intent: EarnedSoFarIntent(),
      phrases: [
        "How much have I earned this shift in \(.applicationName)",
        "What have I earned so far in \(.applicationName)",
      ],
      shortTitle: "assistant.earnedSoFar.title",
      systemImageName: "chart.line.uptrend.xyaxis")
    AppShortcut(
      intent: StopClockIntent(),
      phrases: [
        "Clock out in \(.applicationName)",
        "Stop the clock in \(.applicationName)",
      ],
      shortTitle: "assistant.stopClock.title",
      systemImageName: "stop.circle")
    AppShortcut(
      intent: ExtendShiftIntent(),
      phrases: ["Extend my shift in \(.applicationName)"],
      shortTitle: "assistant.extendShift.title",
      systemImageName: "timer")
    AppShortcut(
      intent: AddShiftIntent(),
      phrases: [
        "Add a shift in \(.applicationName)",
        "Add a \(\.$job) shift in \(.applicationName)",
      ],
      shortTitle: "assistant.addShift.title",
      systemImageName: "plus.circle")
    AppShortcut(
      intent: FriendScheduleIntent(),
      phrases: [
        "When does \(\.$friend) work in \(.applicationName)",
        "Check a friend's shifts in \(.applicationName)",
      ],
      shortTitle: "assistant.friendSchedule.title",
      systemImageName: "person.2")
  }
}
