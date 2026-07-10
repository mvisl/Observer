import CoreAudio
import Foundation

struct AudioOutputService {
    func currentOutputName() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard deviceStatus == noErr, deviceID != 0 else {
            return nil
        }

        address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let sizeStatus = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &size
        )
        guard sizeStatus == noErr, size > 0 else {
            return nil
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<CFString>.alignment
        )
        defer {
            buffer.deallocate()
        }

        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            buffer
        )
        guard nameStatus == noErr else {
            return nil
        }

        return buffer.load(as: CFString.self) as String
    }

    func looksLikeHeadphones(_ outputName: String?) -> Bool {
        guard let outputName else {
            return false
        }

        let normalized = outputName.lowercased()
        return [
            "airpods",
            "headphone",
            "headset",
            "buds",
            "beats",
            "bose",
            "sony",
            "wh-",
            "xm",
            "науш"
        ].contains { normalized.contains($0) }
    }
}
