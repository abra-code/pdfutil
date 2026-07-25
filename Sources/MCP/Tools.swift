// MCP/Tools.swift - the MCP tool definitions and dispatch. Each tool is a thin
// adapter over an existing Core function, returning MCP content items. The tools
// here are read-only and take a `path` confined to the configured roots; the
// mutating tier (ToolsMutating.swift) is dispatched from here only when the
// server runs with --writable. No tool accepts a password: passwords must not
// travel through the agent, so encrypted PDFs are CLI-only (dispatchTool refuses
// the param outright).

import Foundation
import PDFKit

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

// The optional-argument helpers are strict about type: an absent key returns
// nil, but a present value of the wrong type is a usage error, never silently
// ignored - a dropped argument would make the tool do something the agent did
// not ask for (e.g. a burn-in redraw where "annotation": "true" was meant).
// A JSON null counts as absent: clients and tool-call serializers routinely
// emit null for an omitted optional property.

func presentValue(_ arguments: [String: Any], _ key: String) -> Any? {
    guard let raw = arguments[key], !(raw is NSNull) else { return nil }
    return raw
}

func optionalString(_ arguments: [String: Any], _ key: String) throws -> String? {
    guard let raw = presentValue(arguments, key) else { return nil }
    guard let value = raw as? String else {
        throw PDFUtilError.usage("'\(key)' must be a string")
    }
    return value.isEmpty ? nil : value
}

// Strict integer: JSON booleans (which bridge to NSNumber) and fractional
// numbers are refused rather than truncated.
func optionalInt(_ arguments: [String: Any], _ key: String) throws -> Int? {
    guard let raw = presentValue(arguments, key) else { return nil }
    guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else {
        throw PDFUtilError.usage("'\(key)' must be an integer")
    }
    if CFNumberIsFloatType(n) {
        guard let value = Int(exactly: n.doubleValue) else {
            throw PDFUtilError.usage("'\(key)' must be an integer")
        }
        return value
    }
    return n.intValue
}

func optionalDouble(_ arguments: [String: Any], _ key: String) throws -> Double? {
    guard let raw = presentValue(arguments, key) else { return nil }
    guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else {
        throw PDFUtilError.usage("'\(key)' must be a number")
    }
    return n.doubleValue
}

// Strict boolean: only a JSON true/false qualifies (an NSNumber 0/1 or a
// string "true" does not).
func optionalBool(_ arguments: [String: Any], _ key: String) throws -> Bool? {
    guard let raw = presentValue(arguments, key) else { return nil }
    guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else {
        throw PDFUtilError.usage("'\(key)' must be true or false")
    }
    return n.boolValue
}

// Is `path` the root itself or inside it? The root "/" needs the special arm:
// "/" + "/" never prefixes anything.
func isUnder(_ path: String, root: String) -> Bool {
    path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
}

// Canonicalize a requested path and require it to sit under one of the roots.
// Read-only tools only, so the file is expected to exist and resolve fully.
func resolveAllowedPath(_ raw: String, roots: [String]) throws -> String {
    let canonical = URL(fileURLWithPath: raw).resolvingSymlinksInPath().standardizedFileURL.path
    for root in roots where isUnder(canonical, root: root) {
        return canonical
    }
    throw PDFUtilError.processing("path outside allowed roots: \(raw)")
}

// Cap for text payloads: past this the agent should narrow its request.
private let kMaxTextCharacters = 50_000

// MARK: - Dispatch

func dispatchTool(name: String, arguments: [String: Any], roots: [String], writable: Bool) throws -> [String: Any] {
    if presentValue(arguments, "password") != nil {
        return toolError("'password' is not accepted over MCP: passwords must not pass through the agent. Use the pdfutil CLI to work with encrypted PDFs.")
    }
    switch name {
    case "pdf_info": return try toolPdfInfo(arguments, roots)
    case "pdf_text": return try toolPdfText(arguments, roots)
    case "pdf_search": return try toolPdfSearch(arguments, roots)
    case "pdf_outline": return try toolPdfOutline(arguments, roots)
    case "pdf_render": return try toolPdfRender(arguments, roots)
    case "pdf_ocr": return try toolPdfOcr(arguments, roots)
    case "pdf_forms_list": return try toolPdfFormsList(arguments, roots)
    case "pdf_list": return try toolPdfList(arguments, roots)
    default:
        // The mutating tier exists only on a --writable server; without the
        // flag its names are indistinguishable from unknown tools.
        if writable, let result = try dispatchMutatingTool(name: name, arguments: arguments, roots: roots) {
            return result
        }
        return toolError("unknown tool: \(name)")
    }
}

// MARK: - Read-only text tools

private func toolPdfInfo(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let doc = try openPDF(path: path, password: nil)
    let cgDoc = try openCGPDF(path: path, password: nil)
    let info = gatherInfo(path: path, doc: doc, cgDoc: cgDoc)
    return toolText(try encodeJSONString(info))
}

private func toolPdfText(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let doc = try openPDF(path: path, password: nil)
    let pages = try resolvePages(try optionalString(arguments, "pages"), pageCount: doc.pageCount)
    let text = try extractText(doc: doc, pages: pages, pageBreaks: false)
    if text.count > kMaxTextCharacters {
        return toolError("text is \(text.count) characters (cap \(kMaxTextCharacters)); narrow the request with the 'pages' parameter")
    }
    return toolText(text)
}

