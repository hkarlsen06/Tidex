import SwiftUI

struct CalendarSyncSettingsView: View {
  @StateObject private var viewModel: DataSettingsViewModel
  @State private var showDisableCalendarConfirmation = false
  @State private var setupMode: CalendarSubscriptionContentMode

  init(calendarSetupIntent: CalendarSubscriptionSetupIntent? = nil) {
    _viewModel = StateObject(
      wrappedValue: DataSettingsViewModel(calendarSetupIntent: calendarSetupIntent))
    _setupMode = State(initialValue: calendarSetupIntent?.mode ?? .shiftsAndEvents)
  }

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(spacing: Spacing.lg) {
          if let error = viewModel.errorMessage {
            ErrorBanner(message: error, onDismiss: { viewModel.clearError() })
          }

          calendarSubscriptionSection
            .frame(minHeight: max(proxy.size.height - Spacing.xxl, 0), alignment: .top)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.lg)
      }
    }
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .calendarSubscriptionTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadSettings()
    }
  }

  private var calendarSubscriptionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      calendarSubscriptionHeader
        .padding(.top, viewModel.calendarSubscriptionState.isActive ? 0 : Spacing.xxl)

      Spacer(minLength: Spacing.xxl)

      if viewModel.isLoadingCalendarSubscription {
        loadingIndicator
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if let metadata = viewModel.calendarSubscriptionState.metadata {
        calendarModeOptions(metadata: metadata)
      } else {
        setupCalendarModeOptions
      }

      Spacer(minLength: Spacing.xxl)

      if viewModel.calendarSubscriptionFallbackURL != nil {
        fallbackLinkSection
          .padding(.bottom, Spacing.md)
      }

      if viewModel.calendarSubscriptionState.metadata != nil {
        activeCalendarSubscriptionActions
      } else if !viewModel.isLoadingCalendarSubscription {
        setupCalendarSubscriptionButton
      }
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

  private var calendarSubscriptionHeader: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "calendar.badge.clock")
        .font(.system(size: 20, weight: .medium))
        .foregroundColor(.tidexBlue)
        .frame(width: 40, height: 40)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.md)
            .fill(Color.tidexBlue.opacity(0.12))
        )

      VStack(alignment: .leading, spacing: Spacing.xxxs) {
        Text(
          viewModel.calendarSubscriptionState.isActive
            ? .calendarSubscriptionActiveDescription
            : .calendarSubscriptionInactiveDescription
        )
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
  }

  private var loadingIndicator: some View {
    HStack(spacing: Spacing.sm) {
      ProgressView()
        .scaleEffect(0.8)
      Text(.calendarSubscriptionLoading)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
  }

  private func calendarModeOptions(
    metadata: CalendarSubscriptionMetadata
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.calendarSubscriptionIncludeLabel)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)
        .textCase(.uppercase)
        .padding(.horizontal, Spacing.sm)

      ForEach(CalendarSubscriptionContentMode.allCases) { mode in
        calendarModeButton(
          mode,
          isSelected: metadata.contentMode == mode,
          action: {
            Task {
              await viewModel.updateCalendarSubscriptionMode(mode)
            }
          })
      }
    }
  }

  private var setupCalendarModeOptions: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.calendarSubscriptionIncludeLabel)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)
        .textCase(.uppercase)
        .padding(.horizontal, Spacing.sm)

      ForEach(CalendarSubscriptionContentMode.allCases) { mode in
        calendarModeButton(
          mode,
          isSelected: setupMode == mode,
          action: {
            setupMode = mode
          })
      }
    }
  }

  private var activeCalendarSubscriptionActions: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      if CalendarSubscriptionStore.shared.activeMetadata != nil {
        openCalendarSubscriptionButton
      }

      Button {
        Task {
          await viewModel.rotateCalendarSubscription()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "arrow.clockwise")
          Text(.calendarSubscriptionRotateButton)
        }
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlue)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.md)
            .fill(Color.tidexBlue.opacity(0.1))
        )
      }
      .buttonStyle(.plain)
      .disabled(viewModel.isUpdatingCalendarSubscription)

      Button(role: .destructive) {
        showDisableCalendarConfirmation = true
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "stop.circle")
          Text(.calendarSubscriptionDisableButton)
        }
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.md)
            .fill(Color.tidexSurfaceSecondary)
        )
      }
      .buttonStyle(.plain)
      .disabled(viewModel.isUpdatingCalendarSubscription)
    }
  }

  private var openCalendarSubscriptionButton: some View {
    Button {
      Task {
        await viewModel.openCalendarSubscription()
      }
    } label: {
      calendarSubscriptionButtonLabel(
        title: String(localized: .calendarSubscriptionOpenButton),
        systemImage: "arrow.up.forward.app",
        isLoading: viewModel.isUpdatingCalendarSubscription
      )
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isUpdatingCalendarSubscription)
  }

  private var setupCalendarSubscriptionButton: some View {
    Button {
      Task {
        await viewModel.setupCalendarSubscription(mode: setupMode)
      }
    } label: {
      calendarSubscriptionButtonLabel(
        title: String(localized: .calendarSubscriptionSetupButton),
        systemImage: "calendar.badge.plus",
        isLoading: viewModel.isUpdatingCalendarSubscription
      )
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isUpdatingCalendarSubscription)
  }

  private var fallbackLinkSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.calendarSubscriptionFallbackDescription)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)

      Button {
        viewModel.copyCalendarSubscriptionFallbackURL()
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "doc.on.doc")
          Text(.calendarSubscriptionCopyLinkButton)
        }
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlue)
      }
      .buttonStyle(.plain)
    }
  }

  private func calendarModeButton(
    _ mode: CalendarSubscriptionContentMode,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      guard !isSelected else { return }
      action()
    } label: {
      HStack(spacing: Spacing.sm) {
        Image(systemName: mode.systemImage)
          .font(.tidexBodyMedium)
          .foregroundColor(isSelected ? .tidexBlue : .tidexTextSecondary)
          .frame(width: 28, height: 28)

        Text(mode.localizedTitle)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        Spacer(minLength: Spacing.sm)

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.tidexBodyMedium)
          .foregroundColor(isSelected ? .tidexBlue : .tidexTextMuted)
      }
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.md)
          .fill(isSelected ? Color.tidexBlue.opacity(0.1) : Color.tidexSurfacePrimary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.md)
          .stroke(isSelected ? Color.tidexBlue : Color.tidexBorderSubtle, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isUpdatingCalendarSubscription)
  }

  private func calendarSubscriptionButtonLabel(
    title: String,
    systemImage: String,
    isLoading: Bool
  ) -> some View {
    HStack(spacing: Spacing.xs) {
      if isLoading {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
          .scaleEffect(0.8)
      } else {
        Image(systemName: systemImage)
      }

      Text(title)
        .font(.tidexLabelStrong)
    }
    .foregroundColor(.tidexTextOnBrand)
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.md)
        .fill(Color.tidexBlue)
    )
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
