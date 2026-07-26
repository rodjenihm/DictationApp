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
    private var playbackTail:
        (identifier: UUID, task: Task<Void, Never>)?

    func play(_ cue: SoundCue, enabled: Bool) async {
        await enqueue(cue, enabled: enabled).value
    }

    @discardableResult
    func enqueue(
        _ cue: SoundCue,
        enabled: Bool
    ) -> Task<Void, Never> {
        guard
            enabled,
            NSSound(named: cue.systemSoundName) != nil
        else {
            return Task {}
        }

        let identifier = UUID()
        let previousTask = playbackTail?.task
        let task = Task { @MainActor [weak self] in
            await previousTask?.value
            await self?.playImmediately(cue)
        }
        playbackTail = (identifier, task)

        Task { @MainActor [weak self] in
            await task.value
            guard self?.playbackTail?.identifier == identifier else {
                return
            }
            self?.playbackTail = nil
        }

        return task
    }

    private func playImmediately(_ cue: SoundCue) async {
        guard let sound = NSSound(named: cue.systemSoundName) else {
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
