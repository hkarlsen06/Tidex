import SwiftUI
import UIKit

struct AddJobBasicsInput {
  let name: String
  let color: String?
  let currency: String
  let payrollDay: Int
  let halfTaxMonth: Int?
  let monthlyGoal: Int?
}

struct AddJobBasicsSheet: View {
  @Environment(\.dismiss) private var dismiss

  let initialCurrency: String
  let initialPayrollDay: Int
  let initialHalfTaxMonth: Int?
  let initialMonthlyGoal: Int?
  let onSave: (AddJobBasicsInput) async -> Bool

  @State private var name = ""
  @State private var selectedColor = Color.tidexBlue
  @State private var isSaving = false
  @State private var saveError: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(String(localized: .settingsPayAddJobName), text: $name)
            .textInputAutocapitalization(.words)

          VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(.settingsPayAddJobColorLabel)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)

            WorkplaceColorCarousel(selectedHex: Self.normalizedHex(from: selectedColor)) { hex in
              selectedColor = Self.colorFromHex(hex) ?? .tidexBlue
            }
          }
        }

        if let saveError {
          Section {
            Text(saveError)
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
          }
        }
      }
      .navigationTitle(String(localized: .settingsPayAddJobTitle))
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
          .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private func save() async {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      saveError = String(localized: .settingsPayAddJobErrorName)
      return
    }

    isSaving = true
    saveError = nil
    let didSave = await onSave(
      AddJobBasicsInput(
        name: trimmedName,
        color: Self.normalizedHex(from: selectedColor),
        currency: initialCurrency,
        payrollDay: initialPayrollDay,
        halfTaxMonth: initialHalfTaxMonth,
        monthlyGoal: initialMonthlyGoal
      ))
    isSaving = false

    if didSave {
      dismiss()
    } else {
      saveError = String(localized: .settingsPayErrorSaveFailed)
    }
  }

  private static func normalizedHex(from color: Color) -> String? {
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return nil
    }

    return String(
      format: "#%02X%02X%02X",
      Int(red * 255),
      Int(green * 255),
      Int(blue * 255)
    )
  }

  private static func colorFromHex(_ hex: String?) -> Color? {
    guard var hex else { return nil }
    hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") {
      hex.removeFirst()
    }
    guard hex.count == 6, let int = Int(hex, radix: 16) else {
      return nil
    }
    let red = Double((int >> 16) & 0xFF) / 255.0
    let green = Double((int >> 8) & 0xFF) / 255.0
    let blue = Double(int & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
  }
}
