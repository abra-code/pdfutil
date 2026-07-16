// Verbs/SearchVerb.swift - `pdfutil search`: grep the text layer for a string.

import Foundation

private let searchUsage = """
Usage: pdfutil search [options] <in.pdf> <query>

Find every occurrence of <query> in the text layer and print the page number
and a surrounding snippet. Case-insensitive by default. Read-only.

Options:
      --json              Emit matches as JSON ({page, snippet, bounds})
  -p, --pages RANGE       Only search these pages (e.g. 1-5,9,12-end)
      --case-sensitive    Match case exactly
      --context N         Snippet context characters each side (default 20)
      --count             Print only the number of matches
      --password PW       Password for an encrypted PDF
  -h, --help              Show this help

Zero matches prints nothing and exits 0 (use --count or --json for the total).

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runSearch(_ args: [String]) throws {
    var common = CommonOptions()
    var caseSensitive = false
    var context = 20
    var countOnly = false
    var scanner = ArgScanner(verb: "search", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(searchUsage); return
        case "--json": common.json = true
        case "-p", "--pages": common.pages = try scanner.value(a)
        case "--case-sensitive": caseSensitive = true
        case "--context": context = try scanner.intValue(a)
        case "--count": countOnly = true
        case "--password": common.password = try scanner.value(a)
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard scanner.positionals.count == 2 else {
        throw PDFUtilError.usage("expected an input PDF and a query string")
    }
    let path = scanner.positionals[0]
    let query = scanner.positionals[1]
    guard !query.isEmpty else { throw PDFUtilError.usage("query must not be empty") }
    guard context >= 0 else { throw PDFUtilError.usage("--context must be >= 0") }

    let doc = try openPDF(path: path, password: common.password)
    let pages = try resolvePages(common.pages, pageCount: doc.pageCount)
    let matches = searchDocument(doc: doc, query: query, pages: pages,
                                 caseSensitive: caseSensitive, context: context)

    if countOnly {
        writeOut("\(matches.count)\n")
    } else if common.json {
        try emitJSON(matches)
    } else {
        for m in matches { writeOut("p\(m.page): \(m.snippet)\n") }
    }
}
