import Supabase
import SwiftUI
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "SettingsView")

/// Settings main menu view
/// Displays a list of settings options in iOS Settings style
struct SettingsView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.dismiss) private var dismiss
  @Environment(\.layoutDirection) private var layoutDirection

  /// Whether the current user is an admin
  @State private var isAdmin = false
  /// Whether sign out is in progress
  @State private var isSigningOut = false
  /// Whether global sign out is in progress
  @State private var isSigningOutGlobal = false
  /// Whether to show the global sign out confirmation alert
  @State private var showSignOutEverywhereAlert = false
  /// Navigation path for settings subviews
  @State private var navigationPath = NavigationPath()

  /// Settings navigation destinations
  enum SettingsDestination: Hashable {
    case profile
    case security
    case subscription
    case notifications
    case appearance
    case pay
    case recurringShifts
    case data
    case feedback
    case admin
    #if DEBUG
      case debug
    #endif
  }

  /// Compute user initials from display name for avatar fallback
  private var userInitials: String {
    let components = coordinator.userDisplayName.split(separator: " ")
    if components.count >= 2 {
      return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
    }
    return String(coordinator.userDisplayName.prefix(1)).uppercased()
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      List {
        // MARK: - Profile Card
        Section {
          Button {
            navigationPath.append(SettingsDestination.profile)
          } label: {
            HStack(spacing: 14) {
              AvatarView(
                url: coordinator.userAvatarUrl,
                initials: userInitials,
                size: 60
              )

              VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.userDisplayName)
                  .font(.tidexTitle)
                  .foregroundColor(.tidexTextPrimary)

                Text(.settingsMenuAccountDescription)
                  .font(.tidexSubheadline)
                  .foregroundColor(.tidexTextSecondary)
                  .lineLimit(2)
              }

              Spacer()

              Image(
                systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right"
              )
              .font(.tidexLabelStrong)
              .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)

        // MARK: - Account & Security
        Section(header: Text(String(localized: .settingsGroupAccountSecurity))) {
          SettingsMenuItem(
            icon: "lock.shield",
            title: String(localized: .settingsMenuSecurityLabel),
            description: String(localized: .settingsMenuSecurityDescription),
            iconBackgroundColor: .green
          ) {
            navigationPath.append(SettingsDestination.security)
          }

          SettingsMenuItem(
            icon: "creditcard",
            title: String(localized: .settingsMenuSubscriptionLabel),
            description: String(localized: .settingsMenuSubscriptionDescription),
            iconBackgroundColor: .orange
          ) {
            navigationPath.append(SettingsDestination.subscription)
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)

        // MARK: - Preferences
        Section(header: Text(String(localized: .settingsGroupPreferences))) {
          SettingsMenuItem(
            icon: "bell",
            title: String(localized: .settingsMenuNotificationsLabel),
            description: String(localized: .settingsMenuNotificationsDescription),
            iconBackgroundColor: .red
          ) {
            navigationPath.append(SettingsDestination.notifications)
          }

          SettingsMenuItem(
            icon: "paintpalette",
            title: String(localized: .settingsMenuAppearanceLabel),
            description: String(localized: .settingsMenuAppearanceDescription),
            iconBackgroundColor: .indigo
          ) {
            navigationPath.append(SettingsDestination.appearance)
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)

        // MARK: - App Settings
        Section(header: Text(String(localized: .settingsGroupAppSettings))) {
          SettingsMenuItem(
            icon: "banknote",
            title: String(localized: .settingsMenuPayLabel),
            description: String(localized: .settingsMenuPayDescription),
            iconBackgroundColor: .green
          ) {
            navigationPath.append(SettingsDestination.pay)
          }

          SettingsMenuItem(
            icon: "repeat.circle",
            title: String(localized: .settingsMenuRecurringShiftsLabel),
            description: String(localized: .settingsMenuRecurringShiftsDescription),
            iconBackgroundColor: .purple
          ) {
            navigationPath.append(SettingsDestination.recurringShifts)
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)

        // MARK: - Data & Support
        Section(header: Text(String(localized: .settingsGroupDataSupport))) {
          SettingsMenuItem(
            icon: "externaldrive",
            title: String(localized: .settingsMenuDataLabel),
            description: String(localized: .settingsMenuDataDescription),
            iconBackgroundColor: .gray
          ) {
            navigationPath.append(SettingsDestination.data)
          }

          SettingsMenuItem(
            icon: "message",
            title: String(localized: .settingsMenuFeedbackLabel),
            description: String(localized: .settingsMenuFeedbackDescription),
            iconBackgroundColor: .tidexBlue
          ) {
            navigationPath.append(SettingsDestination.feedback)
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)

        // MARK: - Admin
        if isAdmin {
          Section(header: Text(String(localized: .settingsGroupAdmin))) {
            SettingsMenuItem(
              icon: "shield.lefthalf.filled.badge.checkmark",
              title: String(localized: .settingsMenuAdminLabel),
              description: String(localized: .settingsMenuAdminDescription),
              iconBackgroundColor: .tidexWarning
            ) {
              navigationPath.append(SettingsDestination.admin)
            }
          }
          .listRowBackground(Color.tidexSurfacePrimary)
        }

        // MARK: - Sign Out
        Section {
          signOutRow
          signOutEverywhereRow
        }
        .listRowBackground(Color.tidexSurfacePrimary)

        // MARK: - Debug (DEBUG builds only)
        #if DEBUG
          Section(header: Text("Debug")) {
            SettingsMenuItem(
              icon: "ladybug",
              title: "Debug",
              description: "Sync, StoreKit, and notification diagnostics",
              iconBackgroundColor: .pink
            ) {
              navigationPath.append(SettingsDestination.debug)
            }
          }
          .listRowBackground(Color.tidexSurfacePrimary)
        #endif
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(Color.tidexBackground)
      .toolbar {
        ToolbarItem(placement: .principal) {
          VStack(spacing: 2) {
            Text(.settingsTitle)
              .font(.tidexHeadline)
              .foregroundColor(.tidexTextPrimary)

            Text(.settingsSubtitle)
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextSecondary)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.tidexBodyMedium)
              .foregroundStyle(Color.tidexTextMuted)
          }
        }
      }
      .navigationDestination(for: SettingsDestination.self) { destination in
        Group {
          switch destination {
          case .profile:
            ProfileSettingsView()
          case .security:
            SecuritySettingsView()
          case .subscription:
            SubscriptionSettingsView()
          case .notifications:
            NotificationSettingsView()
          case .appearance:
            AppearanceSettingsView()
          case .pay:
            PaySettingsView()
          case .recurringShifts:
            RecurringShiftsSettingsView()
          case .data:
            DataSettingsView()
          case .feedback:
            FeedbackSettingsView()
          case .admin:
            AdminSettingsView()
          #if DEBUG
            case .debug:
              SyncDebugView()
          #endif
          }
        }
        .toolbarRole(.editor)
      }
    }
    .task {
      await checkAdminStatus()
    }
    .alert(
      String(localized: .userMenuLogoutEverywhereConfirmTitle),
      isPresented: $showSignOutEverywhereAlert
    ) {
      Button(String(localized: .userMenuLogoutEverywhereConfirmCancel), role: .cancel) {}
      Button(String(localized: .userMenuLogoutEverywhereConfirmAction), role: .destructive) {
        Task {
          await signOutGlobal()
        }
      }
    } message: {
      Text(.userMenuLogoutEverywhereConfirmDescription)
    }
  }

  // MARK: - Sign Out Rows

  /// Sign out from this device only (local scope)
  private var signOutRow: some View {
    Button {
      Task {
        await signOut()
      }
    } label: {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "rectangle.portrait.and.arrow.right")
          .font(.system(size: 14))
          .foregroundColor(.white)
          .frame(width: 29, height: 29)
          .background(
            Color.tidexError.opacity(0.75),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )

        if isSigningOut {
          ProgressView()
            .tint(.tidexError)
          Text(String(localized: .userMenuLoggingOut))
            .foregroundColor(.tidexError)
        } else {
          Text(String(localized: .userMenuLogout))
            .foregroundColor(.tidexError)
        }

        Spacer()
      }
    }
    .disabled(isSigningOut || isSigningOutGlobal)
  }

  /// Sign out from ALL devices (global scope)
  private var signOutEverywhereRow: some View {
    Button {
      showSignOutEverywhereAlert = true
    } label: {
      HStack(spacing: Spacing.sm) {
        Image(systemName: "rectangle.portrait.and.arrow.right.fill")
          .font(.tidexFootnoteMedium)
          .foregroundColor(.white)
          .frame(width: 29, height: 29)
          .background(
            Color.gray.opacity(0.75),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )

        if isSigningOutGlobal {
          ProgressView()
            .tint(.tidexTextSecondary)
          Text(String(localized: .userMenuLogoutEverywhereLoading))
            .foregroundColor(.tidexTextSecondary)
        } else {
          Text(String(localized: .userMenuLogoutEverywhere))
            .foregroundColor(.tidexTextSecondary)
        }

        Spacer()
      }
    }
    .disabled(isSigningOut || isSigningOutGlobal)
  }

  // MARK: - Actions

  private func checkAdminStatus() async {
    do {
      let session = try await AuthSessionManager.shared.getSession()
      // Check app_metadata for admin role
      // The role is stored in app_metadata which is set by the backend
      if let appMetadata = session.user.appMetadata["role"],
        case .string(let role) = appMetadata,
        role == "admin"
      {
        isAdmin = true
      }
    } catch {
      // Silently fail - non-admin is the default
      logger.debug("Could not check admin status: \(error.localizedDescription)")
    }
  }

  private func signOut() async {
    isSigningOut = true
    await coordinator.signOut()
    dismiss()
    isSigningOut = false
  }

  private func signOutGlobal() async {
    isSigningOutGlobal = true
    await coordinator.signOutGlobal()
    dismiss()
    isSigningOutGlobal = false
  }
}

