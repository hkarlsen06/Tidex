import SwiftUI

struct WorkSetupRequiredPlaceholder: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @State private var isRefreshingBeforeSetup = false
  private let syncCoordinator = SyncCoordinator.shared
  private let workSetupStatusService = WorkSetupStatusService.shared

  var body: some View {
    VStack(spacing: Spacing.mlg) {
      Spacer()

      Image(systemName: "briefcase.badge.plus")
        .font(.system(size: 52, weight: .regular))
        .foregroundColor(.tidexBlue.opacity(0.8))

      VStack(spacing: Spacing.sm) {
        Text("work_setup.required.title", tableName: "Localizable")
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)

        Text("work_setup.required.description", tableName: "Localizable")
          .font(.tidexBody)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }

      Button {
        Task {
          await refreshBeforeOpeningSetup()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          if isRefreshingBeforeSetup {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
              .scaleEffect(0.8)
          }

          Text("work_setup.required.cta", tableName: "Localizable")
            .font(.tidexButton)
        }
        .foregroundColor(.tidexTextOnBrand)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(
          isRefreshingBeforeSetup
            ? Color.tidexBrandPrimary.opacity(0.7)
            : Color.tidexBrandPrimary
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(isRefreshingBeforeSetup)

      Spacer()
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, Spacing.lg)
  }

  @MainActor
  private func refreshBeforeOpeningSetup() async {
    guard !isRefreshingBeforeSetup else { return }
    guard let userId = coordinator.getCurrentUserId() else { return }

    isRefreshingBeforeSetup = true
    defer { isRefreshingBeforeSetup = false }

    _ = await syncCoordinator.sync(
      reason: .manualRefresh,
      userId: userId,
      tables: [.jobs, .wageSnapshots],
      updateWidgetStorage: false
    )

    coordinator.objectWillChange.send()
    NotificationCenter.default.post(name: .workSetupDataDidChange, object: nil)

    let status = workSetupStatusService.status(for: userId)
    guard !status.isWorkSetupComplete else { return }

    coordinator.requestPostAuthOnboardingReentry()
  }
}
