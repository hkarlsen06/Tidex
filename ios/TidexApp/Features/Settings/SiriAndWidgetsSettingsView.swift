import AppIntents
import SwiftUI

/// What Tidex offers outside the app: Siri phrases, widgets and the Live Activity.
struct SiriAndWidgetsSettingsView: View {
  private struct Row {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    let systemImage: String
  }

  // One phrase per `TidexShortcuts` entry. AppIntents does not expose the phrases at run time.
  private var siriRows: [Row] {
    [
      Row(title: .siriWidgetsSiriNextShift, systemImage: "calendar"),
      Row(title: .siriWidgetsSiriEarnings, systemImage: "banknote"),
      Row(title: .siriWidgetsSiriHours, systemImage: "clock"),
      Row(title: .siriWidgetsSiriEarnedSoFar, systemImage: "chart.line.uptrend.xyaxis"),
      Row(title: .siriWidgetsSiriClockOut, systemImage: "stop.circle"),
      Row(title: .siriWidgetsSiriExtendShift, systemImage: "timer"),
      Row(title: .siriWidgetsSiriAddShift, systemImage: "plus.circle"),
      Row(title: .siriWidgetsSiriFriendSchedule, systemImage: "person.2"),
    ]
  }

  private var widgetRows: [Row] {
    [
      Row(title: .widgetNameNextShift, detail: .widgetDescNextShift, systemImage: "calendar"),
      Row(title: .widgetNameShift, detail: .widgetDescLockScreen, systemImage: "lock"),
      Row(
        title: .widgetNameMonthlyTotal, detail: .widgetDescMonthlyTotal, systemImage: "banknote"),
      Row(title: .widgetNameFriendsShift, detail: .widgetDescFriendsShift, systemImage: "person"),
      Row(
        title: .widgetNameFriendsShifts, detail: .widgetDescFriendsShifts, systemImage: "person.2"),
    ]
  }

  var body: some View {
    Form {
      Group {
        Section {
          ForEach(siriRows, id: \.systemImage, content: rowView)
        } header: {
          Text(.siriWidgetsSiriHeader)
        } footer: {
          ShortcutsLink()
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.sm)
        }

        Section {
          ForEach(widgetRows, id: \.systemImage, content: rowView)
        } header: {
          Text(.siriWidgetsWidgetsHeader)
        } footer: {
          Text(.siriWidgetsWidgetsFooter)
        }

        Section(String(localized: .siriWidgetsLiveActivityHeader)) {
          Text(.siriWidgetsLiveActivityDescription)
            .font(.tidexBody)
            .foregroundStyle(Color.tidexTextPrimary)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle(String(localized: .settingsMenuSiriWidgetsLabel))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func rowView(_ row: Row) -> some View {
    Label {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(row.title)
          .font(.tidexBody)
          .foregroundStyle(Color.tidexTextPrimary)

        if let detail = row.detail {
          Text(detail)
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)
        }
      }
    } icon: {
      Image(systemName: row.systemImage)
        .foregroundStyle(Color.tidexBlueText)
    }
  }
}

#Preview {
  NavigationStack {
    SiriAndWidgetsSettingsView()
  }
}
