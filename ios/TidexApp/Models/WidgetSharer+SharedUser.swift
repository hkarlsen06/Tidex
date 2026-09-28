// MARK: - SharedUser Extension

extension SharedUser {
  /// Convert to lightweight WidgetSharer for App Group storage
  func toWidgetSharer() -> WidgetSharer {
    WidgetSharer(
      id: id,
      displayName: displayName,
      initials: initials,
      showEarnings: showEarnings
    )
  }
}
