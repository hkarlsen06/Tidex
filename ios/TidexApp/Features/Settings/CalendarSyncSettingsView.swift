import SwiftUI

struct CalendarSyncSettingsView: View {
  @State private var viewModel: DataSettingsViewModel
  @State private var showDisableCalendarConfirmation = false
  @State private var setupMode: CalendarSubscriptionContentMode

  init(calendarSetupIntent: CalendarSubscriptionSetupIntent? = nil) {
    _viewModel = State(
      wrappedValue: DataSettingsViewModel(calendarSetupIntent: calendarSetupIntent))
    _setupMode = State(initialValue: calendarSetupIntent?.mode ?? .shiftsAndEvents)
  }

  var body: some View {
    Form {
      Group {
        if let error = viewModel.errorMessage {
          Section {
            ErrorBanner(message: error, onDismiss: { viewModel.clearError() })
          }
        }

        if viewModel.isLoadingCalendarSubscription {
          Section {
            HStack(spacing: Spacing.sm) {
              ProgressView()
              Text(.calendarSubscriptionLoading)
                .foregroundColor(.tidexTextSecondary)
            }
          }
        } else {
          modeSection
          actionsSection

          if viewModel.calendarSubscriptionFallbackURL != nil {
            fallbackSection
          }

          if viewModel.calendarSubscriptionState.metadata != nil {
            disableSection
          }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle(String(localized: .calendarSubscriptionTitle))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if viewModel.isUpdatingCalendarSubscription {
        ToolbarItem(placement: .topBarTrailing) {
          ProgressView()
        }
      }
    }
    .task {
      await viewModel.loadSettings()
    }
    .confirmationDialog(
      String(localized: .calendarSubscriptionDisableTitle),
      isPresented: $showDisableCalendarConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: .calendarSubscriptionDisableButton), role: .destructive) {
        Task {
          await viewModel.disableCalendarSubscription()
        }
      }
      Button(String(localized: .commonCancel), role: .cancel) {}
    } message: {
      Text(.calendarSubscriptionDisableMessage)
    }
  }

  /// Before setup the picker only chooses the mode to create; afterwards it updates the live feed.
  private var modeSelection: Binding<CalendarSubscriptionContentMode> {
    Binding(
      get: { viewModel.calendarSubscriptionState.metadata?.contentMode ?? setupMode },
      set: { mode in
        guard viewModel.calendarSubscriptionState.metadata != nil else {
          setupMode = mode
          return
        }
        Task {
          await viewModel.updateCalendarSubscriptionMode(mode)
        }
      }
    )
  }

  private var modeSection: some View {
    Section {
      Picker(selection: modeSelection) {
        ForEach(CalendarSubscriptionContentMode.allCases) { mode in
          Label(mode.localizedTitle, systemImage: mode.systemImage)
            .tag(mode)
        }
      } label: {
        Text(.calendarSubscriptionIncludeLabel)
      }
      .pickerStyle(.inline)
      .labelsHidden()
      .disabled(viewModel.isUpdatingCalendarSubscription)
    } header: {
      Text(.calendarSubscriptionIncludeLabel)
    } footer: {
      Text(
        viewModel.calendarSubscriptionState.isActive
          ? .calendarSubscriptionActiveDescription
          : .calendarSubscriptionInactiveDescription
      )
    }
  }

  @ViewBuilder
  private var actionsSection: some View {
    Section {
      if viewModel.calendarSubscriptionState.metadata != nil {
        if CalendarSubscriptionStore.shared.activeMetadata != nil {
          Button {
            Task {
              await viewModel.openCalendarSubscription()
            }
          } label: {
            Label(String(localized: .calendarSubscriptionOpenButton), systemImage: "arrow.up.forward.app")
          }
        }

        Button {
          Task {
            await viewModel.rotateCalendarSubscription()
          }
        } label: {
          Label(String(localized: .calendarSubscriptionRotateButton), systemImage: "arrow.clockwise")
        }
      } else {
        Button {
          Task {
            await viewModel.setupCalendarSubscription(mode: setupMode)
          }
        } label: {
          Label(String(localized: .calendarSubscriptionSetupButton), systemImage: "calendar.badge.plus")
        }
      }
    }
    .foregroundColor(.tidexBlue)
    .disabled(viewModel.isUpdatingCalendarSubscription)
  }

  private var fallbackSection: some View {
    Section {
      Button {
        viewModel.copyCalendarSubscriptionFallbackURL()
      } label: {
        Label(String(localized: .calendarSubscriptionCopyLinkButton), systemImage: "doc.on.doc")
      }
      .foregroundColor(.tidexBlue)
    } footer: {
      Text(.calendarSubscriptionFallbackDescription)
    }
  }

  private var disableSection: some View {
    Section {
      Button(role: .destructive) {
        showDisableCalendarConfirmation = true
      } label: {
        Label(String(localized: .calendarSubscriptionDisableButton), systemImage: "stop.circle")
      }
      .foregroundColor(.tidexError)
      .disabled(viewModel.isUpdatingCalendarSubscription)
    }
  }
}

#Preview {
  NavigationStack {
    CalendarSyncSettingsView()
  }
}

extension CalendarSubscriptionContentMode {
  fileprivate var systemImage: String {
    switch self {
    case .eventsOnly:
      return "calendar"

    case .shiftsOnly:
      return "briefcase"

    case .shiftsAndEvents:
      return "calendar.badge.clock"
    }
  }
}
