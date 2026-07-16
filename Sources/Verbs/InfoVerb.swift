// Verbs/InfoVerb.swift - `pdfutil info`: report version, page geometry, security,
// metadata, and outline presence. Read-only.

import Foundation

private let infoUsage = """
Usage: pdfutil info [options] <in.pdf>

Report a PDF's version, page count, per-page size/boxes/rotation, encryption
and permissions, Info-dictionary metadata, and outline item count. Read-only.

Options:
      --json          Emit the report as JSON
      --password PW   Password for an encrypted PDF
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runInfo(_ args: [String]) throws {
    var common = CommonOptions()
    var scanner = ArgScanner(verb: "info", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(infoUsage); return
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
    let cgDoc = try openCGPDF(path: path, password: common.password)
    let info = gatherInfo(path: path, doc: doc, cgDoc: cgDoc)

    if common.json {
        try emitJSON(info)
    } else {
        writeOut(formatInfo(info))
    }
}
