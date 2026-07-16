// Verbs/PagesVerb.swift - `pdfutil pages`: extract/reorder or delete pages
// (structure-preserving).

import Foundation

private let pagesUsage = """
Usage: pdfutil pages (--extract RANGE | --delete RANGE) [options] <in.pdf>

Keep or drop pages by range. --extract keeps exactly the listed pages in the
listed order, so it doubles as the reorder/duplicate tool (repeats are legal).
--delete removes the listed pages. Page-level structure (annotations, links,
form fields) survives. --extract rebuilds the document, so the outline is not
carried; --delete edits in place and keeps the outline (destinations to removed
pages may dangle).

Options:
      --extract RANGE Keep these pages, in this order (e.g. 3,1,2 or 5-1)
      --delete RANGE  Remove these pages
  -o, --output FILE   Output file (default: edit in place)
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runPages(_ args: [String]) throws {
    var common = CommonOptions()
    var extractSpec: String?
    var deleteSpec: String?
    var scanner = ArgScanner(verb: "pages", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(pagesUsage); return
        case "--extract": extractSpec = try scanner.value(a)
        case "--delete": deleteSpec = try scanner.value(a)
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
    guard (extractSpec == nil) != (deleteSpec == nil) else {
        throw PDFUtilError.usage("exactly one of --extract or --delete is required")
    }
    let path = scanner.positionals[0]

    let doc = try openPDF(path: path, password: common.password)

    if let spec = extractSpec {
        let indices = try PageRange.parse(spec, pageCount: doc.pageCount)
        let out = try documentFromPages(doc, indices: indices)
        try savePDF(out, to: common.output, force: common.force, inPlaceOf: path)
    } else if let spec = deleteSpec {
        let indices = try PageRange.parse(spec, pageCount: doc.pageCount)
        let toDelete = Set(indices).sorted(by: >)   // descending so earlier removals do not shift
        guard toDelete.count < doc.pageCount else {
            throw PDFUtilError.processing("cannot delete every page")
        }
        for idx in toDelete { autoreleasepool { doc.removePage(at: idx) } }
        try savePDF(doc, to: common.output, force: common.force, inPlaceOf: path)
    }
}
