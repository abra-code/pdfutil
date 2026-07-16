// Verbs/SplitVerb.swift - `pdfutil split`: split into parts by page count or by
// top-level outline chapters (structure-preserving).

import Foundation

private let splitUsage = """
Usage: pdfutil split [options] <in.pdf>

Split a PDF into parts written as <prefix>-NNN.pdf (1-based, zero-padded). By
default each part is one page. Each part keeps the pages' annotations, links,
and form fields; the document outline is not carried into the parts.

Options:
      --every N       Pages per part (default 1)
      --chapters      One part per top-level outline chapter
  -o, --output PREFIX Output filename prefix (default: input minus .pdf)
      --password PW   Password for an encrypted PDF
      --force         Overwrite existing output files
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runSplit(_ args: [String]) throws {
    var common = CommonOptions()
    var everyN = 1
    var everyExplicit = false
    var chapters = false
    var scanner = ArgScanner(verb: "split", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(splitUsage); return
        case "--every": everyN = try scanner.intValue(a); everyExplicit = true
        case "--chapters": chapters = true
        case "-o", "--output": common.output = try scanner.value(a)
        case "--password": common.password = try scanner.value(a)
        case "--force": common.force = true
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard scanner.positionals.count == 1 else {
        throw PDFUtilError.usage("expected exactly one input PDF")
    }
    guard !(chapters && everyExplicit) else {
        throw PDFUtilError.usage("--every and --chapters are mutually exclusive")
    }
    let path = scanner.positionals[0]

    let doc = try openPDF(path: path, password: common.password)
    let mode: SplitMode = chapters ? .chapters : .every(everyN)
    let prefix = common.output ?? stripPDFExtension(path)
    let paths = try splitDocument(doc: doc, mode: mode, prefix: prefix, force: common.force)
    writeErr("split: wrote \(paths.count) file(s)\n")
}
