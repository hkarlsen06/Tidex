import SwiftUI

#if DEBUG
  import Foundation
  import QuartzCore
#endif

extension View {
  /// Logs every value SwiftUI computes for `value` while it animates, for `scripts/motion-check`.
  /// Records only in Debug builds launched with `-motion-probe`. Release builds return `self`.
  func motionProbe(_ name: String, _ value: CGFloat) -> some View {
    motionProbe(name, Double(value))
  }

  /// Logs every value SwiftUI computes for `value` while it animates, for `scripts/motion-check`.
  /// Records only in Debug builds launched with `-motion-probe`. Release builds return `self`.
  func motionProbe(_ name: String, _ value: Double) -> some View {
    #if DEBUG
      background(
        MotionProbeLog.isEnabled ? MotionProbeView(name: name, value: value) : nil
      )
    #else
      self
    #endif
  }
}

#if DEBUG
  /// SwiftUI interpolates `animatableData` and runs `body` once per animation frame, and once
  /// when the value changes with no animation, so each change produces one sample.
  private struct MotionProbeView: View, Animatable {
    let name: String
    var value: Double
    // SwiftUI writes `animatableData` for an animation frame and not for a value set with no
    // animation, such as a finger drag.
    private var isAnimationFrame = false

    init(name: String, value: Double) {
      self.name = name
      self.value = value
    }

    // Animatable's requirement is nonisolated, while View makes this type main-actor isolated.
    nonisolated var animatableData: Double {
      get { value }
      set {
        value = newValue
        isAnimationFrame = true
      }
    }

    // SwiftUI skips a body that produces no view, so the probe draws a clear color. A
    // modifier that returns its content unchanged is skipped the same way.
    var body: some View {
      MotionProbeLog.shared.record(name, value, isAnimationFrame: isAnimationFrame)
      return Color.clear
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }

  /// Appends `name<TAB>t<TAB>value<TAB>a|d` lines to `Library/Caches/motion-probe.tsv`, where
  /// `a` marks an animation frame and `d` a value set directly. The first sample of a launch
  /// truncates the file. Each sample goes straight to the file so a killed app loses nothing.
  @MainActor
  private final class MotionProbeLog: NSObject {
    static let shared = MotionProbeLog()
    nonisolated static let isEnabled: Bool =
      ProcessInfo.processInfo.arguments.contains("-motion-probe")

    private static let unopened: Int32 = -2
    private var fileDescriptor: Int32 = MotionProbeLog.unopened
    private var displayLink: CADisplayLink?
    // SwiftUI computes each animated value for a display frame, and the body that records it
    // can run late. The frame's own time keeps a late body from looking like a slow frame.
    private var frameTime: CFTimeInterval?

    func record(_ name: String, _ value: Double, isAnimationFrame: Bool) {
      if displayLink == nil {
        let link = CADisplayLink(target: self, selector: #selector(frameDidStart))
        link.add(to: .main, forMode: .common)
        displayLink = link
      }
      if fileDescriptor == Self.unopened {
        let path = URL.cachesDirectory.appending(path: "motion-probe.tsv")
          .path(percentEncoded: false)
        fileDescriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, S_IRUSR | S_IWUSR)
      }
      guard fileDescriptor >= 0 else { return }
      let time = String(format: "%.6f", frameTime ?? CACurrentMediaTime())
      let source = isAnimationFrame ? "a" : "d"
      let line = Array("\(name)\t\(time)\t\(String(format: "%.6f", value))\t\(source)\n".utf8)
      line.withUnsafeBytes { bytes in
        _ = write(fileDescriptor, bytes.baseAddress, bytes.count)
      }
    }

    @objc
    private func frameDidStart(_ link: CADisplayLink) {
      frameTime = link.targetTimestamp
    }
  }
#endif
