import SwiftUI

/// Data export settings view
/// Allows users to export their shift data as PDF or CSV
struct DataSettingsView: View {
  private let presetColumns = [
    GridItem(.flexible(), spacing: Spacing.xs),
    GridItem(.flexible(), spacing: Spacing.xs),
  ]

  @StateObject private var viewModel = DataSettingsViewModel()

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.lg) {
        // Error message
        if let error = viewModel.errorMessage {
          errorBanner(error)
        }

        // Sync indicator
        if viewModel.isSyncing {
          syncingIndicator
        }

        // Period selection
        periodSelectionSection

        // Export buttons
        exportButtonsSection

        // About section
        aboutSection
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .dataTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadSettings()
    }
    .sheet(item: $viewModel.shareURL) { url in
      ShareSheet(activityItems: [url])
        .onDisappear {
          viewModel.dismissShareSheet()
        }
    }
  }

  // MARK: - Error Banner

  private func errorBanner(_ message: String) -> some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.tidexBody)
        .foregroundColor(.tidexError)

      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextPrimary)

      Spacer()

      Button {
        viewModel.clearError()
      } label: {
        Image(systemName: "xmark")
          .font(.tidexCaption)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .padding(Spacing.sm)
    .background(Color.tidexError.opacity(0.1))
    .cornerRadius(CornerRadius.sm)
  }

  // MARK: - Syncing Indicator

  private var syncingIndicator: some View {
    HStack(spacing: Spacing.sm) {
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
        .scaleEffect(0.8)

      Text(.dataExportSyncing)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      Spacer()
    }
    .padding(Spacing.sm)
    .background(Color.tidexBlue.opacity(0.1))
    .cornerRadius(CornerRadius.sm)
  }

  // MARK: - Period Selection Section

  private var periodSelectionSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Section header
      Text(.dataExportPeriodLabel)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextMuted)
        .textCase(.uppercase)

      Text(.dataExportPeriodDescription)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)

      // Preset buttons
      LazyVGrid(columns: presetColumns, spacing: Spacing.xs) {
        ForEach([ExportPeriodPreset.lastMonth, .currentMonth, .lastYear, .currentYear], id: \.self)
        { preset in
          presetButton(preset)
        }
      }

      // Divider with "or"
      HStack {
        Rectangle()
          .fill(Color.tidexBorder)
          .frame(height: 1)
        Text(String(localized: .commonOr).uppercased())
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
        Rectangle()
          .fill(Color.tidexBorder)
          .frame(height: 1)
      }

      // Custom period card
      customPeriodCard
    }
  }

  private func presetButton(_ preset: ExportPeriodPreset) -> some View {
    let isSelected = viewModel.selectedPreset == preset

    return Button {
      viewModel.selectedPreset = preset
    } label: {
      Text(presetLabel(preset))
        .font(.tidexLabel)
        .foregroundColor(isSelected ? .white : .tidexTextSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.sm)
            .fill(isSelected ? Color.tidexBlue : Color.tidexSurfaceSecondary)
        )
    }
    .buttonStyle(.plain)
  }

  private func presetLabel(_ preset: ExportPeriodPreset) -> String {
    let now = Date()
    let calendar = Calendar.current
    let dateFormatter = DateFormatter()

    switch preset {
    case .lastMonth:
      guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else {
        return ""
      }
      dateFormatter.dateFormat = "MMMM"
      return dateFormatter.string(from: lastMonth).sentenceCased()
    case .currentMonth:
      dateFormatter.dateFormat = "MMMM"
      return dateFormatter.string(from: now).sentenceCased()
    case .lastYear:
      return String(calendar.component(.year, from: now) - 1)
    case .currentYear:
      return String(calendar.component(.year, from: now))
    case .custom:
      return String(localized: .dataExportCustomPeriod)
    }
  }

  private var customPeriodCard: some View {
    let isSelected = viewModel.selectedPreset == .custom

    return Button {
      viewModel.selectedPreset = .custom
    } label: {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text(.dataExportCustomPeriod)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        // Date pickers in a balanced row
        HStack(spacing: Spacing.sm) {
          // From date
          VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(.dataExportFromLabel)
              .font(.tidexMicro)
              .foregroundColor(.tidexTextMuted)
              .textCase(.uppercase)

            DatePicker(
              "",
              selection: $viewModel.customFromDate,
              displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .onChange(of: viewModel.customFromDate) { _, _ in
              viewModel.selectedPreset = .custom
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          // To date
          VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(.dataExportToLabel)
              .font(.tidexMicro)
              .foregroundColor(.tidexTextMuted)
              .textCase(.uppercase)

            DatePicker(
              "",
              selection: $viewModel.customToDate,
              displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .onChange(of: viewModel.customToDate) { _, _ in
              viewModel.selectedPreset = .custom
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Error message for invalid range
        if viewModel.isCustomRangeInvalid {
          Text(.dataExportDateRangeError)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexError)
        }
      }
      .padding(Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg)
          .fill(Color.tidexSurfacePrimary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg)
          .stroke(isSelected ? Color.tidexBlue : Color.tidexBorder, lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Export Buttons Section

  private var exportButtonsSection: some View {
    VStack(spacing: Spacing.md) {
      // PDF Export
      exportCard(
        icon: "doc.text.fill",
        iconColor: Color(red: 1.0, green: 0.0, blue: 0.0),  // Red for PDF
        title: String(localized: .dataExportPdfTitle),
        description: String(localized: .dataExportPdfDescription),
        buttonLabel: viewModel.isExportingPdf
          ? String(localized: .dataExportPdfExporting)
          : String(localized: .dataExportPdfButton),
        isLoading: viewModel.isExportingPdf,
        buttonColor: Color(red: 1.0, green: 0.0, blue: 0.0)
      ) {
        Task {
          await viewModel.exportShifts(format: .pdf, locale: Locale.current)
        }
      }

      // CSV Export
      exportCard(
        icon: "tablecells.fill",
        iconColor: .tidexBlue,
        title: String(localized: .dataExportCsvTitle),
        description: String(localized: .dataExportCsvDescription),
        buttonLabel: viewModel.isExportingCsv
          ? String(localized: .dataExportCsvExporting)
          : String(localized: .dataExportCsvButton),
        isLoading: viewModel.isExportingCsv,
        buttonColor: .tidexBlue
      ) {
        Task {
          await viewModel.exportShifts(format: .csv, locale: Locale.current)
        }
      }

    }
  }

  // swiftlint:disable:next function_parameter_count
  private func exportCard(
    icon: String,
    iconColor: Color,
    title: String,
    description: String,
    buttonLabel: String,
    isLoading: Bool,
    buttonColor: Color,
    action: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      // Header row with icon and title
      HStack(spacing: Spacing.sm) {
        // Icon in colored background
        Image(systemName: icon)
          .font(.system(size: 20, weight: .medium))
          .foregroundColor(iconColor)
          .frame(width: 40, height: 40)
          .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
              .fill(iconColor.opacity(0.15))
          )

        Text(title)
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

        Spacer()
      }

      // Description
      Text(description)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)

      // Full-width button
      Button(action: action) {
        HStack(spacing: Spacing.xs) {
          if isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
              .scaleEffect(0.8)
          } else {
            Image(systemName: "square.and.arrow.down")
              .font(.tidexLabel)
          }

          Text(buttonLabel)
            .font(.tidexLabelStrong)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.md)
            .fill(viewModel.canExport ? buttonColor : buttonColor.opacity(0.5))
        )
      }
      .buttonStyle(.plain)
      .disabled(!viewModel.canExport || isLoading)
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexSurfacePrimary)
    )
  }

  // MARK: - About Section

  private var aboutSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.dataExportAboutTitle)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextMuted)

      Text(.dataExportAboutDescription)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, Spacing.xs)
  }
}

// MARK: - Share Sheet

/// Wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
  let activityItems: [Any]
  var applicationActivities: [UIActivity]? = nil

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(
      activityItems: activityItems,
      applicationActivities: applicationActivities
    )
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
  NavigationStack {
    DataSettingsView()
  }
}
