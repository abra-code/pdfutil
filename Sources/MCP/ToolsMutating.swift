// MCP/ToolsMutating.swift - the mutating MCP tools, served only when the server
// runs with --writable. The safety invariant is create-only output: every tool
// writes a NEW file at an explicit `output` path that must canonicalize under a
// root and must not already exist. There is no overwrite parameter and no MCP
// equivalent of --force, so no pre-existing byte on disk can ever change through
// this server; the guarantee is code correctness, not kernel sandboxing. Inputs
// pass the same read sandbox as the read tools, and no tool takes a password.

import Foundation
import PDFKit

// Route a mutating tool call; nil means the name is not a mutating tool (the
// caller reports it unknown). Reachable only from a --writable dispatch.
func dispatchMutatingTool(name: String, arguments: [String: Any], roots: [String]) throws -> [String: Any]? {
    switch name {
    case "pdf_merge": return try toolPdfMerge(arguments, roots)
    case "pdf_extract_pages": return try toolPdfExtractPages(arguments, roots)
    case "pdf_delete_pages": return try toolPdfDeletePages(arguments, roots)
    case "pdf_rotate": return try toolPdfRotate(arguments, roots)
    case "pdf_metadata_set": return try toolPdfMetadataSet(arguments, roots)
    default: return nil
    }
}

// MARK: - Output-path resolution (the create-only write sandbox)

// Admit a path for a new file: the parent directory must exist and canonicalize
// under one of the roots, the last component must be a plain file name, and
// nothing may already exist at the joined path. Canonicalization is parent-based
// because resolvingSymlinksInPath only realpaths components that exist, and the
// output file must not. The existence check uses attributesOfItem (which does
// not follow symlinks), so a pre-planted symlink at the name - dangling or
// pointing anywhere - counts as existing and is refused; FileManager.moveItem
// in savePDF/writeAtomically is the race backstop, failing rather than
// replacing anything that appears afterwards.
func resolveOutputPath(_ raw: String, roots: [String]) throws -> String {
    guard !raw.hasSuffix("/") else {
        throw PDFUtilError.usage("output must be a file path, not a directory: \(raw)")
    }
    let url = URL(fileURLWithPath: raw).standardizedFileURL
    let name = url.lastPathComponent
    guard !name.isEmpty, name != ".", name != "..", name != "/" else {
        throw PDFUtilError.usage("output must name a file: \(raw)")
    }

    let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDir), isDir.boolValue else {
        throw PDFUtilError.processing("output directory does not exist: \(raw)")
    }
    guard roots.contains(where: { isUnder(parent, root: $0) }) else {
        throw PDFUtilError.processing("output outside allowed roots: \(raw)")
    }

    let dest = parent == "/" ? "/" + name : parent + "/" + name
    if (try? FileManager.default.attributesOfItem(atPath: dest)) != nil {
        throw PDFUtilError.processing("output exists: \(dest) (outputs are create-only; choose a new name)")
    }
    return dest
}

// MARK: - Result shape

private struct MutationResult: Codable {
    let output: String
    let bytes: Int
    let pageCount: Int
}

// The uniform mutating-tool result: stat the written file so the agent can
// chain the next call without a separate stat round-trip.
private func mutationResult(_ output: String) throws -> [String: Any] {
    let bytes = ((try? FileManager.default.attributesOfItem(atPath: output))?[.size] as? Int) ?? 0
    let pageCount = PDFDocument(url: URL(fileURLWithPath: output))?.pageCount ?? 0
    return toolText(try encodeJSONString(MutationResult(output: output, bytes: bytes, pageCount: pageCount)))
}

// MARK: - Part A: plumbing + document assembly

private func toolPdfMerge(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    guard let rawInputs = arguments["inputs"] as? [[String: Any]], rawInputs.count >= 2 else {
        throw PDFUtilError.usage("'inputs' must be an array of at least two {path, pages?} objects")
    }
    let output = try resolveOutputPath(try requiredString(arguments, "output"), roots: roots)
    var inputs: [MergeInput] = []
    for item in rawInputs {
        let path = try resolveAllowedPath(try requiredString(item, "path"), roots: roots)
        inputs.append(MergeInput(path: path, range: try optionalString(item, "pages")))
    }
    let merged = try mergeDocuments(inputs, password: nil)
    try savePDF(merged, to: output, force: false, inPlaceOf: output)
    return try mutationResult(output)
}

private func toolPdfExtractPages(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let output = try resolveOutputPath(try requiredString(arguments, "output"), roots: roots)
    let doc = try openPDF(path: path, password: nil)
    let indices = try PageRange.parse(try requiredString(arguments, "pages"), pageCount: doc.pageCount)
    let out = try documentFromPages(doc, indices: indices)
    try savePDF(out, to: output, force: false, inPlaceOf: output)
    return try mutationResult(output)
}

private func toolPdfDeletePages(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let output = try resolveOutputPath(try requiredString(arguments, "output"), roots: roots)
    let doc = try openPDF(path: path, password: nil)
    let indices = try PageRange.parse(try requiredString(arguments, "pages"), pageCount: doc.pageCount)
    try deletePages(doc: doc, indices: indices)
    try savePDF(doc, to: output, force: false, inPlaceOf: path)
    return try mutationResult(output)
}

