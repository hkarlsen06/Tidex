// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface
import SwiftUI

/// Full-screen block for `AppGate`. It replaces everything else, signed in or not.
struct AppGateView: View {
  let block: AppGateBlock
  let onRetry: () async -> Void

  @Environment(\.openURL) private var openURL
  @State private var isRetrying = false

  var body: some View {
    ContentUnavailableView {
      switch block {
      case .updateRequired:
        Label(String(localized: .appGateUpdateTitle), systemImage: "arrow.down.app")
      case .maintenance:
        Label(String(localized: .appGateMaintenanceTitle), systemImage: "wrench.and.screwdriver")
      }
    } description: {
      switch block {
      case .updateRequired:
        Text(.appGateUpdateMessage)
      case .maintenance:
        Text(.appGateMaintenanceMessage)
      }
    } actions: {
      switch block {
      case .updateRequired:
        Button(String(localized: .appGateUpdateButton)) {
          openURL(APIConfiguration.appStoreURL)
        }
        .buttonStyle(.borderedProminent)
        .tint(.tidexBlue)
      case .maintenance:
        Button(String(localized: .commonRetry)) {
          Task {
            isRetrying = true
            await onRetry()
            isRetrying = false
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(.tidexBlue)
        .disabled(isRetrying)
      }
    }
  }
}

#Preview("Update required") {
  AppGateView(block: .updateRequired) {}  // swiftlint:disable:this no_empty_block
    .background(Color.tidexBackground)
}

#Preview("Maintenance") {
  AppGateView(block: .maintenance) {}  // swiftlint:disable:this no_empty_block
    .background(Color.tidexBackground)
}
