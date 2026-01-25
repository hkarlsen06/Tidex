import AudioToolbox
import AVFoundation

final class SoundManager {
    static let shared = SoundManager()
    private var players: [String: AVAudioPlayer] = [:]

    // System sound IDs (respects silent switch automatically)
    private let systemSounds: [String: SystemSoundID] = [
        "success": 1057,  // Subtle pop/ding
        "tap": 1104       // Short click
    ]

    private init() {
        // Ambient category respects the device silent switch
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
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
