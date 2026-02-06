import AVFoundation
import UIKit

/// Haptic feedback types for different interactions
enum HapticType {
  case success  // Successful operations (form submit, save)
  case error  // Errors and failures
  case warning  // Destructive action confirmations
  case light  // Subtle feedback (toggles, navigation)
  case medium  // Moderate feedback
  case heavy  // Strong feedback
  case selection  // Selection changes
  case hold  // Firm, pronounced feedback (like pressing down)
  case release  // Soft, gentle feedback (like releasing a press)
}

/// Sound types for audio feedback
enum SoundType: String {
  case shiftCreated = "tidex_success"
  case shiftDeleted = "tidex_shift_deleted"
  case subscriptionSuccess = "tidex_subscription_success"
}

/// Centralized haptic feedback manager
/// Provides consistent haptic feedback across the app
enum Haptics {
  /// Audio players for each sound type
  private static var soundPlayers: [SoundType: AVAudioPlayer] = [:]

  /// Pre-prepared generator for rapid streaming haptics (e.g., token streaming)
  private static let streamingGenerator = UIImpactFeedbackGenerator(style: .light)

  /// Volume level for sound effects (0.0 to 1.0)
  /// Adjust this to control how loud the sounds play
  private static let soundVolume: Float = 0.3

  /// Preload all sounds (call at app startup)
  static func prepareSounds() {
    // Set ambient category before creating any AVAudioPlayer instances.
    // Without this, iOS uses the default .soloAmbient which pauses external audio (Spotify, Apple Music, etc.)
    try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])

    for soundType in [SoundType.shiftCreated, .shiftDeleted, .subscriptionSuccess] {
      prepareSound(soundType)
    }
  }

  /// Prepare the streaming haptic generator for rapid haptics (call before streaming starts)
  static func prepareStreamingHaptics() {
    streamingGenerator.prepare()
  }

  /// Play a light haptic for streaming tokens (uses pre-prepared generator for performance)
  static func playStreamingToken() {
    streamingGenerator.impactOccurred()
  }

  /// Preload a specific sound
  private static func prepareSound(_ type: SoundType) {
    guard let url = Bundle.main.url(forResource: type.rawValue, withExtension: "caf") else {
      return
    }
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.volume = soundVolume
      player.prepareToPlay()
      soundPlayers[type] = player
    } catch {
      // Sound will not play if initialization fails
    }
  }

  /// Play haptic feedback of the specified type
  static func play(_ type: HapticType) {
    switch type {
    case .success:
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .error:
      UINotificationFeedbackGenerator().notificationOccurred(.error)
    case .warning:
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
    case .light:
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .medium:
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .heavy:
      UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    case .selection:
      UISelectionFeedbackGenerator().selectionChanged()
    case .hold:
      UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
    case .release:
      UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }
  }

  /// Play a sound effect
  private static func playSound(_ type: SoundType) {
    // Re-initialize player if needed
    if soundPlayers[type] == nil {
      prepareSound(type)
    }

    // Ensure volume is set (in case player was re-created)
    soundPlayers[type]?.volume = soundVolume

    // Reset to beginning and play
    soundPlayers[type]?.currentTime = 0
    soundPlayers[type]?.play()
  }

  // MARK: - Combined Haptic + Sound Methods

  /// Play shift creation success feedback (haptic + sound)
  static func playShiftCreationSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    playSound(.shiftCreated)
  }

  /// Play shift deletion feedback (haptic + sound)
  static func playShiftDeleted() {
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    playSound(.shiftDeleted)
  }

  /// Play subscription success feedback (haptic + sound)
  static func playSubscriptionSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    playSound(.subscriptionSuccess)
  }
}
