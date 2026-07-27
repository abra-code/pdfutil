// Verbs/MetadataVerb.swift - `pdfutil metadata`: read, set, delete, or strip
// Info-dictionary attributes (structure-preserving).

import Foundation

private let metadataUsage = """
Usage: pdfutil metadata [options] <in.pdf>

With no mutation flags, print the Info-dictionary attributes (human or --json),
read-only. With --set/--delete/--strip, edit them and save. Keys (case-
insensitive): title, author, subject, keywords, creator, producer,
creation-date, modification-date. A keywords VALUE is comma-separated; dates
are ISO 8601.

Options:
      --json          Print attributes as JSON (read mode only)
      --set KEY=VALUE Set an attribute (repeatable)
      --delete KEY    Remove an attribute (repeatable)
      --strip         Remove all attributes
  -o, --output FILE   Edited PDF when setting/deleting/stripping, or the file to
                      write the listing to in read mode (default: stdout /
                      in place)
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Note: PDFKit's writer resets Producer, the creation date, and the modification
date on every save, regardless of these options.

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runMetadata(_ args: [String]) throws {
    var common = CommonOptions()
    var edit = MetadataEdit()
    var scanner = ArgScanner(verb: "metadata", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(metadataUsage); return
        case "--json": common.json = true
        case "--set":
            let kv = try scanner.value(a)
            guard let eq = kv.firstIndex(of: "=") else {
                throw PDFUtilError.usage("--set expects KEY=VALUE (got '\(kv)')")
            }
            edit.sets.append((key: String(kv[..<eq]), value: String(kv[kv.index(after: eq)...])))
        case "--delete": edit.deletes.append(try scanner.value(a))
        case "--strip": edit.strip = true
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
    let path = scanner.positionals[0]
    // Same two gaps as `forms`: the mutating branch never reads common.json,
    // and the read branch never read common.output/force.
    if common.json && edit.mutates {
        throw PDFUtilError.usage("--json applies to the attribute listing only, not to --set/--delete/--strip")
    }

    let doc = try openPDF(path: path, password: common.password)

    if edit.mutates {
        // PDFKit's writer overwrites these on save; warn rather than silently drop.
        let overridden = edit.sets.map { $0.key.lowercased() }
            .filter { ["producer", "creation-date", "modification-date"].contains($0) }
        if !overridden.isEmpty {
            writeErr("metadata: note: PDFKit resets \(overridden.joined(separator: ", ")) on save; requested value not applied\n")
        }
        try applyMetadata(doc: doc, edit: edit)
        try savePDF(doc, to: common.output, force: common.force, inPlaceOf: path)
    } else {
        let attributes = readDocAttributes(doc)
        let body = common.json ? try encodeJSONString(attributes)
                               : formatAttributes(attributes)
        try writeTextOutput(body, to: common.output, force: common.force)
    }
}
