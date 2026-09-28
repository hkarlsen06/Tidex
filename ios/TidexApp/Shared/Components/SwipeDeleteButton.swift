import SwiftUI

/// Delete button for `.swipeActions`. Always use this instead of a bare
/// `Button(role: .destructive)`. iOS 26 draws destructive swipe buttons in any
/// inherited tint, so an ancestor `.tint(.tidexTextPrimary)` once gave a white
/// button behind a white icon in dark mode.
struct SwipeDeleteButton: View {
  var title: String = String(localized: .shiftsActionsDelete)
  let action: () -> Void

  var body: some View {
    Button(role: .destructive, action: action) {
      Label(title, systemImage: "trash")
    }
    .tint(.tidexError)
  }
}
