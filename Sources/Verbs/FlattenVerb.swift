// Verbs/FlattenVerb.swift - `pdfutil flatten`: burn annotations and form fields
// into the page content (structure-preserving save).

import Foundation

private let flattenUsage = """
Usage: pdfutil flatten [options] <in.pdf>

Flatten annotations and form fields into the page content: their visible
appearances are painted into the page and the interactive objects are removed.
A filled form's values become permanent page content (and extractable text).

Options:
  -o, --output FILE   Output file (default: edit in place)
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runFlatten(_ args: [String]) throws {
    var common = CommonOptions()
    var scanner = ArgScanner(verb: "flatten", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(flattenUsage); return
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
    try flattenDocument(path: scanner.positionals[0], output: common.output,
                        force: common.force, password: common.password)
}
