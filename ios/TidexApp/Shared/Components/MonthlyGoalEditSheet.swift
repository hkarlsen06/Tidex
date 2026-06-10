// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable closure_body_length conditional_returns_on_newline explicit_acl explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface legacy_objc_type no_empty_block number_separator
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable prefer_key_path type_contents_order
import SwiftUI

/// Sheet for editing month-specific goal overrides.
/// Saving an empty value removes the override for that month.
struct MonthlyGoalEditSheet: View {
  let monthDate: Date
  let baselineGoal: Int?
  let initialGoal: Int?
  let showsAdjustmentPercentageFootnote: Bool
  let onSave: (Int?) async throws -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var goalText: String
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    monthDate: Date,
    baselineGoal: Int?,
    initialGoal: Int?,
    showsAdjustmentPercentageFootnote: Bool = false,
    onSave: @escaping (Int?) async throws -> Void
  ) {
    self.monthDate = monthDate
    self.baselineGoal = baselineGoal
    self.initialGoal = initialGoal
    self.showsAdjustmentPercentageFootnote = showsAdjustmentPercentageFootnote
    self.onSave = onSave
    _goalText = State(initialValue: initialGoal.map(String.init) ?? "")
  }

  private var parsedGoal: Int? {
    let trimmed = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let parsed = Int(trimmed), parsed > 0 else { return nil }
    return parsed
  }

  private var hasChanges: Bool {
    parsedGoal != initialGoal
  }

  private var canSave: Bool {
    let trimmed = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
    let isEmpty = trimmed.isEmpty
    return hasChanges && (isEmpty || parsedGoal != nil)
  }

  private var goalInputPlaceholder: String {
    if let baselineGoal, baselineGoal > 0 {
      return NumberFormatter.localizedString(from: NSNumber(value: baselineGoal), number: .decimal)
    }
    return String(localized: .settingsPayGlobalMonthlyGoalPlaceholder)
  }

  private var monthGoalHeader: String {
    let monthGoalTitle = String(localized: .statsMonthlyGoalTitle)
    let monthText = monthDate.formatted(.dateTime.month(.wide).year())
    return "\(monthGoalTitle) (\(monthText)):"
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(monthGoalHeader)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        HStack {
          TextField(goalInputPlaceholder, text: $goalText)
            .keyboardType(.numberPad)
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
            .tint(.tidexBlue)
            .onChange(of: goalText) { _, newValue in
              let filtered = newValue.filter(\.isNumber)
              if filtered != newValue {
                goalText = filtered
              }
            }
        }
        .padding(Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))

        Text(.settingsPayGlobalMonthlyGoalHelper)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)

        if showsAdjustmentPercentageFootnote {
          Text(.dashboardMonthlyGoalAdjustmentPercentageFootnote)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Spacing.xxs)
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.top, Spacing.md)
      .navigationTitle(String(localized: .statsMonthlyGoalTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonSave)) {
            Task {
              await save()
            }
          }
          .disabled(!canSave || isSaving)
        }
      }
      .alert(
        String(localized: .commonError),
        isPresented: .init(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button(String(localized: .commonOk), role: .cancel) {
          errorMessage = nil
        }
      } message: {
        if let errorMessage {
          Text(errorMessage)
        }
      }
    }
    .onAppear {
      // Ensure the text field reflects the passed value each time the sheet opens.
      goalText = initialGoal.map(String.init) ?? ""
    }
  }

  private func save() async {
    guard canSave, !isSaving else { return }
    isSaving = true
    defer { isSaving = false }

    do {
      try await onSave(parsedGoal)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview {
  MonthlyGoalEditSheet(
    monthDate: Date(),
    baselineGoal: 20_000,
    initialGoal: 20_000,
    onSave: { _ in }
  )
}
