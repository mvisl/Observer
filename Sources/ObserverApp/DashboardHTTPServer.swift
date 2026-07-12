import Foundation
import Network

final class DashboardHTTPServer: @unchecked Sendable {
    private let environment: AppEnvironment
    private let queue = DispatchQueue(label: "observer.dashboard.http")
    private let encoder = JSONEncoder.observerEncoder
    private var listener: NWListener?
    private var sessions: [String: Date] = [:]
    private var pairingCode: String
    private var pairingExpiresAt: Date

    init(environment: AppEnvironment) {
        self.environment = environment
        self.pairingCode = DashboardHTTPServer.generatePairingCode()
        self.pairingExpiresAt = Date().addingTimeInterval(300)
        ensureMasterSecret()
    }

    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(environment.settings.dashboard.port)")!
    }

    func currentPairingCode() -> String {
        queue.sync {
            if Date() >= pairingExpiresAt {
                pairingCode = Self.generatePairingCode()
                pairingExpiresAt = Date().addingTimeInterval(300)
            }
            return pairingCode
        }
    }

    func start() throws {
        guard listener == nil else { return }
        let port = NWEndpoint.Port(rawValue: UInt16(environment.settings.dashboard.port)) ?? 43127
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
        print("Observer Dashboard API listening on \(baseURL.absoluteString)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        sessions.removeAll()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256_000) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = HTTPRequest(data: data ?? Data())
            let response = self.route(request)
            connection.send(content: response.data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func route(_ request: HTTPRequest) -> HTTPResponse {
        guard request.hostIsAllowed else {
            return .json(["error": "wrong_host"], status: 403)
        }
        if request.method != "GET", !request.originIsAllowed {
            return .json(["error": "wrong_origin"], status: 403)
        }

        let path = request.path
        if path == "/api/openapi.json" {
            return .data(DashboardOpenAPI.jsonData(), contentType: "application/json")
        }
        if path == "/api/v1/health" {
            return .json([
                "status": "ok",
                "schemaVersion": DashboardContract.schemaVersion,
                "dashboardEnabled": environment.settings.dashboard.enabled,
                "remoteAccessMode": environment.settings.dashboard.remoteAccessMode
            ])
        }
        if path == "/api/v1/meta" {
            return .json([
                "apiVersion": DashboardContract.apiVersion,
                "schemaVersion": DashboardContract.schemaVersion,
                "pipelineVersion": ObserverPipeline.version,
                "tailscaleFunnelAllowed": false,
                "browserLLMAllowed": false,
                "externalSendingEndpoints": false
            ])
        }
        if path == "/api/v1/auth/pair", request.method == "POST" {
            return pair(request)
        }

        guard let session = request.cookie("observer_session"), sessionIsValid(session) else {
            if path == "/api/v1/session" {
                return .json(["authenticated": false], status: 401)
            }
            if path.hasPrefix("/api/") {
                return .json(["error": "auth_required"], status: 401)
            }
            return serveStatic(path: path)
        }

        if path == "/api/v1/session" {
            return .json(["authenticated": true, "expiresAt": isoString(sessions[session] ?? Date())])
        }
        if path == "/api/v1/auth/logout", request.method == "POST" {
            sessions.removeValue(forKey: session)
            return .json(["ok": true], extraHeaders: ["Set-Cookie": "observer_session=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict"])
        }
        if path == "/api/v1/dashboard/day" {
            return jsonResponse(snapshot(for: request))
        }
        if path == "/api/v1/timeline" {
            return jsonResponse(snapshot(for: request).timelineSegments)
        }
        if path == "/api/v1/threads" {
            return jsonResponse(snapshot(for: request).threadSummaries)
        }
        if path == "/api/v1/review" {
            return jsonResponse(snapshot(for: request).reviewSummary)
        }
        if path == "/api/v1/sensors" {
            return jsonResponse(snapshot(for: request).sensorSummary)
        }
        if path == "/api/v1/causal/hypotheses" {
            return jsonResponse(snapshot(for: request).causalSummary.hypotheses)
        }
        if path == "/api/v1/readiness" {
            return jsonResponse(snapshot(for: request).readinessSummary)
        }
        if path == "/api/v1/reports/daily/markdown" {
            let report = dailyReport(for: request)
            return .data(Data(report.markdown.utf8), contentType: "text/markdown; charset=utf-8")
        }
        if path == "/api/v1/reports/daily/json" {
            return .json(dailyReport(for: request).diagnostics)
        }
        if path.hasPrefix("/api/v1/corrections/") || path.hasSuffix("/rename") {
            return handleCorrection(path: path, request: request)
        }
        if path == "/api/v1/admin/rebuild", request.method == "POST" {
            return .json([
                "jobId": UUID().uuidString,
                "status": "accepted",
                "mode": "diagnostics",
                "note": "v0 records the rebuild request; derived models are rebuilt on read"
            ])
        }
        if path.hasPrefix("/api/") {
            return .json(["error": "not_found"], status: 404)
        }
        return serveStatic(path: path)
    }

    private func pair(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = request.jsonBody,
              let code = body["code"] as? String,
              code == currentPairingCode(),
              Date() < pairingExpiresAt
        else {
            return .json(["error": "invalid_or_expired_pairing_code"], status: 401)
        }
        let token = UUID().uuidString + UUID().uuidString
        sessions[token] = Date().addingTimeInterval(environment.settings.dashboard.sessionTTLSeconds)
        pairingCode = Self.generatePairingCode()
        pairingExpiresAt = Date().addingTimeInterval(300)
        appendAuditEvent(type: "pair", payload: body)
        return .json(
            ["authenticated": true, "expiresAt": isoString(sessions[token] ?? Date())],
            extraHeaders: ["Set-Cookie": "observer_session=\(token); Path=/; Max-Age=\(Int(environment.settings.dashboard.sessionTTLSeconds)); HttpOnly; SameSite=Strict"]
        )
    }

    private func sessionIsValid(_ token: String) -> Bool {
        guard let expires = sessions[token], expires > Date() else {
            sessions.removeValue(forKey: token)
            return false
        }
        return true
    }

    private func snapshot(for request: HTTPRequest) -> DayDashboardSnapshot {
        let events = (try? environment.eventStore.allEvents()) ?? []
        let timezone = TimeZone(identifier: request.query["timezone"] ?? TimeZone.current.identifier) ?? .current
        let date = request.query["date"].flatMap { localDate($0, timezone: timezone) } ?? Date()
        return DashboardReadModelBuilder().buildDaySnapshot(
            events: events,
            date: date,
            timezone: timezone,
            diagnostics: request.query["diagnostics"] == "true",
            settings: environment.settings
        )
    }

    private func dailyReport(for request: HTTPRequest) -> (markdown: String, diagnostics: [String: String]) {
        let events = (try? environment.eventStore.allEvents()) ?? []
        let timezone = TimeZone(identifier: request.query["timezone"] ?? TimeZone.current.identifier) ?? .current
        let date = request.query["date"].flatMap { localDate($0, timezone: timezone) } ?? Date()
        var calendar = Calendar.current
        calendar.timeZone = timezone
        return DailyActivityReportBuilder().build(events: events, day: date)
    }

    private func handleCorrection(path: String, request: HTTPRequest) -> HTTPResponse {
        guard request.method == "POST" else {
            return .json(["error": "method_not_allowed"], status: 405)
        }
        guard let body = request.jsonBody,
              let commandId = body["commandId"] as? String,
              commandId.isEmpty == false
        else {
            return .json(["error": "missing_command_id"], status: 400)
        }
        let kind = path.components(separatedBy: "/").last ?? "correction"
        appendAuditEvent(type: kind, payload: body)
        let response = DashboardCorrectionResponse(
            accepted: true,
            commandId: commandId,
            dataRevision: "\(Date().timeIntervalSince1970)",
            message: "Correction recorded locally; derived read models rebuild on next snapshot"
        )
        return jsonResponse(response)
    }

    private func appendAuditEvent(type: String, payload: [String: Any]) {
        var eventPayload: [String: String] = [
            "command_type": type,
            "dashboard_api": "true",
            "pipeline_version": ObserverPipeline.version
        ]
        for (key, value) in payload {
            eventPayload[key] = String(describing: value)
        }
        try? environment.eventStore.append(
            ObserverEvent(
                type: .contextLinkUserLabel,
                source: "dashboard_api",
                confidence: 1,
                payload: eventPayload,
                workspaceTopologyVersion: environment.topology.version
            )
        )
    }

    private func jsonResponse<T: Encodable>(_ value: T) -> HTTPResponse {
        do {
            return .data(try encoder.encode(value), contentType: "application/json")
        } catch {
            return .json(["error": "encoding_failed", "message": String(describing: error)], status: 500)
        }
    }

    private func serveStatic(path: String) -> HTTPResponse {
        let root = staticRoot()
        let relative = path == "/" ? "index.html" : String(path.dropFirst())
        let safeRelative = relative.contains("..") ? "index.html" : relative
        let file = root.appendingPathComponent(safeRelative)
        if FileManager.default.fileExists(atPath: file.path),
           let data = try? Data(contentsOf: file) {
            return .data(data, contentType: contentType(for: file.path), cacheControl: file.path.contains("/assets/") ? "public, max-age=31536000, immutable" : "no-store")
        }
        let index = root.appendingPathComponent("index.html")
        if let data = try? Data(contentsOf: index) {
            return .data(data, contentType: "text/html; charset=utf-8")
        }
        return .data(Data(minimalHTML.utf8), contentType: "text/html; charset=utf-8")
    }

    private func staticRoot() -> URL {
        let bundleRoot = Bundle.main.resourceURL?.appendingPathComponent("observer-web")
        if let bundleRoot, FileManager.default.fileExists(atPath: bundleRoot.appendingPathComponent("index.html").path) {
            return bundleRoot
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("apps/observer-web/dist", isDirectory: true)
    }

    private func contentType(for path: String) -> String {
        if path.hasSuffix(".js") { return "text/javascript; charset=utf-8" }
        if path.hasSuffix(".css") { return "text/css; charset=utf-8" }
        if path.hasSuffix(".svg") { return "image/svg+xml" }
        if path.hasSuffix(".json") { return "application/json" }
        return "application/octet-stream"
    }

    private func ensureMasterSecret() {
        guard !KeychainStore.dashboardMasterSecret.hasPassword() else { return }
        try? KeychainStore.dashboardMasterSecret.setPassword(UUID().uuidString + UUID().uuidString)
    }

    private static func generatePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}

private struct HTTPRequest {
    let method: String
    let target: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    init(data: Data) {
        let marker = Data("\r\n\r\n".utf8)
        let parts = data.split(separator: marker, maxSplits: 1, omittingEmptySubsequences: false)
        let headerText = String(data: Data(parts.first ?? Data.SubSequence()), encoding: .utf8) ?? ""
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        method = requestLine.first ?? "GET"
        target = requestLine.dropFirst().first ?? "/"
        let components = URLComponents(string: target) ?? URLComponents()
        path = components.path.isEmpty ? "/" : components.path
        var queryItems: [String: String] = [:]
        for item in components.queryItems ?? [] {
            queryItems[item.name] = item.value ?? ""
        }
        query = queryItems
        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = line[..<idx].lowercased()
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            parsedHeaders[String(key)] = value
        }
        headers = parsedHeaders
        body = parts.count > 1 ? Data(parts[1]) : Data()
    }

    var jsonBody: [String: Any]? {
        guard !body.isEmpty else { return [:] }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    var hostIsAllowed: Bool {
        guard let host = headers["host"] else { return true }
        return host.hasPrefix("127.0.0.1") || host.hasPrefix("localhost") || host.contains(".ts.net")
    }

    var originIsAllowed: Bool {
        guard let origin = headers["origin"] else { return true }
        return origin.hasPrefix("http://127.0.0.1") || origin.hasPrefix("http://localhost") || origin.contains(".ts.net")
    }

    func cookie(_ name: String) -> String? {
        guard let cookie = headers["cookie"] else { return nil }
        for part in cookie.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pieces.count == 2, pieces[0] == name {
                return pieces[1]
            }
        }
        return nil
    }
}

private struct HTTPResponse {
    let data: Data

    static func json(_ object: Any, status: Int = 200, extraHeaders: [String: String] = [:]) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return .data(data, status: status, contentType: "application/json", extraHeaders: extraHeaders)
    }

    static func data(
        _ body: Data,
        status: Int = 200,
        contentType: String,
        cacheControl: String = "no-store",
        extraHeaders: [String: String] = [:]
    ) -> HTTPResponse {
        var headers = [
            "HTTP/1.1 \(status) \(reason(status))",
            "Content-Length: \(body.count)",
            "Content-Type: \(contentType)",
            "Connection: close",
            "Cache-Control: \(cacheControl)",
            "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'",
            "X-Content-Type-Options: nosniff",
            "Referrer-Policy: no-referrer",
            "Permissions-Policy: camera=(), microphone=(), geolocation=()"
        ]
        for (key, value) in extraHeaders {
            headers.append("\(key): \(value)")
        }
        let head = headers.joined(separator: "\r\n") + "\r\n\r\n"
        return HTTPResponse(data: Data(head.utf8) + body)
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Error"
        }
    }
}

private func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func localDate(_ value: String, timezone: TimeZone) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timezone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}

private let minimalHTML = """
<!doctype html>
<html>
<head><meta charset="utf-8"><title>Observer Dashboard</title></head>
<body><h1>Observer Dashboard</h1><p>Build the web app with <code>make web-build</code>.</p></body>
</html>
"""
