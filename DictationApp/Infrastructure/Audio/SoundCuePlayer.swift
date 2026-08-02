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

    var maximumPlaybackDuration: Duration? {
        switch self {
        case .recordingStarted:
            .milliseconds(120)
        case
            .recordingStopped,
            .sessionCancelled,
            .attentionRequired:
            nil
        }
    }
}

@MainActor
final class SoundCuePlayer {
    private var activePlaybacks: [ObjectIdentifier: SoundPlayback] = [:]

    func play(_ cue: SoundCue, enabled: Bool) async {
        if case .recordingStarted = cue {
            stopAll()
        }
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

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await playImmediately(cue)
        }
        return task
    }

    private func stopAll() {
        let playbacks = Array(activePlaybacks.values)
        activePlaybacks.removeAll()
        playbacks.forEach { $0.stop() }
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

            if !playback.play(
                maximumDuration: cue.maximumPlaybackDuration
            ) {
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
    private var stopTask: Task<Void, Never>?

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

    func play(maximumDuration: Duration?) -> Bool {
        guard sound.play() else {
            return false
        }

        if let maximumDuration {
            stopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: maximumDuration)
                guard !Task.isCancelled else {
                    return
                }
                self?.stop()
            }
        }
        return true
    }

    func stop() {
        sound.stop()
        finish()
    }

    func sound(
        _ sound: NSSound,
        didFinishPlaying flag: Bool
    ) {
        finish()
    }

    private func finish() {
        stopTask?.cancel()
        stopTask = nil
        let completion = completion
        self.completion = nil
        completion?(identifier)
    }
}
