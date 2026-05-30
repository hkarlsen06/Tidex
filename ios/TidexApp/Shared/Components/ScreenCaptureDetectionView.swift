import SwiftUI
import UIKit

struct ScreenCaptureDetectionView: UIViewRepresentable {
  let onCaptureStarted: @MainActor () -> Void

  func makeUIView(context: Context) -> CaptureStateView {
    let view = CaptureStateView()
    view.onCaptureStarted = onCaptureStarted
    return view
  }

  func updateUIView(_ uiView: CaptureStateView, context: Context) {
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
      (view: CaptureStateView, _) in
      view.reportCurrentStateIfNeeded()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
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
