import Foundation

struct WorkspaceTopology: Codable, CustomDebugStringConvertible {
    enum DeviceRole: String, Codable {
        case laptopPrimaryDevice = "laptop_primary_device"
        case laptopSecondaryDevice = "laptop_secondary_device"
        case desktopHost = "desktop_host"
        case unknown
    }

    enum DisplayRole: String, Codable {
        case mainWorkbench = "main_workbench"
        case productivity
        case reference
        case communication
        case unknown
    }

    enum RelativePosition: String, Codable {
        case left
        case center
        case right
        case above
        case below
        case unknown
    }

    struct Display: Codable {
        var role: DisplayRole
        var position: RelativePosition
        var isCameraMounted: Bool
    }

    var version: Int
    var deviceRole: DeviceRole
    var displays: [Display]

    static let defaultTwoDisplaySetup = WorkspaceTopology(
        version: 1,
        deviceRole: .laptopSecondaryDevice,
        displays: [
            Display(role: .mainWorkbench, position: .center, isCameraMounted: false),
            Display(role: .productivity, position: .right, isCameraMounted: true)
        ]
    )

    var eventPayload: [String: String] {
        [
            "device_role": deviceRole.rawValue,
            "display_count": "\(displays.count)",
            "camera_display_index": cameraDisplayIndex.map(String.init) ?? "unknown"
        ]
    }

    var markdownDescription: String {
        let displayLines = displays.enumerated().map { index, display in
            "- Display \(index): \(display.role.rawValue), \(display.position.rawValue), camera mounted: \(display.isCameraMounted)"
        }
        return ([
            "- Topology version: \(version)",
            "- Device role: \(deviceRole.rawValue)"
        ] + displayLines).joined(separator: "\n")
    }

    var debugDescription: String {
        markdownDescription
    }

    var cameraMountDescription: String {
        guard let cameraDisplayIndex else {
            return "Camera: unknown"
        }
        let display = displays[cameraDisplayIndex]
        return "Camera: display \(cameraDisplayIndex), \(display.position.rawValue)"
    }

    var cameraMountedDisplay: Display? {
        guard let cameraDisplayIndex else {
            return nil
        }
        return displays[cameraDisplayIndex]
    }

    private var cameraDisplayIndex: Int? {
        displays.firstIndex { $0.isCameraMounted }
    }
}
