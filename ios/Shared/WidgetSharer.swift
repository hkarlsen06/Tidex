/// Lightweight sharer model for widget App Group storage.
/// Used by the widget extension's EntityQuery to list available friends for configuration.
struct WidgetSharer: Codable, Identifiable, Equatable {
  let id: String
  let displayName: String
  let initials: String
  let showEarnings: Bool
}
