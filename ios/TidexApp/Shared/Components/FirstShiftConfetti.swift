import SwiftUI
import UIKit

/// Timing of the first-shift confetti burst.
enum FirstShiftConfetti {
  // Waits for the Add screen's pop to get going, so the burst plays over the screen underneath.
  fileprivate static let startDelay: Duration = .milliseconds(300)
  fileprivate static let emissionDuration: Duration = .milliseconds(600)
  fileprivate static let particleLifetime: Duration = .seconds(3)

  /// Returns once the burst has fallen. A system prompt dims the whole screen, so one that
  /// follows a first shift waits here. Reduce Motion plays no burst, so there is no wait.
  @MainActor
  static func waitUntilFinished() async {
    guard !UIAccessibility.isReduceMotionEnabled else {
      return
    }
    try? await Task.sleep(for: startDelay + emissionDuration + particleLifetime)
  }
}

extension View {
  /// Plays a confetti burst over this view when `CelebrationManager` has a pending first shift.
  func firstShiftConfetti() -> some View {
    modifier(FirstShiftConfettiModifier())
  }
}

private struct FirstShiftConfettiModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isShowingConfetti = false
  private let celebrationManager = CelebrationManager.shared

  func body(content: Content) -> some View {
    content
      .overlay {
        if isShowingConfetti {
          ConfettiBurst { isShowingConfetti = false }
        }
      }
      .onAppear(perform: playPendingCelebration)
      .onChange(of: celebrationManager.isFirstShiftCelebrationPending) { _, isPending in
        if isPending {
          playPendingCelebration()
        }
      }
  }

  private func playPendingCelebration() {
    guard celebrationManager.consumeFirstShiftCelebration(), !reduceMotion else {
      return
    }
    isShowingConfetti = true
  }
}

/// One short confetti burst that falls across the screen, then calls `onFinish`.
private struct ConfettiBurst: View {
  let onFinish: () -> Void
  @State private var isEmitting = false

  var body: some View {
    ConfettiEmitter(isEmitting: isEmitting)
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .task {
        do {
          try await Task.sleep(for: FirstShiftConfetti.startDelay)
          isEmitting = true
          try await Task.sleep(for: FirstShiftConfetti.emissionDuration)
          isEmitting = false
          try await Task.sleep(for: FirstShiftConfetti.particleLifetime)
        } catch {
          return
        }
        onFinish()
      }
  }
}

private struct ConfettiEmitter: UIViewRepresentable {
  let isEmitting: Bool

  func makeUIView(context: Context) -> ConfettiEmitterView {
    ConfettiEmitterView()
  }

  func updateUIView(_ uiView: ConfettiEmitterView, context: Context) {
    uiView.setEmitting(isEmitting)
  }
}

private final class ConfettiEmitterView: UIView {
  private let emitter = CAEmitterLayer()
  private var isEmitting = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    emitter.birthRate = 0
    emitter.emitterShape = .line
    layer.addSublayer(emitter)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    emitter.frame = bounds
    emitter.emitterPosition = CGPoint(x: bounds.midX, y: -12)
    emitter.emitterSize = CGSize(width: bounds.width, height: 1)
  }

  func setEmitting(_ newValue: Bool) {
    guard newValue != isEmitting else {
      return
    }
    isEmitting = newValue
    if newValue {
      emitter.emitterCells = makeCells()
      // Without this the layer starts from its creation time and drops particles mid-fall.
      emitter.beginTime = CACurrentMediaTime()
    }
    emitter.birthRate = newValue ? 1 : 0
  }

  private func makeCells() -> [CAEmitterCell] {
    let colors: [Color] = [.tidexBlue, .tidexPurple, .tidexSuccess, .tidexWarning, .tidexError]
    let shapes: [UIImage] = [Self.strip, Self.dot]
    return colors.flatMap { color in
      let cgColor: CGColor = UIColor(color).resolvedColor(with: traitCollection).cgColor
      return shapes.map { shape in
        let cell = CAEmitterCell()
        cell.contents = shape.cgImage
        cell.contentsScale = shape.scale
        cell.color = cgColor
        // 10 cells for 0.6 s at 24 a second is about 140 pieces.
        cell.birthRate = 24
        cell.lifetime = Float(FirstShiftConfetti.particleLifetime.components.seconds)
        cell.velocity = 170
        cell.velocityRange = 100
        cell.emissionLongitude = .pi
        cell.emissionRange = .pi / 5
        cell.yAcceleration = 160
        cell.spin = 4
        cell.spinRange = 8
        cell.scaleRange = 0.4
        cell.alphaSpeed = -0.15
        return cell
      }
    }
  }

  private static let strip: UIImage = particleImage(size: CGSize(width: 10, height: 6)) { rect in
    UIBezierPath(roundedRect: rect, cornerRadius: 1.5)
  }

  private static let dot: UIImage = particleImage(size: CGSize(width: 7, height: 7)) { rect in
    UIBezierPath(ovalIn: rect)
  }

  private static func particleImage(
    size: CGSize, path: (CGRect) -> UIBezierPath
  ) -> UIImage {
    UIGraphicsImageRenderer(size: size).image { _ in
      UIColor.white.setFill()
      path(CGRect(origin: .zero, size: size)).fill()
    }
  }
}
