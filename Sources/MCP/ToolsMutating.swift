// MCP/ToolsMutating.swift - the mutating MCP tools, served only when the server
// runs with --writable. The safety invariant is create-only output: every tool
// writes a NEW file at an explicit `output` path that must canonicalize under a
// root and must not already exist. There is no overwrite parameter and no MCP
// equivalent of --force, so no pre-existing byte on disk can ever change through
// this server; the guarantee is code correctness, not kernel sandboxing. Inputs
// pass the same read sandbox as the read tools, and no tool takes a password.

import Foundation
import PDFKit
import CoreGraphics

// Rasterizing to a file has no model-context payload cost, so this cap is
// higher than the inline pdf_render's 300 - but it stays bounded, so an agent
// typo like "dpi": 100000 cannot drive a multi-gigabyte bitmap. The 30000 px
// per-side guard in renderPageToImage is the backstop.
private let kMaxRenderToFileDPI = 600.0

// Route a mutating tool call; nil means the name is not a mutating tool (the
// caller reports it unknown). Reachable only from a --writable dispatch.
func dispatchMutatingTool(name: String, arguments: [String: Any], roots: [String]) throws -> [String: Any]? {
    switch name {
    case "pdf_merge": return try toolPdfMerge(arguments, roots)
    case "pdf_extract_pages": return try toolPdfExtractPages(arguments, roots)
    case "pdf_delete_pages": return try toolPdfDeletePages(arguments, roots)
    case "pdf_rotate": return try toolPdfRotate(arguments, roots)
    case "pdf_metadata_set": return try toolPdfMetadataSet(arguments, roots)
    case "pdf_forms_fill": return try toolPdfFormsFill(arguments, roots)
    case "pdf_watermark": return try toolPdfWatermark(arguments, roots)
    case "pdf_reduce": return try toolPdfReduce(arguments, roots)
    case "pdf_render_to_file": return try toolPdfRenderToFile(arguments, roots)
    default: return nil
    }
}

// MARK: - Output-path resolution (the create-only write sandbox)

