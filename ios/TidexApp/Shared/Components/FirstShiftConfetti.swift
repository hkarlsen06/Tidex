import SwiftUI
import UIKit

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

  // Waits for the Add screen's pop to get going, so the burst plays over the screen underneath.
  private static let startDelay: Duration = .milliseconds(300)
  private static let emissionDuration: Duration = .milliseconds(250)

  var body: some View {
    ConfettiEmitter(isEmitting: isEmitting)
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .task {
        do {
          try await Task.sleep(for: Self.startDelay)
          isEmitting = true
          try await Task.sleep(for: Self.emissionDuration)
          isEmitting = false
          try await Task.sleep(for: .seconds(ConfettiEmitterView.particleLifetime))
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
  static let particleLifetime: Double = 3

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
        // 10 cells for 0.25 s at 48 a second is about 120 pieces.
        cell.birthRate = 48
        cell.lifetime = Float(Self.particleLifetime)
        cell.velocity = 140
        cell.velocityRange = 80
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
