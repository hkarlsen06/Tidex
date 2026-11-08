import SwiftUI

struct TariffSetupSelector: View {
  let types: [TariffType]
  let selectedTypeID: String?
  let onSelect: (String?, String?) -> Void

  @Binding private var draft: TariffSelection?
  @State private var lastResolvedID: String?
  @State private var showsAgreements = false

  init(
    types: [TariffType], selectedTypeID: String?, draft: Binding<TariffSelection?>,
    onSelect: @escaping (String?, String?) -> Void
  ) {
    self.types = types
    self.selectedTypeID = selectedTypeID
    self.onSelect = onSelect
    _draft = draft
    _lastResolvedID = State(initialValue: selectedTypeID)
  }

  private var selection: TariffSelection {
    get { draft ?? TariffSelection(types: types, selectedTypeID: selectedTypeID) }
    nonmutating set { draft = newValue }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      agreementPicker
      ForEach(selection.dimensions) { dimension in
        dimensionPicker(dimension)
      }
    }
    .sheet(isPresented: $showsAgreements) {
      TariffAgreementSheet(families: selection.families, selectedID: selection.selectedFamilyID) {
        family in
        guard family.id != selection.selectedFamilyID else { return }
        selection.selectFamily(family.id)
        publishSelection()
      }
    }
    .onChange(of: selectedTypeID) { _, id in
      let incoming = id.flatMap { $0.isEmpty ? nil : $0 }
      if incoming != selection.resolvedTypeID {
        selection = TariffSelection(types: types, selectedTypeID: incoming)
        lastResolvedID = incoming
      }
    }
    .onChange(of: types) { _, values in
      selection = TariffSelection(types: values, selectedTypeID: selectedTypeID)
    }
  }

  private var agreementPicker: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.tariffAgreement)
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexTextSecondary)
      Button {
        showsAgreements = true
      } label: {
        choiceLabel(
          selection.selectedFamily?.displayName ?? String(localized: .tariffChooseAgreement))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("tariff.agreement")
      .accessibilityLabel(Text(.tariffAgreement))
      .accessibilityValue(
        selection.selectedFamily?.displayName ?? String(localized: .tariffChooseAgreement))
      if selection.selectedFamily?.kind == .statutory {
        Text(.tariffStatutoryMinimums)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
      }
    }
  }

  private func dimensionPicker(_ dimension: TariffSelectionDimension) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(verbatim: dimension.label)
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexTextSecondary)
      if dimension.options.count == 1, let option = dimension.options.first {
        Text(verbatim: option.valueLabel)
          .font(.tidexBodyMedium)
          .foregroundStyle(Color.tidexTextPrimary)
      } else {
        dimensionMenu(dimension)
      }
      if let help = dimension.help, dimension.isEnabled {
        Text(verbatim: help)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
      }
    }
  }

  private func dimensionMenu(_ dimension: TariffSelectionDimension) -> some View {
    Menu {
      ForEach(dimension.options, id: \.value) { option in
        Button {
          selection.selectOption(dimensionID: dimension.id, value: option.value)
          publishSelection()
        } label: {
          if selection.selectedValues[dimension.id] == option.value {
            Label(option.valueLabel, systemImage: "checkmark")
          } else {
            Text(verbatim: option.valueLabel)
          }
        }
        .accessibilityIdentifier("tariff.option.\(dimension.id).\(option.value)")
      }
    } label: {
      choiceLabel(
        dimension.options.first { $0.value == selection.selectedValues[dimension.id] }?
          .valueLabel
          ?? String(localized: .tariffChooseOption))
    }
    .disabled(!dimension.isEnabled)
    .opacity(dimension.isEnabled ? 1 : 0.5)
    .accessibilityIdentifier("tariff.dimension.\(dimension.id)")
    .accessibilityLabel(dimension.label)
    .accessibilityValue(
      dimension.options.first { $0.value == selection.selectedValues[dimension.id] }?
        .valueLabel
        ?? String(localized: .tariffChooseOption))
  }

  private func publishSelection() {
    let id = selection.resolvedTypeID
    onSelect(id, lastResolvedID)
    if let id { lastResolvedID = id }
  }

  private func choiceLabel(_ value: String) -> some View {
    HStack(spacing: Spacing.sm) {
      Text(verbatim: value)
        .font(.tidexBodyMedium)
        .foregroundStyle(Color.tidexTextPrimary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
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

private struct TariffAgreementSheet: View {
  let families: [TariffFamily]
  let selectedID: String?
  let onSelect: (TariffFamily) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""

  private var filtered: [TariffFamily] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return families.filter { family in
      query.isEmpty
        || ([family.displayName] + family.searchTerms)
          .contains { $0.localizedStandardContains(query) }
    }
    .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
  }

  var body: some View {
    NavigationStack {
      List {
        if filtered.isEmpty {
          Text(.tariffNoAgreements)
            .foregroundStyle(Color.tidexTextSecondary)
            .listRowBackground(Color.tidexBackground)
        }
        familySection(filtered.filter { $0.kind == .agreement }, title: .tariffCollectiveAgreements)
        familySection(filtered.filter { $0.kind == .statutory }, title: .tariffStatutoryMinimums)
        familySection(filtered.filter { $0.kind == nil }, title: .tariffAgreement)
      }
      .tidexListBackground()
      .searchable(text: $search, prompt: Text(.tariffSearchAgreements))
      .navigationTitle(Text(.tariffChooseAgreement))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(.commonCancel) { dismiss() }
        }
      }
    }
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder
  private func familySection(_ values: [TariffFamily], title: LocalizedStringResource) -> some View
  {
    if !values.isEmpty {
      Section {
        ForEach(values) { family in
          Button {
            onSelect(family)
            dismiss()
          } label: {
            HStack(spacing: Spacing.sm) {
              Text(verbatim: family.displayName)
                .foregroundStyle(Color.tidexTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: Spacing.xs)
              if selectedID == family.id {
                Image(systemName: "checkmark")
                  .foregroundStyle(Color.tidexBlueText)
                  .accessibilityHidden(true)
              }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          }
          .accessibilityIdentifier("tariff.family.\(family.id)")
          .accessibilityAddTraits(selectedID == family.id ? .isSelected : [])
          .listRowBackground(Color.tidexSurfacePrimary)
        }
      } header: {
        Text(title)
      }
    }
  }
}