// MARK: - Recurring Shifts Settings

private struct RecurringShiftsSettingsView: View {
  @State private var recurringShifts: [RecurringShiftRow] = []
  @State private var recurringShiftToEdit: RecurringShiftRow?
  @State private var isLoading = true
  @State private var errorMessage: String?

  private let impactHaptic = UIImpactFeedbackGenerator(style: .light)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.mlg) {
        headerSection

        if let errorMessage {
          errorBanner(errorMessage)
        }

        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Spacing.lg)
        } else if recurringShifts.isEmpty {
          emptyState
        } else {
          VStack(spacing: 10) {
            ForEach(recurringShifts, id: \.id) { recurring in
              recurringShiftRow(recurring)
            }
          }
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .settingsRecurringShiftsTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadRecurringShifts()
    }
    .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
      Task {
        await loadRecurringShifts()
      }
    }
    .sheet(item: $recurringShiftToEdit) { recurring in
      RecurringShiftEditorSheet(
        recurringShift: recurring,
        onSave: { editResult in
          recurringShiftToEdit = nil
          Task {
            await updateRecurringShift(editResult)
          }
        },
        onDelete: {
          let recurringId = recurring.id
          recurringShiftToEdit = nil
          Task {
            await deleteRecurringShift(recurringId)
          }
        }
      )
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
  }

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(.settingsRecurringShiftsTitle)
        .font(.title2)
        .fontWeight(.bold)
        .foregroundColor(.tidexTextPrimary)

      Text(.settingsRecurringShiftsSubtitle)
        .font(.subheadline)
        .foregroundColor(.tidexTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var emptyState: some View {
    VStack(spacing: Spacing.xs) {
      Text(.settingsRecurringShiftsEmptyTitle)
        .font(.tidexButton)
        .foregroundColor(.tidexTextPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(.settingsRecurringShiftsEmptyDescription)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(12)
    .tidexCardShadow(cornerRadius: 12)
  }

  private func recurringShiftRow(_ recurring: RecurringShiftRow) -> some View {
    let exclusionCount = recurring.effectiveExclusions.count

    return Button {
      impactHaptic.impactOccurred()
      recurringShiftToEdit = recurring
    } label: {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(verbatim: "\(recurring.cleanStartTime) - \(recurring.cleanEndTime)")
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)

        HStack(spacing: 6) {
          Text(weekdaySummary(for: recurring.selected_days))
          Text("•")
          Text(repeatLabel(for: recurring.repeat_interval_weeks))
          if exclusionCount > 0 {
            Text("•")
            Text(String(localized: .settingsRecurringShiftsExcludedCount(exclusionCount)))
          }
        }
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(12)
      .tidexCardShadow(cornerRadius: 12)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func errorBanner(_ message: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)
      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)
      Spacer()
    }
    .padding(Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.tidexError.opacity(0.1))
    )
  }

  private func loadRecurringShifts() async {
    isLoading = true
    errorMessage = nil

    do {
      let session = try await AuthSessionManager.shared.getSession()
      let shifts = RecurringShiftsRepository.shared.getRecurringShifts(
        for: session.normalizedUserId)
      recurringShifts = sortRecurringShifts(shifts)
    } catch {
      logger.error("Failed to load recurring shifts settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsLoadFailed)
    }

    isLoading = false
  }

  private func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {
    do {
      _ = try await RecurringShiftsRepository.shared.updateRecurringShift(
        id: editResult.recurringId,
        startTime: editResult.startTime,
        endTime: editResult.endTime,
        repeatIntervalWeeks: editResult.repeatIntervalWeeks,
        selectedDays: editResult.selectedDays,
        endCondition: editResult.endCondition,
        exclusions: editResult.exclusions
      )

      await loadRecurringShifts()
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)
      Haptics.play(.success)
    } catch {
      logger.error("Failed to update recurring shift from settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsSaveFailed)
    }
  }

  private func deleteRecurringShift(_ recurringId: String) async {
    do {
      try await RecurringShiftsRepository.shared.deleteRecurringShift(id: recurringId)
      await loadRecurringShifts()
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)
      Haptics.play(.success)
    } catch {
      logger.error("Failed to delete recurring shift from settings: \(error.localizedDescription)")
      errorMessage = String(localized: .settingsRecurringShiftsDeleteFailed)
    }
  }

  private func sortRecurringShifts(_ shifts: [RecurringShiftRow]) -> [RecurringShiftRow] {
    shifts.sorted { lhs, rhs in
      let lhsEarliestAnchor = lhs.selected_days.values.min() ?? "9999-12-31"
      let rhsEarliestAnchor = rhs.selected_days.values.min() ?? "9999-12-31"
      if lhsEarliestAnchor != rhsEarliestAnchor {
        return lhsEarliestAnchor < rhsEarliestAnchor
      }
      if lhs.cleanStartTime != rhs.cleanStartTime {
        return lhs.cleanStartTime < rhs.cleanStartTime
      }
      return lhs.id < rhs.id
    }
  }

  private func weekdaySummary(for selectedDays: SelectedDays) -> String {
    let order = ["1", "2", "3", "4", "5", "6", "0"]
    var calendar = Calendar.current
    calendar.locale = Locale(identifier: Locale.current.identifier)
    let symbols = calendar.shortWeekdaySymbols
    let labels =
      order
      .filter { selectedDays[$0] != nil }
      .compactMap { key -> String? in
        guard let index = Int(key), index >= 0, index < symbols.count else { return nil }
        return symbols[index]
      }
    return labels.joined(separator: ", ")
  }

  private func repeatLabel(for repeatInterval: Int) -> String {
    if repeatInterval == 0 {
      return String(localized: .addShiftEveryWeek)
    }
    return String(localized: .addShiftEveryNWeeks(repeatInterval + 1))
  }
}

// MARK: - Settings Menu Item

/// A single settings menu item with colored icon background, title, description, and chevron
/// Designed for use inside a List section (iOS Settings style)
struct SettingsMenuItem: View {
  let icon: String
  let title: String
  let description: String
  var iconBackgroundColor: Color = .tidexBlue
  let action: () -> Void

  @Environment(\.layoutDirection) private var layoutDirection

  var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.sm) {
        // Icon with colored background (fixed size to fit 29x29 container)
        Image(systemName: icon)
          .font(.system(size: 14))
          .foregroundColor(.white)
          .frame(width: 29, height: 29)
          .background(
            iconBackgroundColor.opacity(0.75),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )

        // Title and description
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .font(.body)
            .foregroundColor(.tidexTextPrimary)

          Text(description)
            .font(.caption)
            .foregroundColor(.tidexTextSecondary)
            .lineLimit(2)
        }

        Spacer()

        // Chevron
        Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
          .font(.tidexLabelStrong)
          .foregroundStyle(.tertiary)
      }
    }
  }
}

// MARK: - Preview

#Preview {
  SettingsView()
    .environmentObject(AppCoordinator.shared)
}
