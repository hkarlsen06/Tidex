import SwiftUI

struct ScheduleTimeZoneSection: View {
  @Bindable var viewModel: ProfileSettingsViewModel
  @State private var search = ""

  private var zones: [String] {
    (["UTC"] + TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") })
      .filter {
        search.isEmpty
          || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(search)
      }
  }

  var body: some View {
    Section {
      NavigationLink {
        zonePicker
      } label: {
        LabeledContent {
          switch viewModel.scheduleTimeZoneLoadState {
          case .loading:
            ProgressView()
          case .failed:
            Text(.commonErrorLoadFailed)
          case .loaded(let zone):
            if let zone {
              Text(verbatim: zone.replacingOccurrences(of: "_", with: " "))
            } else {
              Text(.profileScheduleTimeZoneNotSet)
            }
          }
        } label: {
          Text(.profileScheduleTimeZoneTitle)
        }
      }
      .disabled(!viewModel.canEditScheduleTimeZone)

      if viewModel.scheduleZoneDiffersFromDevice {
        Text(.profileScheduleTimeZoneDifferent)
          .foregroundStyle(Color.tidexTextSecondary)
      }
      if viewModel.canEditScheduleTimeZone,
        SharedShiftInterval.scheduleZone(TimeZone.current.identifier) != nil,
        viewModel.scheduleTimeZone == nil || viewModel.scheduleZoneDiffersFromDevice
      {
        Button(.profileScheduleTimeZoneUseDevice) {
          Task { await viewModel.saveScheduleTimeZone(TimeZone.current.identifier) }
        }
        .disabled(
          viewModel.isSavingScheduleTimeZone || viewModel.isOfflineProfileFallback
            || viewModel.isLoading)
      }
    } footer: {
      Text(.profileScheduleTimeZoneDescription)
    }
  }

  private var zonePicker: some View {
    List(zones, id: \.self) { zone in
      Button {
        Task { await viewModel.saveScheduleTimeZone(zone) }
      } label: {
        HStack {
          Text(verbatim: zone.replacingOccurrences(of: "_", with: " "))
          Spacer()
          if zone == viewModel.scheduleTimeZone {
            Image(systemName: "checkmark").accessibilityHidden(true)
          }
        }
        .foregroundStyle(Color.tidexTextPrimary)
      }
      .accessibilityAddTraits(zone == viewModel.scheduleTimeZone ? .isSelected : [])
      .disabled(viewModel.isSavingScheduleTimeZone)
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .searchable(text: $search, prompt: Text(.profileScheduleTimeZoneSearch))
    .navigationTitle(Text(.profileScheduleTimeZoneTitle))
    .safeAreaInset(edge: .top) {
      if let error = viewModel.errorMessage {
        ErrorBanner(message: error, onDismiss: { viewModel.errorMessage = nil })
          .padding(.horizontal, Spacing.md)
      }
    }
  }
}
