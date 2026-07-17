// Verbs/McpVerb.swift - `pdfutil mcp`: run the read-only MCP server over stdio.

import Foundation

private let mcpUsage = """
Usage: pdfutil mcp --root DIR [--root DIR]...

Run a read-only Model Context Protocol server over stdio (newline-delimited
JSON-RPC 2.0). It exposes the read-only PDF tools (pdf_info, pdf_text,
pdf_search, pdf_outline, pdf_render, pdf_ocr, pdf_forms_list). Every tool's path
must resolve under one of the --root directories; requests outside them are
refused. At least one --root is required.

Options:
      --root DIR   Allow access to this directory (repeatable, required)
  -h, --help       Show this help

Exit status: 0 on clean shutdown (stdin EOF), 1 on a usage error.
"""

func runMcp(_ args: [String]) throws {
    var roots: [String] = []
    var scanner = ArgScanner(verb: "mcp", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(mcpUsage); return
        case "--root": roots.append(try scanner.value(a))
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard scanner.positionals.isEmpty else {
        throw PDFUtilError.usage("mcp takes no positional arguments (only --root DIR)")
    }
    guard !roots.isEmpty else {
        throw PDFUtilError.usage("at least one --root DIR is required")
    }

    // Canonicalize each root and require it to be an existing directory.
    var canonicalRoots: [String] = []
    for root in roots {
        let path = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw PDFUtilError.usage("--root is not a directory: \(root)")
        }
        canonicalRoots.append(path)
    }

    runMCPServer(roots: canonicalRoots)
}
