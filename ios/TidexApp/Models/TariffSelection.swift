import Foundation

struct TariffPresentation: Codable, Equatable {
  enum Kind: String, Codable {
    case agreement
    case statutory
  }

  let familyID: String
  let nameEnglish: String
  let nameNorwegian: String
  let kind: Kind
  let searchTerms: [String]
  let categoryGroup: String
  let options: [TariffPresentationOption]

  var displayName: String { Locale.appLocale.isNorwegian ? nameNorwegian : nameEnglish }

  private enum CodingKeys: String, CodingKey {
    case kind, options
    case familyID = "family_id"
    case nameEnglish = "name_en"
    case nameNorwegian = "name_nb"
    case searchTerms = "search_terms"
    case categoryGroup = "category_group"
  }
}

struct TariffPresentationOption: Codable, Equatable, Identifiable {
  let dimensionID: String
  let labelEnglish: String
  let labelNorwegian: String
  var helpEnglish: String?
  var helpNorwegian: String?
  let value: String
  let valueEnglish: String
  let valueNorwegian: String

  var id: String { value }
  var label: String { Locale.appLocale.isNorwegian ? labelNorwegian : labelEnglish }
  var help: String? { Locale.appLocale.isNorwegian ? helpNorwegian : helpEnglish }
  var valueLabel: String { Locale.appLocale.isNorwegian ? valueNorwegian : valueEnglish }

  private enum CodingKeys: String, CodingKey {
    case value
    case dimensionID = "dimension_id"
    case labelEnglish = "label_en"
    case labelNorwegian = "label_nb"
    case helpEnglish = "help_en"
    case helpNorwegian = "help_nb"
    case valueEnglish = "value_en"
    case valueNorwegian = "value_nb"
  }
}

struct TariffFamily: Identifiable, Equatable {
  let id: String
  let types: [TariffType]

  var displayName: String {
    types.first?.presentation?.displayName ?? types.first?.displayName ?? id
  }
  var kind: TariffPresentation.Kind? { types.first?.presentation?.kind }
  var searchTerms: [String] {
    types.flatMap { [$0.displayName] + ($0.presentation?.searchTerms ?? []) }
  }

  fileprivate var dimensionIDs: [String] {
    var result: [String] = []
    for option in types.flatMap({ $0.presentation?.options ?? [] })
    where !result.contains(option.dimensionID) {
      result.append(option.dimensionID)
    }
    return result
  }
}

struct TariffSelectionDimension: Identifiable, Equatable {
  let id: String
  let label: String
  let help: String?
  let options: [TariffPresentationOption]
  let isEnabled: Bool
}

struct TariffSelection: Equatable {
  let families: [TariffFamily]
  private(set) var selectedFamilyID: String?
  private(set) var selectedValues: [String: String] = [:]

  init(types: [TariffType], selectedTypeID: String? = nil) {
    let selectedTypeID = selectedTypeID.flatMap { $0.isEmpty ? nil : $0 }
    var availableTypes = types
    if let selectedTypeID, !types.contains(where: { $0.id == selectedTypeID }) {
      availableTypes.append(
        TariffType(
          id: selectedTypeID, display_name: selectedTypeID, description: nil,
          country: "", is_default: false))
    }
    families = Self.families(from: availableTypes)
    guard let selectedTypeID,
      let family = families.first(where: { $0.types.contains(where: { $0.id == selectedTypeID }) }),
      let type = family.types.first(where: { $0.id == selectedTypeID })
    else { return }
    selectedFamilyID = family.id
    for option in type.presentation?.options ?? [] {
      selectedValues[option.dimensionID] = option.value
    }
  }

  static func families(from types: [TariffType]) -> [TariffFamily] {
    var ids: [String] = []
    var groups: [String: [TariffType]] = [:]
    for type in types {
      let id = type.presentation?.familyID ?? type.id
      if groups[id] == nil { ids.append(id) }
      groups[id, default: []].append(type)
    }
    return ids.map { TariffFamily(id: $0, types: groups[$0] ?? []) }
  }

  var selectedFamily: TariffFamily? { families.first { $0.id == selectedFamilyID } }

  var dimensions: [TariffSelectionDimension] {
    guard let family = selectedFamily else { return [] }
    var candidates = family.types
    var priorAnswersComplete = true
    return family.dimensionIDs.compactMap { dimensionID in
      let options = Self.options(in: candidates, dimensionID: dimensionID)
      guard let first = options.first else { return nil }
      let dimension = TariffSelectionDimension(
        id: dimensionID, label: first.label, help: first.help,
        options: options, isEnabled: priorAnswersComplete)
      if let value = selectedValues[dimensionID] {
        candidates = Self.matching(candidates, dimensionID: dimensionID, value: value)
      } else {
        priorAnswersComplete = false
      }
      return dimension
    }
  }

  var resolvedTypeID: String? {
    guard let family = selectedFamily,
      family.dimensionIDs.allSatisfy({ selectedValues[$0] != nil })
    else { return nil }
    let matches = family.types.filter { type in
      (type.presentation?.options ?? []).allSatisfy {
        selectedValues[$0.dimensionID] == $0.value
      }
    }
    return matches.count == 1 ? matches.first?.id : nil
  }

  mutating func selectFamily(_ id: String) {
    guard id != selectedFamilyID, families.contains(where: { $0.id == id }) else { return }
    selectedFamilyID = id
    selectedValues = [:]
    reconcileOptions()
  }

  mutating func selectOption(dimensionID: String, value: String) {
    guard let dimension = dimensions.first(where: { $0.id == dimensionID }),
      dimension.isEnabled, dimension.options.contains(where: { $0.value == value })
    else { return }
    selectedValues[dimensionID] = value
    reconcileOptions()
  }

  static func canPreserveCategory(from oldType: TariffType?, to newType: TariffType?) -> Bool {
    guard let oldType, let newType else { return false }
    if oldType.id == newType.id { return true }
    guard let old = oldType.presentation, let new = newType.presentation else { return false }
    return old.familyID == new.familyID && !old.categoryGroup.isEmpty
      && old.categoryGroup == new.categoryGroup
  }

  private mutating func reconcileOptions() {
    guard let family = selectedFamily else { return }
    var candidates = family.types
    for dimensionID in family.dimensionIDs {
      let options = Self.options(in: candidates, dimensionID: dimensionID)
      if let value = selectedValues[dimensionID], options.contains(where: { $0.value == value }) {
        candidates = Self.matching(candidates, dimensionID: dimensionID, value: value)
      } else if options.count == 1, let option = options.first {
        selectedValues[dimensionID] = option.value
        candidates = Self.matching(candidates, dimensionID: dimensionID, value: option.value)
      } else {
        selectedValues[dimensionID] = nil
      }
    }
  }

  private static func options(
    in types: [TariffType], dimensionID: String
  ) -> [TariffPresentationOption] {
    var result: [TariffPresentationOption] = []
    for option in types.flatMap({ $0.presentation?.options ?? [] })
    where option.dimensionID == dimensionID && !result.contains(where: { $0.value == option.value })
    {
      result.append(option)
    }
    return result
  }

  private static func matching(
    _ types: [TariffType], dimensionID: String, value: String
  ) -> [TariffType] {
    types.filter { type in
      type.presentation?.options.contains(where: {
        $0.dimensionID == dimensionID && $0.value == value
      })
        == true
    }
  }
}
