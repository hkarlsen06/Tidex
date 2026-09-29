import SwiftUI

/// The headline numbers under the user's name. Shows dashes while the stats load.
struct AdminUserStatTiles: View {
  let stats: AdminUserStats?

  var body: some View {
    Section {
      HStack(spacing: Spacing.xs) {
        AdminStatTile(title: "Shifts", value: stats?.shiftCount, icon: "calendar", tint: .tidexBlue)
        AdminStatTile(
          title: "Last 30 days", value: stats?.shiftsLast30Days, icon: "clock", tint: .tidexSuccess)
        AdminStatTile(
          title: "Messages", value: stats?.messagesSent, icon: "bubble.left.and.bubble.right",
          tint: .tidexPurple)
      }
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    }
  }
}

/// Usage, friends, support and device sections for the user detail screen.
struct AdminUserStatsSections: View {
  let stats: AdminUserStats

  var body: some View {
    Section("Usage") {
      dateRow("First shift", stats.firstShift)
      dateRow("Latest shift", stats.latestShift)
      countRow("Upcoming shifts", stats.upcomingShiftCount)
      LabeledContent("Last shift added") { AdminRelativeDate(date: stats.lastShiftAdded) }
      countRow("Jobs", stats.jobCount)
      countRow("Recurring schedules", stats.recurringScheduleCount)
      countRow("Calendar events", stats.eventCount)
      LabeledContent("Calendar feed") {
        if !stats.hasCalendarFeed {
          Text("Off")
        } else if let lastUsed = stats.calendarFeedLastUsed {
          Text("Used \(lastUsed.formatted(.relative(presentation: .named)))")
        } else {
          Text("On, never fetched")
        }
      }
    }

    Section("Friends") {
      countRow("Shares shifts with", stats.sharesTheirShiftsWith)
      countRow("Sees shifts from", stats.seesShiftsFrom)
      countRow("Messages in last 30 days", stats.messagesLast30Days)
    }

    Section("Support") {
      countRow("Feedback sent", stats.feedbackCount)
      countRow("Reports filed", stats.reportsFiled)
      LabeledContent("Reports against them") {
        Text(stats.reportsReceived, format: .number)
          .foregroundStyle(stats.reportsReceived > 0 ? Color.tidexError : Color.tidexTextSecondary)
      }
    }

    if let app = stats.appActivity {
      Section {
        LabeledContent("Last opened") { AdminRelativeDate(date: app.lastActive) }
        textRow("Version", app.version)
        if let previous = app.previousVersion {
          textRow("Updated from", previous)
        }
        textRow("Device", app.deviceModel)
        textRow("System", app.osVersion)
        textRow("App language", app.appLanguage)
        textRow("Locale", app.locale)
        textRow("Time zone", app.timeZone)
        countRow("Opens", app.openCount)
        if let activeDays = app.activeDays {
          countRow("Active days", activeDays)
        }
        dateRow("First recorded open", app.firstActive)
      } header: {
        Text("App")
      } footer: {
        Text(
          """
          From the latest time the user opened the app. Opens and active days are counted from \
          the first recorded open.
          """
        )
      }

      Section("Settings") {
        textRow("Notifications", Self.label(app.notificationPermission))
        textRow("Background refresh", Self.label(app.backgroundRefresh))
        textRow("Widgets", app.widgetKinds.map { $0.isEmpty ? "None" : $0.joined(separator: ", ") })
        textRow("Appearance", Self.label(app.appearance))
        textRow("Text size", app.textSize)
        textRow("Reduce Motion", app.reduceMotion.map { $0 ? "On" : "Off" })
      }
    }

    Section {
      if stats.devices.isEmpty {
        Text("No registered devices, so broadcasts can't reach this user.")
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
      }
      ForEach(stats.devices) { device in
        LabeledContent {
          AdminRelativeDate(date: device.lastSeen)
        } label: {
          Text(
            [device.platform.map { $0 == "ios" ? "iOS" : $0 }, device.appVersion]
              .compactMap { $0 }
              .joined(separator: " · ")
          )
          if let timeZone = device.timeZone {
            Text(timeZone)
          }
        }
      }
    } header: {
      Text("Devices")
    } footer: {
      if !stats.devices.isEmpty {
        Text(
          "Devices registered for push notifications, with the app version and when each was last seen."
        )
      }
    }
  }

  private func countRow(_ title: String, _ value: Int) -> some View {
    LabeledContent(title) { Text(value, format: .number) }
  }

  /// Readable text for the codes `record_app_activity` stores. Unknown codes show as they are.
  private static let labels: [String: String] = [
    "authorized": "Allowed", "denied": "Denied", "not_determined": "Not asked yet",
    "provisional": "Provisional", "ephemeral": "Ephemeral", "available": "On",
    "restricted": "Restricted", "light": "Light", "dark": "Dark",
  ]

  private static func label(_ code: String?) -> String? {
    code.map { labels[$0] ?? $0 }
  }

  private func textRow(_ title: String, _ value: String?) -> some View {
    LabeledContent(title) { Text(verbatim: value.flatMap { $0.isEmpty ? nil : $0 } ?? "–") }
  }

  private func dateRow(_ title: String, _ date: Date?) -> some View {
    LabeledContent(title) {
      if let date {
        Text(date, format: .dateTime.day().month().year())
      } else {
        Text("None")
      }
    }
  }
}
