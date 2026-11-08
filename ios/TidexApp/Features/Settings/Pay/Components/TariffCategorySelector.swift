import SwiftUI

struct TariffCategorySelector: View {
  let levels: [TariffLevel]
  @Binding var selectedLevel: Int
  @State private var showsCategories = false

  private var selected: TariffLevel? { levels.first { $0.level == selectedLevel } }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.tariffPayCategory)
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexTextSecondary)
      Button {
        showsCategories = true
      } label: {
        selectedCategoryLabel
      }
      .buttonStyle(.plain)
      .multilineTextAlignment(.leading)
      .accessibilityIdentifier("tariff.category-picker")
      .accessibilityLabel(Text(.tariffPayCategory))
      .accessibilityValue(
        selected.map { "\($0.displayName), \($0.formattedRate)" }
          ?? String(localized: .tariffChooseOption))
    }
    .sheet(isPresented: $showsCategories) {
      TariffCategorySheet(levels: levels, selectedLevel: selectedLevel) { level in
        selectedLevel = level.level
      }
    }
  }
  private var selectedCategoryLabel: some View {
    HStack(spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(selected?.displayName ?? String(localized: .tariffChooseOption))
          .font(.tidexBodyMedium)
          .foregroundStyle(Color.tidexTextPrimary)
          .fixedSize(horizontal: false, vertical: true)
        if let selected {
          Text(verbatim: selected.formattedRate)
            .font(.tidexButton)
            .foregroundStyle(Color.tidexBlueText)
            .accessibilityIdentifier("pay-settings.hourly-wage")
        }
      }
      Spacer(minLength: Spacing.xs)
      Image(systemName: "chevron.up.chevron.down")
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextMuted)
        .accessibilityHidden(true)
    }
    .padding(Spacing.sm)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    .contentShape(Rectangle())
  }

}

private struct TariffCategorySheet: View {
  let levels: [TariffLevel]
  let selectedLevel: Int
  let onSelect: (TariffLevel) -> Void
  @State private var search = ""
  @Environment(\.dismiss) private var dismiss

  private var filtered: [TariffLevel] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return levels.filter { query.isEmpty || $0.displayName.localizedStandardContains(query) }
  }

  var body: some View {
    NavigationStack {
      List(filtered) { level in
        categoryRow(level)
      }
      .tidexListBackground()
      .searchable(text: $search)
      .navigationTitle(Text(.tariffPayCategory))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(.commonCancel) { dismiss() }
        }
      }
    }
    .presentationDragIndicator(.visible)
  }
  private func categoryRow(_ level: TariffLevel) -> some View {
    Button {
      onSelect(level)
      dismiss()
    } label: {
      HStack(spacing: Spacing.sm) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(verbatim: level.displayName)
            .font(.tidexBodyMedium)
            .foregroundStyle(Color.tidexTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
          Text(verbatim: level.formattedRate)
            .font(.tidexSubheadline)
            .foregroundStyle(Color.tidexTextSecondary)
        }
        Spacer(minLength: Spacing.xs)
        if level.level == selectedLevel {
          Image(systemName: "checkmark")
            .foregroundStyle(Color.tidexBlueText)
            .accessibilityHidden(true)
        }
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .accessibilityIdentifier("tariff.category.\(level.level)")
    .accessibilityAddTraits(level.level == selectedLevel ? .isSelected : [])
    .listRowBackground(Color.tidexSurfacePrimary)
  }

}