// Admit a path for a new file: the parent directory must exist and canonicalize
// under one of the roots, the last component must be a plain file name, and
// nothing may already exist at the joined path. The existence check uses
// attributesOfItem (which does not follow symlinks), so a pre-planted symlink at
// the name - dangling or pointing anywhere - counts as existing and is refused;
// FileManager.moveItem in savePDF/writeAtomically is the race backstop, failing
// rather than replacing anything that appears afterwards.
//
// DIRECTORY POLICY: this server creates FILES, never DIRECTORIES. The parent
// directory of every output must already exist; a missing one is a tool error,
// not something a tool silently fills in with the equivalent of mkdir -p. Two
// reasons, one structural and one practical:
//
//  1. The root check is parent-based, and only works because the parent exists.
//     resolvingSymlinksInPath realpaths only components that exist, so an
//     existing parent canonicalizes exactly - symlinks and .. resolved - before
//     it is tested against the roots. Creating missing components would mean
//     admitting a path whose real location cannot be known until after the
//     directories are made, which is precisely where sandbox-escape bugs live.
//  2. An agent's mistyped path should cost an error message, not a tree of
//     stray directories scattered through the user's root.
//
// The single write sandbox contract is therefore: one call creates one new file
// at a path whose directory the user already made.
func resolveOutputPath(_ raw: String, roots: [String]) throws -> String {
    guard !raw.hasSuffix("/") else {
        throw PDFUtilError.usage("output must be a file path, not a directory: \(raw)")
    }
    let url = URL(fileURLWithPath: raw).standardizedFileURL
    let name = url.lastPathComponent
    guard !name.isEmpty, name != ".", name != "..", name != "/" else {
        throw PDFUtilError.usage("output must name a file: \(raw)")
    }

    let parentDisplay = url.deletingLastPathComponent().path
    let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDir) else {
        throw PDFUtilError.processing("output directory does not exist: \(parentDisplay) - this server writes files but never creates directories; write to a directory that already exists, or ask the user to create that one")
    }
    guard isDir.boolValue else {
        throw PDFUtilError.processing("output parent is not a directory: \(parentDisplay)")
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

// reduce's result carries the before size and whether anything was gained, so a
// declined run is legible to an agent rather than looking like a success.
private struct ReduceResult: Codable {
    let output: String
    let bytes: Int
    let originalBytes: Int
    let pageCount: Int
    let reduced: Bool
}

private func reduceResult(_ output: String, originalBytes: Int) throws -> [String: Any] {
    let bytes = ((try? FileManager.default.attributesOfItem(atPath: output))?[.size] as? Int) ?? 0
    let pageCount = PDFDocument(url: URL(fileURLWithPath: output))?.pageCount ?? 0
    return toolText(try encodeJSONString(ReduceResult(
        output: output, bytes: bytes, originalBytes: originalBytes,
        pageCount: pageCount, reduced: originalBytes > 0 && bytes < originalBytes)))
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

// MARK: - Part B: forms, watermark, reduce

private func toolPdfFormsFill(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let output = try resolveOutputPath(try requiredString(arguments, "output"), roots: roots)
    guard let fields = arguments["fields"] as? [String: Any], !fields.isEmpty else {
        throw PDFUtilError.usage("'fields' must be a non-empty object of fieldName: value")
    }
    let flatten = try optionalBool(arguments, "flatten") ?? false

    let doc = try openPDF(path: path, password: nil)
    try applyFormValues(doc: doc, values: fields)
    try saveForm(doc: doc, output: output, force: false, inPlaceOf: path, flatten: flatten)
    return try mutationResult(output)
}

private func toolPdfWatermark(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let output = try resolveOutputPath(try requiredString(arguments, "output"), roots: roots)

    let text = try optionalString(arguments, "text")
    let imageRaw = try optionalString(arguments, "imagePath")
    guard (text == nil) != (imageRaw == nil) else {
        throw PDFUtilError.usage("provide exactly one of 'text' or 'imagePath'")
    }
    var spec = WatermarkSpec()
    spec.text = text
    if let imageRaw = imageRaw {
        // The watermark image is an input like any other: sandbox-checked.
        spec.imagePath = try resolveAllowedPath(imageRaw, roots: roots)
    }
    if let position = try optionalString(arguments, "position") {
        guard let p = WatermarkPosition(rawValue: position) else {
            throw PDFUtilError.usage("'position' must be one of center, top-left, top-right, bottom-left, bottom-right")
        }
        spec.position = p
    }
    let angle = try optionalDouble(arguments, "angle")
    if let angle = angle { spec.rotateMark = angle }
    if let opacity = try optionalDouble(arguments, "opacity") {
        guard opacity >= 0, opacity <= 1 else {
            throw PDFUtilError.usage("'opacity' must be between 0 and 1")
        }
        spec.opacity = opacity
    }
    spec.annotation = try optionalBool(arguments, "annotation") ?? false
    guard !(spec.annotation && spec.text == nil) else {
        throw PDFUtilError.usage("'annotation' requires 'text' (an image watermark must be burned in)")
    }
    // watermarkAnnotation never reads spec.rotateMark, so an 'angle' passed
    // alongside 'annotation' was accepted and dropped. The schema says
    // "burn-in only"; this makes the server enforce what it advertises.
    guard !(spec.annotation && angle != nil) else {
        throw PDFUtilError.usage("'angle' is burn-in only: a freeText annotation is always axis-aligned")
    }

    let doc = try openPDF(path: path, password: nil)
    let pages = try resolvePages(try optionalString(arguments, "pages"), pageCount: doc.pageCount)
    if spec.annotation {
        try watermarkAnnotation(doc: doc, output: output, force: false, pages: pages,
                                spec: spec, inPlaceOf: path)
    } else {
        try watermarkBurnIn(path: path, output: output, force: false, password: nil,
                            pages: pages, spec: spec)
    }
    return try mutationResult(output)
}

private func toolPdfReduce(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let output = try resolveOutputPath(try requiredString(arguments, "output"), roots: roots)

    var options = ReduceOptions()
    if let quality = try optionalInt(arguments, "quality") {
        guard (1...100).contains(quality) else {
            throw PDFUtilError.usage("'quality' must be between 1 and 100")
        }
        options.quality = quality
    }
    if let dpi = try optionalInt(arguments, "dpi") {
        guard dpi >= 0 else {
            throw PDFUtilError.usage("'dpi' must be >= 0 (0 disables downsampling)")
        }
        options.dpi = dpi
    }
    if let maxEdge = try optionalInt(arguments, "max_edge") {
        guard maxEdge >= 0 else {
            throw PDFUtilError.usage("'max_edge' must be >= 0 (0 disables the cap)")
        }
        options.maxEdge = maxEdge
    }
    options.gray = try optionalBool(arguments, "gray") ?? false
    // The Gray Tone system filter replaces the recompress/downsample filter
    // entirely; a combination would silently drop quality/dpi, so refuse it.
    if options.gray, presentValue(arguments, "quality") != nil || presentValue(arguments, "dpi") != nil
        || presentValue(arguments, "max_edge") != nil {
        throw PDFUtilError.usage("'gray' cannot be combined with 'quality', 'dpi' or 'max_edge' (the grayscale filter replaces recompression)")
    }

    // Sizes either side, because reduce can decline: when recompression would
    // have produced a bigger file it keeps the original and copies it to the
    // output. That is reported on stderr, which MCP never sees, so without
    // these two numbers an agent cannot tell "shrank it" from "gave you back
    // what you had" - and would go on believing the file had been optimized.
    let originalBytes = ((try? FileManager.default
        .attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
    try reduceDocument(path: path, output: output, force: false, password: nil, options: options)
    return try reduceResult(output, originalBytes: originalBytes)
}

// MARK: - Page rasterization to a file

// The output extension selects the image format, and there is no `format`
// parameter to disagree with it: a call naming format "png" with output
// "page.jpg" has no defensible resolution, so the name on disk decides.
private func imageFormatForOutput(_ output: String) throws -> ImageFormat {
    switch (output as NSString).pathExtension.lowercased() {
    case "png": return .png
    case "jpg", "jpeg": return .jpeg
    case "tiff", "tif": return .tiff
    case "heic": return .heic
    default:
        throw PDFUtilError.usage("'output' must end in .png, .jpg/.jpeg, .tiff/.tif, or .heic (the extension selects the image format)")
    }
}

private struct RenderFileResult: Codable {
    let output: String
    let bytes: Int
    let format: String
    let width: Int
    let height: Int
    let dpi: Int
}

// Rasterize one page to a NEW image file - the write-tier counterpart of the
// inline pdf_render, which returns its PNG in the result and touches no disk.
// Single page per call, like pdf_render: a page range would mean several output
// files under prefix naming, and the create-only guarantee is exact only when
// one call claims one path.
private func toolPdfRenderToFile(_ arguments: [String: Any], _ roots: [String]) throws -> [String: Any] {
    let path = try resolveAllowedPath(try requiredString(arguments, "path"), roots: roots)
    let output = try resolveOutputPath(try requiredString(arguments, "output"), roots: roots)
    let format = try imageFormatForOutput(output)

    guard let page1 = try optionalInt(arguments, "page") else {
        throw PDFUtilError.usage("missing or invalid 'page' (a single 1-based page number)")
    }
    let doc = try openPDF(path: path, password: nil)
    guard page1 >= 1, page1 <= doc.pageCount, let page = doc.page(at: page1 - 1) else {
        throw PDFUtilError.usage("page \(page1) out of range (1-\(doc.pageCount))")
    }

    let dpi = min(kMaxRenderToFileDPI, max(1, Double(try optionalInt(arguments, "dpi") ?? 150)))

    // Refuse quality on a format that ignores it, rather than accept a value
    // that silently does nothing.
    let quality = try optionalInt(arguments, "quality") ?? 85
    if presentValue(arguments, "quality") != nil {
        guard format.isLossy else {
            throw PDFUtilError.usage("'quality' applies only to .jpg/.jpeg and .heic outputs")
        }
        guard (1...100).contains(quality) else {
            throw PDFUtilError.usage("'quality' must be between 1 and 100")
        }
    }
    let transparent = try optionalBool(arguments, "transparent") ?? false
    guard !transparent || format.supportsTransparency else {
        throw PDFUtilError.usage("'transparent' is not supported for \(format.rawValue)")
    }

    let image = try renderPageToImage(page, dpi: dpi, transparent: transparent)
    // Write through the temp-then-move helper so the create-only guarantee
    // survives a file appearing at the path after resolveOutputPath checked:
    // moveItem fails rather than replacing it.
    try writeAtomically(to: output, force: false, inPlaceOf: output) { tmp in
        try writeCGImage(image, to: tmp, format: format,
                         quality: Double(quality) / 100.0, dpi: dpi)
    }

    let bytes = ((try? FileManager.default.attributesOfItem(atPath: output))?[.size] as? Int) ?? 0
    return toolText(try encodeJSONString(RenderFileResult(
        output: output, bytes: bytes, format: format.rawValue,
        width: image.width, height: image.height, dpi: Int(dpi))))
}

// MARK: - Tool schemas

func outputProperty() -> [String: Any] {
    ["type": "string", "description": "Path for the new PDF, under an allowed root. Must not already exist (outputs are create-only), and its parent directory must already exist (this server never creates directories)"]
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
        [
            "name": "pdf_forms_fill",
            "description": "Write a new PDF with AcroForm fields filled. Structure-preserving; with 'flatten' the values burn into the page and the interactive fields are dropped. Text/choice values are strings; checkbox values are booleans.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "fields": [
                        "type": "object",
                        "description": "Values to fill, as fieldName: value (string for text/choice, boolean for a checkbox); list names first with pdf_forms_list",
                    ],
                    "flatten": ["type": "boolean", "description": "Burn the values into the page content and drop the interactive fields (default false)"],
                    "output": outputProperty(),
                ],
                "required": ["path", "fields", "output"],
            ],
        ],
        [
            "name": "pdf_watermark",
            "description": "Write a new PDF with a text or image watermark on the selected pages. The default burn-in redraws the document, so the output loses annotations, links, outline, and form fields; 'annotation': true adds a structure-preserving text annotation instead (axis-aligned, text only).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "text": ["type": "string", "description": "Watermark text (exactly one of 'text' or 'imagePath')"],
                    "imagePath": ["type": "string", "description": "Watermark image file, under an allowed root (exactly one of 'text' or 'imagePath')"],
                    "position": ["type": "string", "enum": ["center", "top-left", "top-right", "bottom-left", "bottom-right"], "description": "Anchor on the page (default center)"],
                    "angle": ["type": "number", "description": "Rotation of the mark in degrees; burn-in only (default 45). Refused when 'annotation' is true, since a freeText annotation is always axis-aligned"],
                    "opacity": ["type": "number", "description": "Mark opacity 0-1 (default 0.25)"],
                    "pages": pagesProperty("Pages to mark, e.g. 1-3 (1-based); default all"),
                    "annotation": ["type": "boolean", "description": "Add a structure-preserving freeText annotation instead of burning in (text only, default false)"],
                    "output": outputProperty(),
                ],
                "required": ["path", "output"],
            ],
        ],
        [
            "name": "pdf_reduce",
            "description": "Write a smaller PDF by recompressing and downsampling raster images. Redraws the document: the output loses annotations, links, outline, and form fields.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "quality": ["type": "integer", "description": "JPEG quality 1-100 (default 85)"],
                    "dpi": ["type": "integer", "description": "Downsample images above this DPI; 0 disables (default 150)"],
                    "max_edge": ["type": "integer", "description": "Cap the longest image edge in pixels; 0 disables (default 2400). This cap is what makes 'quality' take effect: only images that get rescaled are re-encoded."],
                    "gray": ["type": "boolean", "description": "Convert to grayscale via the system Gray Tone filter; cannot be combined with quality/dpi/max_edge (default false)"],
                    "output": outputProperty(),
                ],
                "required": ["path", "output"],
            ],
        ],
        [
            "name": "pdf_render_to_file",
            "description": "Rasterize a single page to a NEW image file on disk. The extension of 'output' selects the format. Use this when the image must be saved; pdf_render returns a PNG inline and writes nothing.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": pathProperty(),
                    "page": ["type": "integer", "description": "1-based page number (a single page)"],
                    "output": ["type": "string", "description": "Path for the new image, under an allowed root. Must not already exist (outputs are create-only), and its parent directory must already exist (this server never creates directories). The extension selects the format: .png, .jpg/.jpeg, .tiff/.tif, or .heic"],
                    "dpi": ["type": "integer", "description": "Resolution in DPI (default 150, max 600)"],
                    "quality": ["type": "integer", "description": "Lossy quality 1-100 for .jpg/.jpeg and .heic outputs (default 85); refused for other formats"],
                    "transparent": ["type": "boolean", "description": "Keep the background transparent; not supported for .jpg/.jpeg (default false)"],
                ],
                "required": ["path", "page", "output"],
            ],
        ],
    ]
}
