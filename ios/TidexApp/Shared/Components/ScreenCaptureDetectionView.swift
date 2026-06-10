// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_types_order prefer_self_in_static_references required_deinit unused_parameter
import SwiftUI
import UIKit

struct ScreenCaptureDetectionView: UIViewRepresentable {
  let onCaptureStarted: @MainActor () -> Void

  func makeUIView(context _: Context) -> CaptureStateView {
    let view = CaptureStateView()
    view.onCaptureStarted = onCaptureStarted
    return view
  }

  func updateUIView(_ uiView: CaptureStateView, context _: Context) {
    uiView.onCaptureStarted = onCaptureStarted
    uiView.reportCurrentStateIfNeeded()
  }
}

@MainActor
final class CaptureStateView: UIView {
  var onCaptureStarted: (@MainActor () -> Void)?

  private var lastCaptureState: UISceneCaptureState?
  private var captureStateRegistration: (any UITraitChangeRegistration)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isHidden = true
    isUserInteractionEnabled = false
    captureStateRegistration = registerForTraitChanges([UITraitSceneCaptureState.self]) {
      (view: Self, _) in
      view.reportCurrentStateIfNeeded()
    }
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    reportCurrentStateIfNeeded()
  }

  func reportCurrentStateIfNeeded() {
    let currentState = traitCollection.sceneCaptureState
    defer { lastCaptureState = currentState }

    guard currentState == .active, lastCaptureState != .active else { return }
    onCaptureStarted?()
  }
}
