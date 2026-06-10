import AVFoundation
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers number_separator required_deinit sorted_imports
import AudioToolbox

final class SoundManager {
  static let shared = SoundManager()
  private var players: [String: AVAudioPlayer] = [:]

  // System sound IDs (respects silent switch automatically)
  private let systemSounds: [String: SystemSoundID] = [
    "success": 1_057,  // Subtle pop/ding
    "tap": 1_104,  // Short click
  ]

  private init() {
    // Ambient category respects the device silent switch and mixes with other audio
    try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
  }

  func preload(_ name: String, extension ext: String = "wav") {
    guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return }
    players[name] = try? AVAudioPlayer(contentsOf: url)
    players[name]?.prepareToPlay()
  }

  func play(_ name: String) {
    // Try custom sound first
    if let player = players[name] {
      player.currentTime = 0
      player.play()
      return
    }

    // Fall back to system sound
    if let soundID = systemSounds[name] {
      AudioServicesPlaySystemSound(soundID)
    }
  }
}
