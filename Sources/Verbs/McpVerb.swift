// Verbs/McpVerb.swift - `pdfutil mcp`: run the MCP server over stdio.
// Read-only by default; --writable adds the mutating tools (create-only outputs).

import Foundation

private let mcpUsage = """
Usage: pdfutil mcp --root PATH [--root PATH]... [--writable]

Run a Model Context Protocol server over stdio (newline-delimited JSON-RPC
2.0). It exposes the read-only PDF tools (pdf_info, pdf_text, pdf_search,
pdf_outline, pdf_render, pdf_ocr, pdf_forms_list, pdf_list). Every tool's
path must resolve under one of the --root paths; requests outside them are
refused. A --root may be a directory or a single PDF file (which allows
exactly that file). At least one --root is required.

With --writable the mutating tools (pdf_merge, pdf_extract_pages,
pdf_delete_pages, pdf_rotate, pdf_metadata_set, pdf_forms_fill,
pdf_watermark, pdf_reduce) are also served. Every mutating tool writes its
result to a NEW file under a --root and fails if the output path already
exists; there is no overwrite option, so no pre-existing file can ever be
modified or destroyed through the server.

Options:
      --root PATH  Allow access to this directory or PDF file (repeatable, required)
      --writable   Also serve the mutating tools (create-only outputs)
  -h, --help       Show this help

Exit status: 0 on clean shutdown (stdin EOF), 1 on a usage error.
"""

func runMcp(_ args: [String]) throws {
    var roots: [String] = []
    var writable = false
    var scanner = ArgScanner(verb: "mcp", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(mcpUsage); return
        case "--root": roots.append(try scanner.value(a))
        case "--writable": writable = true
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard scanner.positionals.isEmpty else {
        throw PDFUtilError.usage("mcp takes no positional arguments (only --root PATH and --writable)")
    }
    guard !roots.isEmpty else {
        throw PDFUtilError.usage("at least one --root PATH is required")
    }

    // Canonicalize each root and require it to exist. A directory root allows
    // everything under it; a file root allows exactly that file (least
    // privilege for a one-document session). File roots can never host
    // outputs: an output path only matches a file root by being equal to it,
    // and an equal path already exists, which create-only writing refuses.
    var canonicalRoots: [String] = []
    for root in roots {
        let path = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw PDFUtilError.usage("--root does not exist: \(root)")
        }
        canonicalRoots.append(path)
    }

    runMCPServer(roots: canonicalRoots, writable: writable)
}
