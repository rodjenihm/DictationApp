@preconcurrency import CoreAudio
import Foundation
import Observation

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let deviceID: AudioObjectID
    let uid: String
    let name: String
    let isBuiltIn: Bool

    var id: String { uid }
}

struct AudioInputCaptureCandidate: Equatable, Sendable {
    let deviceID: AudioObjectID
    let name: String
    let isFallback: Bool
}

@MainActor
@Observable
final class CoreAudioInputDeviceService {
    private(set) var devices: [AudioInputDevice] = []
    private(set) var defaultInputDeviceID: AudioObjectID?

    @ObservationIgnored
    private var hardwareObservation: CoreAudioPropertyObservation?

    init() {
        refresh()
        hardwareObservation = CoreAudioPropertyObservation(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            addresses: [
                CoreAudioHardware.deviceListAddress,
                CoreAudioHardware.defaultInputAddress,
            ]
        ) { [weak self] in
            self?.refresh()
        }
    }

    var hasBuiltInInput: Bool {
        devices.contains(where: \.isBuiltIn)
    }

    func refresh() {
        defaultInputDeviceID = CoreAudioHardware.defaultInputDeviceID()
        devices = CoreAudioHardware.inputDevices().sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn
            }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.uid < rhs.uid
            }
            return comparison == .orderedAscending
        }
    }

    func preference(
        for device: AudioInputDevice
    ) -> AudioInputPreference {
        device.isBuiltIn
            ? .builtIn
            : .device(uid: device.uid, lastKnownName: device.name)
    }

    func preference(
        for identity: AudioInputPreference.Identity,
        retainingMetadataFrom currentPreference: AudioInputPreference
    ) -> AudioInputPreference {
        switch identity {
        case .systemDefault:
            return .systemDefault
        case .builtIn:
            return .builtIn
        case .device(let uid):
            if let device = devices.first(where: { $0.uid == uid }) {
                return preference(for: device)
            }
            if case .device(uid, let lastKnownName) = currentPreference {
                return .device(
                    uid: uid,
                    lastKnownName: lastKnownName
                )
            }
            return .device(uid: uid, lastKnownName: "Microphone")
        }
    }

    func refreshingPresentationMetadata(
        for preference: AudioInputPreference
    ) -> AudioInputPreference {
        guard
            case .device(let uid, _) = preference,
            let device = devices.first(where: { $0.uid == uid })
        else {
            return preference
        }
        return .device(uid: uid, lastKnownName: device.name)
    }

    func displayName(
        for preference: AudioInputPreference
    ) -> String {
        switch preference {
        case .systemDefault:
            "System Default"
        case .builtIn:
            devices.first(where: \.isBuiltIn)?.name
                ?? "Built-in Microphone"
        case .device(let uid, let lastKnownName):
            devices.first(where: { $0.uid == uid })?.name
                ?? lastKnownName
        }
    }

    func isAvailable(
        _ preference: AudioInputPreference
    ) -> Bool {
        resolvedDevice(for: preference) != nil
    }

    func captureCandidates(
        for preference: AudioInputPreference
    ) -> [AudioInputCaptureCandidate] {
        refresh()

        guard preference != .systemDefault else {
            guard let device = defaultInputDevice() else {
                return []
            }
            return [candidate(for: device, isFallback: false)]
        }

        var candidates: [AudioInputCaptureCandidate] = []
        if let preferred = resolvedDevice(for: preference) {
            candidates.append(
                candidate(for: preferred, isFallback: false)
            )
        }
        if
            let systemDefault = defaultInputDevice(),
            !candidates.contains(
                where: { $0.deviceID == systemDefault.deviceID }
            )
        {
            candidates.append(
                candidate(for: systemDefault, isFallback: true)
            )
        }
        return candidates
    }

    private func resolvedDevice(
        for preference: AudioInputPreference
    ) -> AudioInputDevice? {
        switch preference {
        case .systemDefault:
            defaultInputDevice()
        case .builtIn:
            devices.first(where: \.isBuiltIn)
        case .device(let uid, _):
            devices.first(where: { $0.uid == uid })
        }
    }

    private func defaultInputDevice() -> AudioInputDevice? {
        guard let defaultInputDeviceID else {
            return nil
        }
        return devices.first {
            $0.deviceID == defaultInputDeviceID
        }
    }

    private func candidate(
        for device: AudioInputDevice,
        isFallback: Bool
    ) -> AudioInputCaptureCandidate {
        AudioInputCaptureCandidate(
            deviceID: device.deviceID,
            name: device.name,
            isFallback: isFallback
        )
    }
}

nonisolated final class CoreAudioPropertyObservation:
    @unchecked Sendable
{
    private let objectID: AudioObjectID
    private let addresses: [AudioObjectPropertyAddress]
    private let listener: AudioObjectPropertyListenerBlock

    init(
        objectID: AudioObjectID,
        addresses: [AudioObjectPropertyAddress],
        handler: @escaping @MainActor () -> Void
    ) {
        self.objectID = objectID
        self.addresses = addresses
        listener = { _, _ in
            Task { @MainActor in
                handler()
            }
        }
        for var address in addresses {
            AudioObjectAddPropertyListenerBlock(
                objectID,
                &address,
                .main,
                listener
            )
        }
    }

    deinit {
        for var address in addresses {
            AudioObjectRemovePropertyListenerBlock(
                objectID,
                &address,
                .main,
                listener
            )
        }
    }
}

nonisolated enum CoreAudioHardware {
    static let deviceListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    static let deviceAliveAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static func inputDevices() -> [AudioInputDevice] {
        readDeviceIDs().compactMap { deviceID in
            guard
                isAlive(deviceID),
                inputChannelCount(deviceID) > 0,
                let uid = stringProperty(
                    deviceID,
                    selector: kAudioDevicePropertyDeviceUID
                ),
                let name = stringProperty(
                    deviceID,
                    selector: kAudioObjectPropertyName
                )
            else {
                return nil
            }
            return AudioInputDevice(
                deviceID: deviceID,
                uid: uid,
                name: name,
                isBuiltIn:
                    transportType(deviceID)
                        == kAudioDeviceTransportTypeBuiltIn
            )
        }
    }

    static func defaultInputDeviceID() -> AudioObjectID? {
        var address = defaultInputAddress
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &deviceID
            ) == noErr,
            deviceID != kAudioObjectUnknown
        else {
            return nil
        }
        return deviceID
    }

    static func isAlive(_ deviceID: AudioObjectID) -> Bool {
        uint32Property(
            deviceID,
            selector: kAudioDevicePropertyDeviceIsAlive
        ) != 0
    }

    private static func readDeviceIDs() -> [AudioObjectID] {
        var address = deviceListAddress
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size
            ) == noErr,
            size >= MemoryLayout<AudioObjectID>.size
        else {
            return []
        }
        var values = Array(
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        let status = values.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                buffer.baseAddress!
            )
        }
        return status == noErr ? values : []
    }

    private static func inputChannelCount(
        _ deviceID: AudioObjectID
    ) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                deviceID,
                &address,
                0,
                nil,
                &size
            ) == noErr,
            size >= MemoryLayout<AudioBufferList>.size
        else {
            return 0
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                raw
            ) == noErr
        else {
            return 0
        }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }

    private static func stringProperty(
        _ deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &value
            ) == noErr
        else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }

    private static func transportType(
        _ deviceID: AudioObjectID
    ) -> UInt32 {
        uint32Property(
            deviceID,
            selector: kAudioDevicePropertyTransportType
        )
    }

    private static func uint32Property(
        _ deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &value
            ) == noErr
        else {
            return 0
        }
        return value
    }
}