private func toolPdfRotate(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let output = try resolveOutputPath(try requiredString(arguments, "output"), roots: roots)
    guard let angle = try optionalInt(arguments, "angle"), [90, 180, 270, -90].contains(angle) else {
        throw PDFUtilError.usage("'angle' must be one of 90, 180, 270, -90")
    }
    let doc = try openPDF(path: path, password: nil)
    let pages = try resolvePages(try optionalString(arguments, "pages"), pageCount: doc.pageCount)
        ?? Array(0..<doc.pageCount)
    rotatePages(doc: doc, pages: pages, degrees: angle)
    try savePDF(doc, to: output, force: false, inPlaceOf: path)
    return try mutationResult(output)
}

private func toolPdfMetadataSet(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let output = try resolveOutputPath(try requiredString(arguments, "output"), roots: roots)

    var edit = MetadataEdit()
    if let rawSet = presentValue(arguments, "set") {
        guard let sets = rawSet as? [String: Any] else {
            throw PDFUtilError.usage("'set' must be an object of key: value")
        }
        for (key, value) in sets.sorted(by: { $0.key < $1.key }) {
            guard let string = value as? String else {
                throw PDFUtilError.usage("'set' values must be strings (key '\(key)')")
            }
            edit.sets.append((key: key, value: string))
        }
    }
    if let rawDelete = presentValue(arguments, "delete") {
        guard let deletes = rawDelete as? [Any] else {
            throw PDFUtilError.usage("'delete' must be an array of metadata key names")
        }
        for item in deletes {
            guard let key = item as? String else {
                throw PDFUtilError.usage("'delete' must be an array of metadata key names")
            }
            edit.deletes.append(key)
        }
    }
    guard edit.mutates else {
        throw PDFUtilError.usage("provide 'set' (an object of key: value) and/or 'delete' (an array of keys)")
    }

    let doc = try openPDF(path: path, password: nil)
    try applyMetadata(doc: doc, edit: edit)
    try savePDF(doc, to: output, force: false, inPlaceOf: path)
    return try mutationResult(output)
}

// MARK: - Tool schemas

func outputProperty() -> [String: Any] {
    ["type": "string", "description": "Path for the new PDF, under an allowed root; must not already exist (outputs are create-only)"]
}

private func pagesProperty(_ description: String) -> [String: Any] {
    ["type": "string", "description": description]
}

func mutatingToolDefinitions() -> [[String: Any]] {
    [
        [
            "name": "pdf_merge",
            "description": "Concatenate two or more PDFs (each optionally limited to a page range) into a new file. Structure-preserving: annotations, links, and form fields survive.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "inputs": [
                        "type": "array",
                        "minItems": 2,
                        "items": [
                            "type": "object",
                            "properties": [
                                "path": pathProperty(),
                                "pages": pagesProperty("Page range from this input, e.g. 1-5,9 (1-based); default all"),
                            ],
                            "required": ["path"],
                        ],
                        "description": "The PDFs to concatenate, in order",
                    ],
                    "output": outputProperty(),
                ],
                "required": ["inputs", "output"],
            ],
        ],
        [
            "name": "pdf_extract_pages",
            "description": "Copy the listed pages, in the listed order (repeats allowed), into a new PDF. Page-level structure survives; the document outline is not carried.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "pages": pagesProperty("Pages to keep, in order, e.g. 3,1,2 or 5-1 (1-based)"),
                    "output": outputProperty(),
                ],
                "required": ["path", "pages", "output"],
            ],
        ],
        [
            "name": "pdf_delete_pages",
            "description": "Write a new PDF without the listed pages. Structure-preserving; the outline is kept (destinations to removed pages may dangle).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "pages": pagesProperty("Pages to remove, e.g. 2,5-7 (1-based)"),
                    "output": outputProperty(),
                ],
                "required": ["path", "pages", "output"],
            ],
        ],
        [
            "name": "pdf_rotate",
            "description": "Write a new PDF with pages rotated by the angle, added to their current rotation. Lossless (only the page rotation entry changes).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "angle": ["type": "integer", "enum": [90, 180, 270, -90], "description": "Degrees clockwise"],
                    "pages": pagesProperty("Pages to rotate, e.g. 1-3 (1-based); default all"),
                    "output": outputProperty(),
                ],
                "required": ["path", "angle", "output"],
            ],
        ],
        [
            "name": "pdf_metadata_set",
            "description": "Write a new PDF with Info-dictionary attributes set and/or deleted. Structure-preserving. Keys: title, author, subject, keywords, creator, producer, creation-date, modification-date.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "set": [
                        "type": "object",
                        "additionalProperties": ["type": "string"],
                        "description": "Attributes to set, as key: value strings (keywords comma-separated; dates ISO 8601)",
                    ],
                    "delete": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Attribute keys to remove",
                    ],
                    "output": outputProperty(),
                ],
                "required": ["path", "output"],
            ],
        ],
    ]
}
