import Foundation
import Network

/// Tiny HTTP/JSON-RPC server that exposes Claude Sessions to MCP clients.
///
/// Why HTTP over stdio: the GUI process owns the in-memory state any
/// useful tool would mutate (open session id, sidebar selection, etc.),
/// so the server lives inside the running app. See cycle 33 notes in
/// STAGE_2_ROADMAP.md for the full reasoning.
///
/// Wire shape (single endpoint):
///   POST /mcp   — body is a JSON-RPC 2.0 request, response is the reply.
///                 No SSE; tools are point-in-time.
///
/// Security: bound to 127.0.0.1 only. No auth; loopback is the gate.
final class MCPServer {

    // MARK: - State

    private(set) var port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "claude-sessions.mcp.server", qos: .userInitiated)
    private var registry: [String: ToolHandler] = [:]
    var serverName: String = "claude-sessions"
    var serverVersion: String = "0.1.0"

    // MARK: - Tool registration

    typealias ToolHandler = (_ arguments: [String: Any]) async throws -> [String: Any]

    struct ToolDescriptor {
        let name: String
        let description: String
        /// JSON Schema for the arguments object. May be `[:]` for no args.
        let inputSchema: [String: Any]
        let handler: ToolHandler
    }

    private var tools: [ToolDescriptor] = []

    func register(_ tool: ToolDescriptor) {
        tools.append(tool)
        registry[tool.name] = tool.handler
    }

    /// Convenience used by Phase 3 / T03–T06 cycles to drop in a batch
    /// of tools at once.
    func register(_ batch: [ToolDescriptor]) {
        for t in batch { register(t) }
    }

    // MARK: - Lifecycle

    init(port: UInt16 = 7531) {
        self.port = port
    }

    /// Start the listener. Pass `port` to override the configured one.
    /// Falls back to an ephemeral port if the chosen one is in use, and
    /// updates `self.port` to the bound value.
    func start(port: UInt16? = nil) throws {
        guard listener == nil else { return }
        if let port { self.port = port }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Bind to loopback only.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: self.port) ?? .any
        )

        let l = try NWListener(using: parameters)
        l.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let assigned = l.port?.rawValue { self?.port = assigned }
            case .failed(let err):
                NSLog("[MCP] listener failed: \(err)")
            default:
                break
            }
        }
        l.start(queue: queue)
        self.listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    /// Read until we have a complete HTTP request (headers + body bytes).
    private func receiveRequest(on conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error = error {
                NSLog("[MCP] receive error: \(error)")
                conn.cancel()
                return
            }
            var buf = accumulated
            if let data = data { buf.append(data) }

            if let parsed = self.tryParseHTTPRequest(buf) {
                self.handleRequest(parsed, on: conn)
                return
            }
            if isComplete {
                conn.cancel()
                return
            }
            self.receiveRequest(on: conn, accumulated: buf)
        }
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    /// Parse a minimal HTTP/1.1 request. Returns nil if we don't have the
    /// full body yet (caller keeps reading).
    private func tryParseHTTPRequest(_ data: Data) -> HTTPRequest? {
        // Find the end of headers
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<separator.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: true).map(String.init)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let path = parts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let name = String(line[..<colon]).lowercased()
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
        }

        let bodyStart = separator.upperBound
        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        let available = data.count - bodyStart
        if available < contentLength { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - Routing

    private func handleRequest(_ req: HTTPRequest, on conn: NWConnection) {
        // Only POST /mcp
        guard req.method.uppercased() == "POST", req.path == "/mcp" else {
            sendHTTP(404, body: Data("not found".utf8), on: conn)
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any] else {
            sendJSONRPCError(id: nil, code: -32700, message: "parse error", on: conn)
            return
        }
        let id = json["id"]
        guard let method = json["method"] as? String else {
            sendJSONRPCError(id: id, code: -32600, message: "invalid request: no method", on: conn)
            return
        }
        let params = json["params"] as? [String: Any] ?? [:]

        Task { [weak self] in
            await self?.dispatch(method: method, params: params, id: id, conn: conn)
        }
    }

    private func dispatch(method: String, params: [String: Any], id: Any?, conn: NWConnection) async {
        switch method {
        case "initialize":
            let result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": [
                    "name": serverName,
                    "version": serverVersion
                ]
            ]
            sendJSONRPCResult(id: id, result: result, on: conn)

        case "tools/list":
            let listed = tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema
                ]
            }
            sendJSONRPCResult(id: id, result: ["tools": listed], on: conn)

        case "tools/call":
            let name = (params["name"] as? String) ?? ""
            let args = (params["arguments"] as? [String: Any]) ?? [:]
            guard let handler = registry[name] else {
                sendJSONRPCError(id: id, code: -32601,
                                 message: "unknown tool: \(name)", on: conn)
                return
            }
            do {
                let value = try await handler(args)
                let textJSON = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                let result: [String: Any] = [
                    "content": [
                        ["type": "text", "text": textJSON]
                    ]
                ]
                sendJSONRPCResult(id: id, result: result, on: conn)
            } catch {
                sendJSONRPCError(id: id, code: -32000,
                                 message: "tool error: \(error.localizedDescription)",
                                 on: conn)
            }

        default:
            sendJSONRPCError(id: id, code: -32601,
                             message: "method not found: \(method)", on: conn)
        }
    }

    // MARK: - Reply helpers

    private func sendJSONRPCResult(id: Any?, result: [String: Any], on conn: NWConnection) {
        var reply: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id = id { reply["id"] = id }
        sendJSON(reply, on: conn)
    }

    private func sendJSONRPCError(id: Any?, code: Int, message: String, on conn: NWConnection) {
        var reply: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message]
        ]
        if let id = id { reply["id"] = id }
        sendJSON(reply, on: conn)
    }

    private func sendJSON(_ obj: [String: Any], on conn: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
        sendHTTP(200, body: body, contentType: "application/json", on: conn)
    }

    private func sendHTTP(_ status: Int, body: Data, contentType: String = "text/plain", on conn: NWConnection) {
        let statusText = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Error")
        let headers = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var data = Data(headers.utf8)
        data.append(body)
        conn.send(content: data, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
