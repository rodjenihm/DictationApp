import AppKit

enum SoundCue: CaseIterable {
    case recordingStarted
    case recordingStopped
    case sessionCancelled
    case attentionRequired

    var systemSoundName: NSSound.Name {
        switch self {
        case .recordingStarted:
            NSSound.Name("Tink")
        case .recordingStopped:
            NSSound.Name("Pop")
        case .sessionCancelled:
            NSSound.Name("Funk")
        case .attentionRequired:
            NSSound.Name("Basso")
        }
    }
}

@MainActor
final class SoundCuePlayer {
    private var activePlaybacks: [ObjectIdentifier: SoundPlayback] = [:]

    func play(_ cue: SoundCue, enabled: Bool) async {
        guard
            enabled,
            let sound = NSSound(named: cue.systemSoundName)
        else {
            return
        }

        await withCheckedContinuation { continuation in
            let playback = SoundPlayback(
                sound: sound
            ) { [weak self] identifier in
                self?.activePlaybacks[identifier] = nil
                continuation.resume()
            }
            activePlaybacks[playback.identifier] = playback

            if !playback.play() {
                activePlaybacks[playback.identifier] = nil
                continuation.resume()
            }
        }
    }
}

@MainActor
private final class SoundPlayback: NSObject, NSSoundDelegate {
    let identifier: ObjectIdentifier

    private let sound: NSSound
    private var completion: ((ObjectIdentifier) -> Void)?

    init(
        sound: NSSound,
        completion: @escaping (ObjectIdentifier) -> Void
    ) {
        self.sound = sound
        identifier = ObjectIdentifier(sound)
        self.completion = completion
        super.init()
        sound.delegate = self
    }

    func play() -> Bool {
        sound.play()
    }

    func sound(
        _ sound: NSSound,
        didFinishPlaying flag: Bool
    ) {
        finish()
    }

    private func finish() {
        let completion = completion
        self.completion = nil
        completion?(identifier)
    }
}
