import SwiftUI

/// A single confetti particle with its properties
private struct ConfettiParticle: Identifiable {
  let id = UUID()
  let color: Color
  let size: CGSize
  let rotation: Double
  let spinSpeed: Double
  let horizontalOffset: CGFloat
  let delay: TimeInterval
}

/// Confetti celebration overlay view
/// Displays animated confetti particles when shifts are successfully added
struct ConfettiView: View {
  /// Whether the confetti animation is active
  let isActive: Bool

  /// Callback when animation completes
  var onComplete: (() -> Void)?

  // Brand colors matching web implementation
  private static let colors: [Color] = [
    Color(red: 0.231, green: 0.510, blue: 0.965),  // #3b82f6 Blue
    Color(red: 0.545, green: 0.361, blue: 0.965),  // #8b5cf6 Purple
    Color(red: 0.925, green: 0.282, blue: 0.600),  // #ec4899 Pink
  ]

  /// Number of particles (matching web: 80)
  private static let particleCount = 80

  @State private var particles: [ConfettiParticle] = []
  @State private var animationPhase: AnimationPhase = .idle

  fileprivate enum AnimationPhase {
    case idle
    case exploding
    case falling
    case complete
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        ForEach(particles) { particle in
          ConfettiParticleView(
            particle: particle,
            phase: animationPhase,
            containerSize: geometry.size
          )
        }
      }
    }
    .allowsHitTesting(false)
    .onChange(of: isActive) { _, newValue in
      if newValue {
        startAnimation()
      }
    }
    .onAppear {
      if isActive {
        startAnimation()
      }
    }
  }

  private func startAnimation() {
    // Generate particles
    particles = (0..<Self.particleCount).map { index in
      ConfettiParticle(
        // swiftlint:disable:next force_unwrapping
        color: Self.colors.randomElement()!,
        size: CGSize(
          width: CGFloat.random(in: 6...10),
          height: CGFloat.random(in: 8...14)
        ),
        rotation: Double.random(in: 0...360),
        spinSpeed: Double.random(in: 2...5),
        horizontalOffset: CGFloat.random(in: -150...150),
        delay: Double(index) * 0.005  // Stagger particles slightly
      )
    }

    // Start explosion phase
    withAnimation(.easeOut(duration: 0.1)) {
      animationPhase = .exploding
    }

    // Transition to falling phase
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      withAnimation(.easeIn(duration: 0.05)) {
        animationPhase = .falling
      }
    }

    // Complete animation after 2 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      animationPhase = .complete
      particles.removeAll()
      onComplete?()
    }
  }
}

/// Individual confetti particle view with animation
private struct ConfettiParticleView: View {
  let particle: ConfettiParticle
  let phase: ConfettiView.AnimationPhase
  let containerSize: CGSize

  /// Initial position at center-top of container
  private var startPosition: CGPoint {
    CGPoint(x: containerSize.width / 2, y: containerSize.height * 0.3)
  }

  /// Explosion position (outward from center)
  private var explosionPosition: CGPoint {
    let angle = Double.random(in: -Double.pi...0)  // Upper half
    let distance = CGFloat.random(in: 50...120)
    return CGPoint(
      x: startPosition.x + cos(angle) * distance + particle.horizontalOffset * 0.3,
      y: startPosition.y + sin(angle) * distance - 30  // Upward bias
    )
  }

  /// Final falling position (below screen)
  private var fallPosition: CGPoint {
    CGPoint(
      x: explosionPosition.x + particle.horizontalOffset * 0.7,
      y: containerSize.height + 100
    )
  }

  private var currentPosition: CGPoint {
    switch phase {
    case .idle:
      return startPosition
    case .exploding:
      return explosionPosition
    case .falling, .complete:
      return fallPosition
    }
  }

  private var currentOpacity: Double {
    switch phase {
    case .idle:
      return 0
    case .exploding:
      return 1
    case .falling:
      return 0.8
    case .complete:
      return 0
    }
  }

  private var currentScale: CGFloat {
    switch phase {
    case .idle:
      return 0.1
    case .exploding:
      return 1.2
    case .falling:
      return 1.0
    case .complete:
      return 0.5
    }
  }

  var body: some View {
    Rectangle()
      .fill(particle.color)
      .frame(width: particle.size.width, height: particle.size.height)
      .rotationEffect(.degrees(particle.rotation + rotationForPhase))
      .scaleEffect(currentScale)
      .opacity(currentOpacity)
      .position(currentPosition)
      .animation(animationForPhase, value: phase)
  }

  private var rotationForPhase: Double {
    switch phase {
    case .idle:
      return 0
    case .exploding:
      return particle.spinSpeed * 90
    case .falling, .complete:
      return particle.spinSpeed * 360
    }
  }

  private var animationForPhase: Animation? {
    switch phase {
    case .idle:
      return nil
    case .exploding:
      // Quick burst outward
      return .spring(response: 0.35, dampingFraction: 0.6)
        .delay(particle.delay)
    case .falling:
      // Slower fall with gravity
      return .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 1.8)
        .delay(particle.delay)
    case .complete:
      return .easeOut(duration: 0.2)
    }
  }
}

// MARK: - Animation Phase Extension

extension ConfettiView.AnimationPhase: Equatable {}

// MARK: - Preview

#Preview {
  struct PreviewWrapper: View {
    @State private var isActive = false

    var body: some View {
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        VStack {
          Spacer()

          Button("Celebrate!") {
            isActive = true
          }
          .padding()
          .background(Color.tidexBlue)
          .foregroundColor(.white)
          .cornerRadius(12)

          Spacer()
        }

        ConfettiView(isActive: isActive) {
          isActive = false
        }
      }
    }
  }

  return PreviewWrapper()
}
