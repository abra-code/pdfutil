// MCP/Tools.swift - the MCP tool definitions and dispatch. Each tool is a thin
// adapter over an existing Core function, returning MCP content items. All tools
// are read-only and take a `path` confined to the configured roots.

import Foundation

// MARK: - Content-item builders

func toolText(_ text: String) -> [String: Any] {
    ["content": [["type": "text", "text": text]]]
}

func toolImage(base64: String, mimeType: String) -> [String: Any] {
    ["content": [["type": "image", "data": base64, "mimeType": mimeType]]]
}

func toolError(_ message: String) -> [String: Any] {
    ["content": [["type": "text", "text": message]], "isError": true]
}

// MARK: - Argument + path helpers

func requiredString(_ arguments: [String: Any], _ key: String) throws -> String {
    guard let value = arguments[key] as? String, !value.isEmpty else {
        throw PDFUtilError.usage("missing or invalid '\(key)'")
    }
    return value
}

func optionalString(_ arguments: [String: Any], _ key: String) -> String? {
    (arguments[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
}

func optionalInt(_ arguments: [String: Any], _ key: String) -> Int? {
    if let n = arguments[key] as? Int { return n }
    if let n = arguments[key] as? NSNumber { return n.intValue }
    return nil
}

// Canonicalize a requested path and require it to sit under one of the roots.
// Read-only tools only, so the file is expected to exist and resolve fully.
func resolveAllowedPath(_ raw: String, roots: [String]) throws -> String {
    let canonical = URL(fileURLWithPath: raw).resolvingSymlinksInPath().standardizedFileURL.path
    for root in roots where canonical == root || canonical.hasPrefix(root + "/") {
        return canonical
    }
    throw PDFUtilError.processing("path outside allowed roots: \(raw)")
}

// Cap for text payloads: past this the agent should narrow its request.
private let kMaxTextCharacters = 50_000

// MARK: - Dispatch

func dispatchTool(name: String, arguments: [String: Any], roots: [String]) throws -> [String: Any] {
    switch name {
    case "pdf_info": return try toolPdfInfo(arguments, roots)
    case "pdf_text": return try toolPdfText(arguments, roots)
    case "pdf_search": return try toolPdfSearch(arguments, roots)
    case "pdf_outline": return try toolPdfOutline(arguments, roots)
    default: return toolError("unknown tool: \(name)")
    }
}

// MARK: - Read-only text tools

private func toolPdfInfo(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let doc = try openPDF(path: path, password: optionalString(arguments, "password"))
    let cgDoc = try openCGPDF(path: path, password: optionalString(arguments, "password"))
    let info = gatherInfo(path: path, doc: doc, cgDoc: cgDoc)
    return toolText(try encodeJSONString(info))
}

private func toolPdfText(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let doc = try openPDF(path: path, password: optionalString(arguments, "password"))
    let pages = try resolvePages(optionalString(arguments, "pages"), pageCount: doc.pageCount)
    let text = try extractText(doc: doc, pages: pages, pageBreaks: false)
    if text.count > kMaxTextCharacters {
        return toolError("text is \(text.count) characters (cap \(kMaxTextCharacters)); narrow the request with the 'pages' parameter")
    }
    return toolText(text)
}

private func toolPdfSearch(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let query = try requiredString(arguments, "query")
    let doc = try openPDF(path: path, password: optionalString(arguments, "password"))
    let pages = try resolvePages(optionalString(arguments, "pages"), pageCount: doc.pageCount)
    let maxResults = max(1, optionalInt(arguments, "maxResults") ?? 50)
    let caseSensitive = (arguments["caseSensitive"] as? Bool) ?? false

    var matches = searchDocument(doc: doc, query: query, pages: pages,
                                 caseSensitive: caseSensitive, context: 40)
    let total = matches.count
    if matches.count > maxResults { matches = Array(matches.prefix(maxResults)) }
    var payload = try encodeJSONString(matches)
    if total > maxResults {
        payload += "\n(showing \(maxResults) of \(total) matches; raise 'maxResults' or narrow 'pages')"
    }
    return toolText(payload)
}

private func toolPdfOutline(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let doc = try openPDF(path: path, password: optionalString(arguments, "password"))
    guard let nodes = buildOutline(doc: doc) else {
        return toolText("(no outline)")
    }
    return toolText(try encodeJSONString(nodes))
}

// MARK: - Tool schemas (advertised by tools/list)

private func pathProperty() -> [String: Any] {
    ["type": "string", "description": "Absolute path to a PDF, under an allowed root"]
}

func toolDefinitions() -> [[String: Any]] {
    [
        [
            "name": "pdf_info",
            "description": "Report a PDF's version, page count, security, metadata, and per-page geometry as JSON.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "password": ["type": "string", "description": "Password for an encrypted PDF"],
                ],
                "required": ["path"],
            ],
        ],
        [
            "name": "pdf_text",
            "description": "Extract the text layer as UTF-8. Capped at 50000 characters; use 'pages' to narrow.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "pages": ["type": "string", "description": "Page range, e.g. 1-5,9 (1-based); default all"],
                    "password": ["type": "string", "description": "Password for an encrypted PDF"],
                ],
                "required": ["path"],
            ],
        ],
        [
            "name": "pdf_search",
            "description": "Find a string in the text layer; returns matches (page, snippet, bounds) as JSON.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "query": ["type": "string", "description": "Text to find"],
                    "pages": ["type": "string", "description": "Page range to search; default all"],
                    "maxResults": ["type": "integer", "description": "Maximum matches to return (default 50)"],
                    "caseSensitive": ["type": "boolean", "description": "Case-sensitive match (default false)"],
                    "password": ["type": "string", "description": "Password for an encrypted PDF"],
                ],
                "required": ["path", "query"],
            ],
        ],
        [
            "name": "pdf_outline",
            "description": "Return the document outline (table of contents) as a nested JSON tree.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "password": ["type": "string", "description": "Password for an encrypted PDF"],
                ],
                "required": ["path"],
            ],
        ],
    ]
}
