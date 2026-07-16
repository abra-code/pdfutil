// Verbs/OutlineVerb.swift - `pdfutil outline`: print the table of contents.

import Foundation

private let outlineUsage = """
Usage: pdfutil outline [options] <in.pdf>

Print the document outline (table of contents) as an indented tree, or as a
nested JSON array with --json. Read-only.

Options:
      --json          Emit the outline as nested JSON ({label, page, children})
      --password PW   Password for an encrypted PDF
  -h, --help          Show this help

A document with no outline prints "no outline" to stderr and exits 0.

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runOutline(_ args: [String]) throws {
    var common = CommonOptions()
    var scanner = ArgScanner(verb: "outline", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(outlineUsage); return
        case "--json": common.json = true
        case "--password": common.password = try scanner.value(a)
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard scanner.positionals.count == 1 else {
        throw PDFUtilError.usage("expected exactly one input PDF")
    }
    let path = scanner.positionals[0]

    let doc = try openPDF(path: path, password: common.password)
    guard let nodes = buildOutline(doc: doc) else {
        writeErr("no outline\n")
        return
    }

    if common.json {
        try emitJSON(nodes)
    } else {
        writeOut(formatOutline(nodes))
    }
}
