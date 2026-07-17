// MCP/Server.swift - a hand-rolled stdio MCP server (JSON-RPC 2.0), the second
// front-end over the same Core functions. Transport is newline-delimited JSON
// (one object per line, no Content-Length headers): requests are decoded with
// JSONSerialization (they are heterogeneous), responses are built as plain
// dictionaries so a request id echoes back with its original type. The server is
// read-only by design (investigation section 10) and confines every path to the
// configured --root directories.

import Foundation

let kMCPProtocolVersion = "2025-06-18"
private let kKnownProtocolVersions: Set<String> = ["2025-06-18", "2025-03-26", "2024-11-05"]

// Run the server loop over stdin/stdout until EOF. `roots` are canonical
// absolute directory paths (validated by the verb).
func runMCPServer(roots: [String]) {
    while let line = readLine(strippingNewline: true) {
        if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        handleLine(line, roots: roots)
    }
}

private func handleLine(_ line: String, roots: [String]) {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) else {
        writeMessage(errorResponse(id: NSNull(), code: -32700, message: "parse error"))
        return
    }
    // Valid JSON but not a JSON-RPC object (e.g. a bare array): invalid request.
    guard let message = object as? [String: Any] else {
        writeMessage(errorResponse(id: NSNull(), code: -32600, message: "invalid request"))
        return
    }

    // A message with no "id" member is a notification: never respond to it.
    let id = message["id"]
    let isNotification = (id == nil)

    guard let method = message["method"] as? String else {
        if let id = id { writeMessage(errorResponse(id: id, code: -32600, message: "invalid request")) }
        return
    }
    let params = message["params"] as? [String: Any] ?? [:]

    switch method {
    case "notifications/initialized":
        return  // notification; ignore
    case "initialize":
        respond(id, isNotification, resultResponse(id:result:), initializeResult(params: params))
    case "ping":
        respond(id, isNotification, resultResponse(id:result:), [String: Any]())
    case "tools/list":
        respond(id, isNotification, resultResponse(id:result:), ["tools": toolDefinitions()])
    case "tools/call":
        respond(id, isNotification, resultResponse(id:result:), callTool(params: params, roots: roots))
    default:
        if let id = id {
            writeMessage(errorResponse(id: id, code: -32601, message: "method not found: \(method)"))
        }
    }
}

// Emit a result response unless the message was a notification (no id).
private func respond(_ id: Any?, _ isNotification: Bool,
                     _ build: (Any, Any) -> [String: Any], _ result: Any) {
    guard !isNotification, let id = id else { return }
    writeMessage(build(id, result))
}

private func initializeResult(params: [String: Any]) -> [String: Any] {
    // Echo the client's protocol version when we recognize it; otherwise ours.
    let requested = params["protocolVersion"] as? String
    let version = (requested != nil && kKnownProtocolVersions.contains(requested!)) ? requested! : kMCPProtocolVersion
    return [
        "protocolVersion": version,
        "capabilities": ["tools": [String: Any]()],
        "serverInfo": ["name": "pdfutil", "version": kVersionNumber],
    ]
}

private func callTool(params: [String: Any], roots: [String]) -> [String: Any] {
    guard let name = params["name"] as? String else {
        return toolError("missing tool name")
    }
    let arguments = params["arguments"] as? [String: Any] ?? [:]
    do {
        return try dispatchTool(name: name, arguments: arguments, roots: roots)
    } catch let PDFUtilError.usage(message) {
        return toolError(message)
    } catch let PDFUtilError.processing(message) {
        return toolError(message)
    } catch {
        return toolError(error.localizedDescription)
    }
}

// MARK: - JSON-RPC envelope helpers

private func resultResponse(id: Any, result: Any) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "result": result]
}

private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
}

private func writeMessage(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message,
                                                 options: [.withoutEscapingSlashes]) else {
        return
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
