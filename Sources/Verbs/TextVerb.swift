// Verbs/TextVerb.swift - `pdfutil text`: extract the text layer to stdout or a
// file. Thin front-end over openPDF + extractText.

import Foundation

private let textUsage = """
Usage: pdfutil text [options] <in.pdf>

Extract the text layer of a PDF as UTF-8. Text is pulled per page, so page
ranges are honored and memory stays flat on large files. Image-only/scanned
pages have no text layer; use 'pdfutil ocr' for those.

Options:
  -p, --pages RANGE   Only these pages (e.g. 1-5,9,12-end; 1-based, inclusive)
      --page-breaks   Separate pages with a form feed instead of a newline
      --password PW   Password for an encrypted PDF
  -o, --output FILE   Write to FILE instead of stdout
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runText(_ args: [String]) throws {
    var common = CommonOptions()
    var pageBreaks = false
    var scanner = ArgScanner(verb: "text", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(textUsage); return
        case "-o", "--output": common.output = try scanner.value(a)
        case "-p", "--pages": common.pages = try scanner.value(a)
        case "--password": common.password = try scanner.value(a)
        case "--force": common.force = true
        case "--page-breaks": pageBreaks = true
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard scanner.positionals.count == 1 else {
        throw PDFUtilError.usage("expected exactly one input PDF")
    }
    let path = scanner.positionals[0]

    let doc = try openPDF(path: path, password: common.password)
    let pages = try resolvePages(common.pages, pageCount: doc.pageCount)
    let text = try extractText(doc: doc, pages: pages, pageBreaks: pageBreaks)
    try writeTextOutput(text, to: common.output, force: common.force)
}