private func toolPdfSearch(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let query = try requiredString(arguments, "query")
    let doc = try openPDF(path: path, password: nil)
    let pages = try resolvePages(try optionalString(arguments, "pages"), pageCount: doc.pageCount)
    let maxResults = max(1, try optionalInt(arguments, "maxResults") ?? 50)
    let caseSensitive = try optionalBool(arguments, "caseSensitive") ?? false

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
    let doc = try openPDF(path: path, password: nil)
    guard let nodes = buildOutline(doc: doc) else {
        return toolText("(no outline)")
    }
    return toolText(try encodeJSONString(nodes))
}

// Cap for pdf_list: past this the agent should narrow the request.
private let kMaxListEntries = 500

private struct ListedPDF: Codable {
    let path: String
    let bytes: Int
    let pageCount: Int?   // null when the file is encrypted or unreadable
}

// pdf_list: enumerate the PDFs under the roots, so multi-document workflows
// work in shell-less hosts (the agent cannot otherwise discover files).
private func toolPdfList(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let recursive = try optionalBool(arguments, "recursive") ?? true
    let scope: [String]
    if let raw = try optionalString(arguments, "root") {
        scope = [try resolveAllowedPath(raw, roots: roots)]
    } else {
        scope = roots
    }

    // Collect candidate paths. The enumerator is driven lazily (a root may sit
    // over a huge tree; only the .pdf names are retained), and hidden files and
    // anything inside a hidden directory (.git, .Trash, caches) are skipped.
    let fm = FileManager.default
    var paths: Set<String> = []
    for root in scope {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir) else { continue }
        // A file root lists itself.
        if !isDir.boolValue {
            if root.lowercased().hasSuffix(".pdf") { paths.insert(root) }
            continue
        }
        let names: AnySequence<String>
        if recursive, let enumerator = fm.enumerator(atPath: root) {
            names = AnySequence(enumerator.lazy.compactMap { $0 as? String })
        } else {
            names = AnySequence((try? fm.contentsOfDirectory(atPath: root)) ?? [])
        }
        for name in names where name.lowercased().hasSuffix(".pdf") {
            if name.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            // Canonicalize and re-check the sandbox; this also drops symlinks
            // that point outside the roots.
            guard let canonical = try? resolveAllowedPath(root + "/" + name, roots: roots) else { continue }
            var entryIsDir: ObjCBool = false
            guard fm.fileExists(atPath: canonical, isDirectory: &entryIsDir), !entryIsDir.boolValue else { continue }
            paths.insert(canonical)
        }
    }

    var sorted = paths.sorted()
    let total = sorted.count
    if total > kMaxListEntries { sorted = Array(sorted.prefix(kMaxListEntries)) }

    let entries = sorted.map { path -> ListedPDF in
        autoreleasepool {
            let bytes = ((try? fm.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
            let doc = PDFDocument(url: URL(fileURLWithPath: path))
            let pageCount = (doc == nil || doc!.isLocked) ? nil : doc!.pageCount
            return ListedPDF(path: path, bytes: bytes, pageCount: pageCount)
        }
    }
    var payload = try encodeJSONString(entries)
    if total > kMaxListEntries {
        payload += "\n(showing \(kMaxListEntries) of \(total) PDFs; narrow with 'root' or 'recursive': false)"
    }
    return toolText(payload)
}

// MARK: - Tool schemas (advertised by tools/list)

func pathProperty() -> [String: Any] {
    ["type": "string", "description": "Absolute path to a PDF, under an allowed root"]
}

// All advertised tools, annotated per the MCP spec (2025-03-26+): the read
// tools carry readOnlyHint true; the mutating tools declare themselves
// non-read-only but non-destructive (create-only outputs cannot alter or
// destroy existing data) and non-idempotent (a repeat call fails because the
// output now exists). Hosts use these hints to calibrate permission prompts.
func toolDefinitions(writable: Bool) -> [[String: Any]] {
    var defs = readToolDefinitions().map { def -> [String: Any] in
        var d = def
        d["annotations"] = ["readOnlyHint": true, "openWorldHint": false]
        return d
    }
    if writable {
        defs += mutatingToolDefinitions().map { def -> [String: Any] in
            var d = def
            d["annotations"] = ["readOnlyHint": false, "destructiveHint": false,
                                "idempotentHint": false, "openWorldHint": false]
            return d
        }
    }
    return defs
}

private func readToolDefinitions() -> [[String: Any]] {
    [
        [
            "name": "pdf_info",
            "description": "Report a PDF's version, page count, security, metadata, and per-page geometry as JSON.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
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
                ],
                "required": ["path"],
            ],
        ],
        [
            "name": "pdf_render",
            "description": "Rasterize a single page to a PNG image. dpi defaults to 150 and is capped at 300.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "page": ["type": "integer", "description": "1-based page number (single page)"],
                    "dpi": ["type": "integer", "description": "Resolution in DPI (default 150, max 300)"],
                ],
                "required": ["path", "page"],
            ],
        ],
        [
            "name": "pdf_ocr",
            "description": "Recognize text with Vision (rasterizes each page). Capped at 50000 characters.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "pages": ["type": "string", "description": "Page range to OCR; default all"],
                    "languages": [
                        "type": "array", "items": ["type": "string"],
                        "description": "BCP-47 language tags (e.g. en-US); omit to auto-detect",
                    ],
                ],
                "required": ["path"],
            ],
        ],
        [
            "name": "pdf_forms_list",
            "description": "List the AcroForm fields (page, name, kind, value, choices, readOnly) as JSON.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                ],
                "required": ["path"],
            ],
        ],
        [
            "name": "pdf_list",
            "description": "List the PDFs under the allowed roots (path, bytes, pageCount) as JSON. Capped at 500 entries.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "root": ["type": "string", "description": "List only under this path (must be within an allowed root); default all roots"],
                    "recursive": ["type": "boolean", "description": "Descend into subdirectories (default true)"],
                ],
            ],
        ],
    ]
}
