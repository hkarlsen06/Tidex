import SwiftUI

/// Leading toolbar title for tab root screens, smaller than the system large title.
internal struct TabTitleToolbarItem: ToolbarContent {
  let title: LocalizedStringResource

  var body: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Text(title)
        .font(.tidexTitle)
        .fixedSize()
        .accessibilityAddTraits(.isHeader)
    }
    .sharedBackgroundVisibility(.hidden)
  }
}
