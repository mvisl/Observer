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

        var name: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &name
        )
        guard nameStatus == noErr else {
            return nil
        }

        return name as String
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
