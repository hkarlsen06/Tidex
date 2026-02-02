import SwiftUI

/// Data export settings view
/// Allows users to export their shift data as PDF or CSV
struct DataSettingsView: View {
        @StateObject private var viewModel = DataSettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

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
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color.tidexBackground)
        .navigationTitle(String(localized: .dataTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.tidexBackground, for: .navigationBar)
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

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.dataExportTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.tidexTextPrimary)

            Text(.dataExportDescription)
                .font(.subheadline)
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.tidexError)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextPrimary)

            Spacer()

            Button {
                viewModel.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .padding(12)
        .background(Color.tidexError.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Syncing Indicator

    private var syncingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                .scaleEffect(0.8)

            Text(.dataExportSyncing)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)

            Spacer()
        }
        .padding(12)
        .background(Color.tidexBlue.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Period Selection Section

    private var periodSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(.dataExportPeriodLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .textCase(.uppercase)

            Text(.dataExportPeriodDescription)
                .font(.system(size: 13))
                .foregroundColor(.tidexTextSecondary)

            // Preset buttons
            HStack(spacing: 8) {
                ForEach([ExportPeriodPreset.lastMonth, .currentMonth, .currentYear], id: \.self) { preset in
                    presetButton(preset)
                }
            }

            // Divider with "or"
            HStack {
                Rectangle()
                    .fill(Color.tidexBorder)
                    .frame(height: 1)
                Text(String(localized: .commonOr).uppercased())
                    .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .tidexTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.tidexBlue : Color.tidexSurfaceSecondary)
                )
        }
        .buttonStyle(.plain)
    }

    private func presetLabel(_ preset: ExportPeriodPreset) -> String {
        let now = Date()
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current.tidexLanguage.formatterLocale

        switch preset {
        case .lastMonth:
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else {
                return ""
            }
            dateFormatter.dateFormat = "MMMM"
            return dateFormatter.string(from: lastMonth).capitalized
        case .currentMonth:
            dateFormatter.dateFormat = "MMMM"
            return dateFormatter.string(from: now).capitalized
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
            VStack(alignment: .leading, spacing: 16) {
                Text(.dataExportCustomPeriod)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)

                // Date pickers in a balanced row
                HStack(spacing: 12) {
                    // From date
                    VStack(alignment: .leading, spacing: 6) {
                        Text(.dataExportFromLabel)
                            .font(.system(size: 11, weight: .semibold))
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(.dataExportToLabel)
                            .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 12))
                        .foregroundColor(.tidexError)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tidexSurfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.tidexBlue : Color.tidexBorder, lineWidth: isSelected ? 2 : 1)
            )
            .tidexCardShadow(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export Buttons Section

    private var exportButtonsSection: some View {
        VStack(spacing: 16) {
            // PDF Export
            exportCard(
                icon: "doc.text.fill",
                iconColor: Color(red: 1.0, green: 0.0, blue: 0.0), // Red for PDF
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
        VStack(alignment: .leading, spacing: 16) {
            // Header row with icon and title
            HStack(spacing: 12) {
                // Icon in colored background
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(iconColor.opacity(0.15))
                    )

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()
            }

            // Description
            Text(description)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Full-width button
            Button(action: action) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .medium))
                    }

                    Text(buttonLabel)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(viewModel.canExport ? buttonColor : buttonColor.opacity(0.5))
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canExport || isLoading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tidexSurfacePrimary)
        )
        .tidexCardShadow(cornerRadius: 12)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.dataExportAboutTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexTextMuted)

            Text(.dataExportAboutDescription)
                .font(.system(size: 13))
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
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
