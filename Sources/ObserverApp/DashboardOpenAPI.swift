import Foundation

enum DashboardOpenAPI {
    static func jsonData() -> Data {
        (try? JSONSerialization.data(withJSONObject: document(), options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    private static func document() -> [String: Any] {
        [
            "openapi": "3.1.0",
            "info": [
                "title": "Observer Local Core API",
                "version": "v0"
            ],
            "servers": [
                ["url": "http://127.0.0.1:43127"]
            ],
            "paths": [
                "/api/v1/health": ["get": ["summary": "Core health"]],
                "/api/v1/meta": ["get": ["summary": "API metadata"]],
                "/api/v1/session": ["get": ["summary": "Current dashboard session"]],
                "/api/v1/auth/pair": ["post": ["summary": "Pair a device with a short-lived code"]],
                "/api/v1/auth/logout": ["post": ["summary": "Logout dashboard device"]],
                "/api/v1/dashboard/day": ["get": ["summary": "DayDashboardSnapshot"]],
                "/api/v1/timeline": ["get": ["summary": "Timeline segments"]],
                "/api/v1/threads": ["get": ["summary": "Activity threads"]],
                "/api/v1/review": ["get": ["summary": "Review queue"]],
                "/api/v1/sensors": ["get": ["summary": "Sensor health"]],
                "/api/v1/causal/hypotheses": ["get": ["summary": "Causal hypotheses"]],
                "/api/v1/readiness": ["get": ["summary": "Readiness gate"]],
                "/api/v1/reports/daily/markdown": ["get": ["summary": "Daily report as Markdown"]],
                "/api/v1/reports/daily/json": ["get": ["summary": "Daily report diagnostics JSON"]],
                "/api/v1/corrections/same-context": ["post": ["summary": "Mark items as same context"]],
                "/api/v1/corrections/different-context": ["post": ["summary": "Mark items as different context"]],
                "/api/v1/corrections/assign": ["post": ["summary": "Assign item to existing thread"]],
                "/api/v1/corrections/unassign": ["post": ["summary": "Leave item unassigned"]],
                "/api/v1/corrections/{id}/undo": ["post": ["summary": "Undo correction"]],
                "/api/v1/admin/rebuild": ["post": ["summary": "Diagnostics rebuild request"]]
            ]
        ]
    }
}
