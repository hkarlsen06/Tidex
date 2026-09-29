import SwiftUI
import UIKit

struct PaySettingsSheet: View {
  let jobId: String?
  let workDate: Date
  var initiallyExpandPayReview = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      PaySettingsView(
        initialJobId: jobId, initialDate: workDate,
        initiallyExpandPayReview: initiallyExpandPayReview
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonDone)) { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
  }
}

struct EditWorkplaceSheet: View {
  @Environment(\.dismiss) private var dismiss

  let onSave: (String, String?) async -> Bool

  @State private var name: String
  @State private var selectedColor: Color
  @State private var isSaving = false
  @State private var saveError: String?

  init(
    initialName: String,
    initialColorHex: String?,
    onSave: @escaping (String, String?) async -> Bool
  ) {
    self.onSave = onSave
    _name = State(initialValue: initialName)
    _selectedColor = State(
      initialValue: Self.colorFromHex(initialColorHex)
        ?? Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    )
  }

  var body: some View {
    NavigationStack {
      formContent
        .tidexListBackground()
        .navigationTitle(String(localized: .settingsPayEditJobTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }
  }

  private var formContent: some View {
    Form {
      Group {
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
      .listRowBackground(Color.tidexSurfacePrimary)
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
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

  private func save() async {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      saveError = String(localized: .settingsPayAddJobErrorName)
      return
    }

    isSaving = true
    let didSave = await onSave(trimmedName, Self.normalizedHex(from: selectedColor))
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

/// Blocks the screen until the user picks a workplace that still exists.
struct RequiredJobReselectionSheet: View {
  @Environment(\.dismiss) private var dismiss

  let jobs: [Job]
  let onSelect: (String) -> Void

  var body: some View {
    NavigationStack {
      jobList
        .tidexListBackground()
        .navigationTitle(String(localized: .settingsMenuPayLabel))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: .commonCancel)) { dismiss() }
          }
        }
    }
  }

  private var jobList: some View {
    List {
      Group {
        Section {
          Text(.settingsPayChooseJobUnavailable)
            .foregroundStyle(Color.tidexTextSecondary)
          ForEach(jobs) { job in
            Button {
              onSelect(job.id)
            } label: {
              WorkplaceNameText(
                name: job.name,
                colorHex: job.color,
                fallbackBadgeColor: .tidexBlue
              )
            }
            .buttonStyle(.plain)
          }
        } header: {
          HStack(spacing: Spacing.xxxs) {
            Image(systemName: "building.2")
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexBlue)
              .accessibilityHidden(true)
            Text(.settingsPayChooseJobTitle)
          }
          .textCase(nil)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
  }
}
