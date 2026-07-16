// Verbs/MergeVerb.swift - `pdfutil merge`: concatenate PDFs (structure-preserving).

import Foundation

private let mergeUsage = """
Usage: pdfutil merge -o out.pdf [options] <in1.pdf> [-p RANGE] <in2.pdf> [-p RANGE] ...

Concatenate PDFs into one output. A -p range binds to the input file that
precedes it; an input with no range contributes all its pages. Page-level
structure (annotations, links, form fields) is carried over; the document
outline is not merged across inputs.

Options:
  -o, --output FILE   Output file (required)
  -p, --pages RANGE   Restrict the preceding input to these pages
      --password PW   Password tried against every locked input
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runMerge(_ args: [String]) throws {
    var output: String?
    var force = false
    var password: String?
    var inputs: [MergeInput] = []
    var scanner = ArgScanner(verb: "merge", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(mergeUsage); return
        case "-o", "--output": output = try scanner.value(a)
        case "--force": force = true
        case "--password": password = try scanner.value(a)
        case "-p", "--pages":
            let spec = try scanner.value(a)
            guard !inputs.isEmpty else {
                throw PDFUtilError.usage("-p must follow an input file")
            }
            guard inputs[inputs.count - 1].range == nil else {
                throw PDFUtilError.usage("multiple -p ranges for one input")
            }
            inputs[inputs.count - 1].range = spec
        case "--":
            scanner.endOptions()
        default:
            if a.hasPrefix("-") && a != "-" {
                throw PDFUtilError.usage("unknown option '\(a)'")
            }
            inputs.append(MergeInput(path: a, range: nil))
        }
    }
    // Any inputs gathered after "--" carry no range.
    for path in scanner.positionals { inputs.append(MergeInput(path: path, range: nil)) }

    guard let output = output else {
        throw PDFUtilError.usage("merge requires -o/--output")
    }
    guard inputs.count >= 2 || (inputs.count == 1 && inputs[0].range != nil) else {
        throw PDFUtilError.usage("merge needs at least two inputs (or one input with -p)")
    }

    let merged = try mergeDocuments(inputs, password: password)
    try savePDF(merged, to: output, force: force, inPlaceOf: output)
}
