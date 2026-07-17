// Verbs/LinearizeVerb.swift - `pdfutil linearize`: rewrite for fast web view.

import Foundation

private let linearizeUsage = """
Usage: pdfutil linearize [options] <in.pdf>

Rewrite the PDF in linearized ("fast web view") form, so a viewer can display
the first page before the whole file has downloaded.

Redraw path: the document is re-recorded through a new PDF context, so
annotations, links, outline, and form fields are not carried over.

Options:
  -o, --output FILE   Output file (default: edit in place)
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runLinearize(_ args: [String]) throws {
    var common = CommonOptions()
    var scanner = ArgScanner(verb: "linearize", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(linearizeUsage); return
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
    try linearizeDocument(path: scanner.positionals[0], output: common.output,
                          force: common.force, password: common.password)
}
