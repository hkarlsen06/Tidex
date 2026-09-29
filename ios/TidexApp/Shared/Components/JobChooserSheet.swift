import SwiftUI

/// Sheet for picking one of the user's active jobs. Used when adding a shift and when clocking in.
struct JobChooserSheet: View {
  /// Shows a checkmark on this job.
  var selectedJobId: String?
  /// Jobs with finished pay setup. Pass nil to hide the setup badge.
  var configuredJobIds: Set<String>?
  /// Loads jobs when `initialJobs` is empty. If exactly one job comes back, it is picked right away.
  var loadJobs: (() async -> [Job])?
  var onAddJob: (() -> Void)?
  var onOpenSettings: (() -> Void)?
  let onSelect: (String) -> Void
  let onCancel: () -> Void

  @State private var jobs: [Job]
  @State private var isLoading: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    jobs: [Job],
    selectedJobId: String? = nil,
    configuredJobIds: Set<String>? = nil,
    loadJobs: (() async -> [Job])? = nil,
    onAddJob: (() -> Void)? = nil,
    onOpenSettings: (() -> Void)? = nil,
    onSelect: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.selectedJobId = selectedJobId
    self.configuredJobIds = configuredJobIds
    self.loadJobs = loadJobs
    self.onAddJob = onAddJob
    self.onOpenSettings = onOpenSettings
    self.onSelect = onSelect
    self.onCancel = onCancel
    _jobs = State(initialValue: jobs)
    _isLoading = State(initialValue: jobs.isEmpty && loadJobs != nil)
  }

  /// Estimated list height, so short lists open as a small sheet.
  private var detentHeight: CGFloat {
    let rows = max(1, jobs.count + (onAddJob == nil ? 0 : 1))
    return ContentSizedSheetMetrics.detentHeight(for: CGFloat(rows) * 56 + Spacing.lg * 2)
  }

  var body: some View {
    NavigationStack {
      List {
        jobsSection
      }
      .tidexListBackground()
      .overlay {
        if isLoading {
          ProgressView()
        }
      }
      .navigationTitle(String(localized: .settingsPayChooseJobTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel), action: onCancel)
        }

        if let onOpenSettings {
          ToolbarItem(placement: .topBarTrailing) {
            Button(action: onOpenSettings) {
              Image(systemName: "gearshape")
            }
            .accessibilityLabel(Text(.settingsMenuPayLabel))
          }
        }
      }
    }
    .task {
      await loadJobsIfNeeded()
    }
    .presentationDetents([.height(detentHeight), .large])
    .presentationDragIndicator(.visible)
  }

  private var jobsSection: some View {
    Section {
      ForEach(jobs, id: \.id) { job in
        row(job)
      }

      if let onAddJob {
        Button(action: onAddJob) {
          Label {
            Text(.settingsPayAddJobCta)
          } icon: {
            Image(systemName: "plus.circle.fill")
          }
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexBlueText)
        }
      }
    }
    .listRowBackground(Color.tidexSurfacePrimary)
  }

  private var nameAndBadgesLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))
  }

  private func row(_ job: Job) -> some View {
    Button {
      onSelect(job.id)
    } label: {
      HStack(spacing: Spacing.sm) {
        // The name and its badges stack at accessibility text sizes so neither truncates.
        nameAndBadgesLayout {
          WorkplaceNameText(
            name: job.name,
            colorHex: job.color,
            font: .tidexBodyMedium,
            fallbackBadgeColor: .tidexBlue,
            lineLimit: 2,
            badgeCornerRadius: CornerRadius.md,
            badgeHorizontalPadding: Spacing.sm,
            badgeVerticalPadding: Spacing.xs
          )
          .layoutPriority(1)

          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: Spacing.sm)
          }

          JobStatusBadges(
            isDefault: job.is_default,
            requiresPaySetup: configuredJobIds.map { !$0.contains(job.id) } ?? false
          )
          .layoutPriority(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if job.id == selectedJobId {
          Image(systemName: "checkmark")
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexBlueText)
            .accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .accessibilityAddTraits(job.id == selectedJobId ? .isSelected : [])
  }

  private func loadJobsIfNeeded() async {
    guard jobs.isEmpty, let loadJobs else { return }
    let loadedJobs = await loadJobs()
    jobs = loadedJobs
    isLoading = false

    if loadedJobs.count == 1, let onlyJobId = loadedJobs.first?.id {
      onSelect(onlyJobId)
    }
  }
}

/// "Default" and "Setup needed" capsules shown next to a job name.
struct JobStatusBadges: View {
  let isDefault: Bool
  let requiresPaySetup: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    badgeLayout {
      if isDefault {
        badge(
          String(localized: .settingsPayChooseJobDefaultBadge),
          color: .tidexBlue, textColor: .tidexBlueText)
      }

      if requiresPaySetup {
        badge(
          String(localized: .settingsPaySetupRequiredBadge),
          color: .tidexWarning, textColor: .tidexWarning)
      }
    }
    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
  }

  private var badgeLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
      : AnyLayout(HStackLayout(spacing: Spacing.xs))
  }

  private func badge(_ title: String, color: Color, textColor: Color) -> some View {
    Text(title)
      .font(.tidexCaptionStrong)
      .foregroundColor(textColor)
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
      .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
      .padding(.horizontal, Spacing.xsm)
      .padding(.vertical, Spacing.xxs)
      .background(color.opacity(0.14), in: Capsule())
  }
}
