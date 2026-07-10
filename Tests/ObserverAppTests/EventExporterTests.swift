import Foundation
import Testing
@testable import ObserverApp

struct EventExporterTests {
    @Test func exportsJSONL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-export-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let event = ObserverEvent(type: .userNote, payload: ["note": "hello"], workspaceTopologyVersion: 1)
        let url = try EventExporter().exportJSONL(events: [event], directory: directory)
        let contents = try String(contentsOf: url, encoding: .utf8)

        #expect(contents.contains("userNote"))
        #expect(contents.contains("hello"))
    }
}
