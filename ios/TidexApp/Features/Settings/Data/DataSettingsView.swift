import SwiftUI

/// Data export settings view
/// Allows users to export their shift data as PDF or CSV
struct DataSettingsView: View {
  private let presets: [ExportPeriodPreset] = [
    .lastMonth, .currentMonth, .lastYear, .currentYear, .custom,
  ]

  @State private var viewModel = DataSettingsViewModel()

  var body: some View {
    Form {
      Group {
        if let error = viewModel.errorMessage {
          Section {
            ErrorBanner(message: error, onDismiss: { viewModel.clearError() })
          }
        }

        periodSection
        exportSection

        if let shareURL = viewModel.shareURL {
          shareSection(url: shareURL)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle(String(localized: .dataTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadSettings()
    }
  }

  // MARK: - Period Section

  private var periodSection: some View {
    Section {
      Picker(selection: $viewModel.selectedPreset) {
        ForEach(presets) { preset in
          Text(presetLabel(preset))
            .tag(Optional(preset))
        }
      } label: {
        Text(.dataExportPeriodLabel)
      }
      .pickerStyle(.inline)
      .labelsHidden()

      if viewModel.selectedPreset == .custom {
        // Each bound keeps the other valid, so the range can't be inverted.
        DatePicker(
          selection: $viewModel.customFromDate,
          in: ...viewModel.customToDate,
          displayedComponents: .date
        ) {
          Text(.dataExportFromLabel)
        }

        DatePicker(
          selection: $viewModel.customToDate,
          in: viewModel.customFromDate...,
          displayedComponents: .date
        ) {
          Text(.dataExportToLabel)
        }
      }
    } header: {
      Text(.dataExportPeriodLabel)
    }
    .tint(.tidexBlue)
  }

  private func presetLabel(_ preset: ExportPeriodPreset) -> String {
    let now = Date()
    let calendar = Calendar.gregorianCurrent
    let monthFormat = Date.FormatStyle.dateTime.month(.wide).calendar(.gregorian)

    switch preset {
    case .lastMonth:
      guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else {
        return ""
      }
      return lastMonth.formatted(monthFormat).sentenceCased()

    case .currentMonth:
      return now.formatted(monthFormat).sentenceCased()

    case .lastYear:
      return String(calendar.component(.year, from: now) - 1)

    case .currentYear:
      return String(calendar.component(.year, from: now))

    case .custom:
      return String(localized: .dataExportCustomPeriod)
    }
  }

  // MARK: - Export Section

  private var exportSection: some View {
    Section {
      exportRow(
        icon: "doc.text",
        title: String(localized: .dataExportPdfTitle),
        description: String(localized: .dataExportPdfDescription),
        isLoading: viewModel.isExportingPdf
      ) {
        Task {
          await viewModel.exportShifts(format: .pdf, locale: Locale.current)
        }
      }

      exportRow(
        icon: "tablecells",
        title: String(localized: .dataExportCsvTitle),
        description: String(localized: .dataExportCsvDescription),
        isLoading: viewModel.isExportingCsv
      ) {
        Task {
          await viewModel.exportShifts(format: .csv, locale: Locale.current)
        }
      }
    } footer: {
      Text(.dataExportAboutDescription)
    }
  }

  private func exportRow(
    icon: String,
    title: String,
    description: String,
    isLoading: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: Spacing.sm) {
        Label {
          VStack(alignment: .leading, spacing: Spacing.micro) {
            Text(title)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)

            Text(isLoading && viewModel.isSyncing ? String(localized: .dataExportSyncing) : description)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
        } icon: {
          Image(systemName: icon)
            .foregroundColor(.tidexBlue)
        }

        Spacer(minLength: Spacing.xs)

        if isLoading {
          ProgressView()
        } else {
          Image(systemName: "square.and.arrow.down")
            .foregroundColor(.tidexBlue)
            .accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .disabled(!viewModel.canExport)
  }

  // MARK: - Share Section

  private func shareSection(url: URL) -> some View {
    Section {
      ShareLink(item: url) {
        Label {
          VStack(alignment: .leading, spacing: Spacing.micro) {
            Text(.dataExportShare)
              .foregroundColor(.tidexBlue)

            Text(url.lastPathComponent)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
        } icon: {
          Image(systemName: "square.and.arrow.up")
            .foregroundColor(.tidexBlue)
        }
      }
    } header: {
      Text(.dataExportReadyToShare)
    }
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    DataSettingsView()
  }
}
