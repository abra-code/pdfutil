// Verbs/PdfaVerb.swift - `pdfutil pdfa`: rewrite as PDF/A.

import Foundation

private let pdfaUsage = """
Usage: pdfutil pdfa [options] <in.pdf>

Rewrite the PDF as PDF/A using Apple's writer, an archival format that embeds
fonts and forbids external dependencies. The output is tagged PDF/A-2B (observed
via its XMP pdfaid part 2, conformance B). Validate the result independently
(e.g. veraPDF) for archival use; this tool does not verify conformance.

Redraw path: the document is re-recorded through a new PDF context, so
annotations, links, outline, and form fields are not carried over.

Options:
  -o, --output FILE   Output file (default: edit in place)
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runPdfa(_ args: [String]) throws {
    var common = CommonOptions()
    var scanner = ArgScanner(verb: "pdfa", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(pdfaUsage); return
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
    try pdfaDocument(path: scanner.positionals[0], output: common.output,
                     force: common.force, password: common.password)
}
