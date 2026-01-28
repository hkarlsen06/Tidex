import SwiftUI

/// Sheet for selecting a notification reminder time using hours and minutes pickers
struct ReminderTimePickerSheet: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    let isEditing: Bool
    let onSave: () -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @Environment(\.localization) private var localization

    private var totalMinutes: Int {
        (hours * 60) + minutes
    }

    private var canSave: Bool {
        totalMinutes >= 1
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Picker section with description
                VStack(spacing: 12) {
                    // Description label
                    Text(localization.string("notifications.timePicker.description"))
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                        .multilineTextAlignment(.center)

                    // Dual wheel picker
                    HStack(spacing: 0) {
                        // Hours picker (0-48)
                        Picker("", selection: $hours) {
                            ForEach(0...48, id: \.self) { h in
                                Text(localization.currentLocale == .norwegian
                                    ? "\(h) t" : "\(h) h")
                                    .tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        // Minutes picker (0-59)
                        Picker("", selection: $minutes) {
                            ForEach(0..<60, id: \.self) { m in
                                Text("\(m) min")
                                    .tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }
                    .frame(height: 180)
                    .padding(.vertical, 8)
                    .background(Color.tidexSurfacePrimary)
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                // Preview label
                previewLabel

                Spacer()

                // Delete button (only when editing)
                if isEditing, let onDelete = onDelete {
                    deleteButton(action: onDelete)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 24)
            .background(Color.tidexBackground)
            .navigationTitle(isEditing
                ? localization.string("notifications.timePicker.editTitle")
                : localization.string("notifications.timePicker.addTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.string("common.cancel")) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.string("common.save")) {
                        onSave()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var previewLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: canSave ? "bell.fill" : "bell.slash")
                .foregroundColor(canSave ? .tidexBlue : .tidexTextMuted)

            Text(formatPreview())
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(canSave ? .tidexTextPrimary : .tidexTextMuted)
        }
        .padding(12)
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func formatPreview() -> String {
        guard totalMinutes >= 1 else {
            return localization.string("notifications.timePicker.selectTime")
        }

        let h = hours
        let m = minutes

        if h == 0 {
            // Minutes only
            return localization.currentLocale == .norwegian
                ? "\(m) minutt\(m == 1 ? "" : "er") før vakt"
                : "\(m) minute\(m == 1 ? "" : "s") before shift"
        } else if m == 0 {
            // Hours only
            if h == 24 {
                return localization.currentLocale == .norwegian
                    ? "1 dag før vakt"
                    : "1 day before shift"
            } else if h == 48 {
                return localization.currentLocale == .norwegian
                    ? "2 dager før vakt"
                    : "2 days before shift"
            }
            return localization.currentLocale == .norwegian
                ? "\(h) time\(h == 1 ? "" : "r") før vakt"
                : "\(h) hour\(h == 1 ? "" : "s") before shift"
        } else {
            // Mixed hours and minutes
            return localization.currentLocale == .norwegian
                ? "\(h) t \(m) min før vakt"
                : "\(h) h \(m) min before shift"
        }
    }

    @ViewBuilder
    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                Text(localization.string("common.delete"))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.buttonHeight)
            .background(Color.tidexError)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

// MARK: - Preview

#Preview("Add Mode") {
    ReminderTimePickerSheet(
        hours: .constant(1),
        minutes: .constant(0),
        isEditing: false,
        onSave: {},
        onDelete: nil,
        onCancel: {}
    )
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("Edit Mode") {
    ReminderTimePickerSheet(
        hours: .constant(5),
        minutes: .constant(30),
        isEditing: true,
        onSave: {},
        onDelete: {},
        onCancel: {}
    )
    .environment(\.localization, LocalizationManager.shared)
}
