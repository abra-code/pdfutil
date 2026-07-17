// Verbs/FormsVerb.swift - `pdfutil forms`: list, fill, and/or flatten AcroForm
// fields (structure-preserving).

import Foundation

private let formsUsage = """
Usage: pdfutil forms [options] <in.pdf>

With no mutation flags (or --list), print the document's form fields (human or
--json): page, field name, kind (text/button/choice), value, any choices, and
read-only status. Read-only.

With --fill DATA.json, set field values from a JSON object of {fieldName: value}
(a string for text/choice fields, true/false for buttons) and save. Add
--flatten to burn the filled values into the page content afterward. Filling is
structure-preserving; flattening removes the interactive widgets.

A button value of true/false suits a single checkbox; multi-widget radio groups
are not individually selectable this way.

Options:
      --list          List the form fields (the default)
      --json          With --list, print the fields as JSON
      --fill DATA     Set field values from a JSON object file, then save
      --flatten       Burn the (filled) fields into the page content on save
  -o, --output FILE   Output file for edits (default: edit in place)
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runForms(_ args: [String]) throws {
    var common = CommonOptions()
    var list = false
    var fillPath: String?
    var flatten = false
    var scanner = ArgScanner(verb: "forms", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(formsUsage); return
        case "--list": list = true
        case "--json": common.json = true
        case "--fill": fillPath = try scanner.value(a)
        case "--flatten": flatten = true
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
    let mutating = fillPath != nil || flatten
    if list && mutating {
        throw PDFUtilError.usage("--list cannot be combined with --fill/--flatten")
    }
    let path = scanner.positionals[0]
    let doc = try openPDF(path: path, password: common.password)

    if mutating {
        if let fillPath = fillPath {
            try fillForm(doc: doc, dataPath: fillPath)
        }
        try saveForm(doc: doc, output: common.output, force: common.force,
                     inPlaceOf: path, flatten: flatten)
        return
    }

    let fields = gatherFormFields(doc)
    if common.json {
        try emitJSON(fields)
    } else {
        writeOut(formatFormFields(fields))
    }
}
