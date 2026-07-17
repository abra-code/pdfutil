// main.swift - entry point: the verb table, global --help/--version handling,
// dispatch, and translation of PDFUtilError into the exit-code contract.
//
// This is the only source file with top-level code (a swiftc requirement when
// several files are compiled together). Every other file defines types or
// free functions.

import Foundation

let kProgram = "pdfutil"
let kVersion = "pdfutil 0.1"

// One entry per verb: its name, a one-line summary for the global help, and the
// handler that parses the verb's own arguments and runs it.
struct VerbEntry {
    let name: String
    let summary: String
    let run: ([String]) throws -> Void
}

let gVerbs: [VerbEntry] = [
    VerbEntry(name: "info", summary: "Report version, pages, security, and metadata", run: runInfo),
    VerbEntry(name: "text", summary: "Extract the text layer as UTF-8 text", run: runText),
    VerbEntry(name: "search", summary: "Find a string and print page + snippet", run: runSearch),
    VerbEntry(name: "outline", summary: "Print the table of contents", run: runOutline),
    VerbEntry(name: "merge", summary: "Concatenate PDFs into one", run: runMerge),
    VerbEntry(name: "split", summary: "Split into parts by count or chapter", run: runSplit),
    VerbEntry(name: "pages", summary: "Extract/reorder or delete pages by range", run: runPages),
    VerbEntry(name: "rotate", summary: "Rotate pages by 90/180/270/-90", run: runRotate),
    VerbEntry(name: "crop", summary: "Set a page box by rect or margins", run: runCrop),
    VerbEntry(name: "metadata", summary: "Read, set, delete, or strip metadata", run: runMetadata),
    VerbEntry(name: "render", summary: "Rasterize pages to PNG/JPEG/TIFF/HEIC", run: runRender),
    VerbEntry(name: "frompages", summary: "Build a PDF from images and/or PDFs", run: runFromPages),
    VerbEntry(name: "encrypt", summary: "Add password protection and permissions", run: runEncrypt),
    VerbEntry(name: "decrypt", summary: "Remove password protection", run: runDecrypt),
]

func printGlobalUsage(to handle: FileHandle) {
    let width = gVerbs.map { $0.name.count }.max() ?? 0
    var out = "Usage: \(kProgram) <verb> [options] <input...>\n\n"
    out += "Verbs:\n"
    for v in gVerbs {
        out += "  " + v.name.padding(toLength: width, withPad: " ", startingAt: 0)
            + "  " + v.summary + "\n"
    }
    out += "\nGlobal options:\n"
    out += "  --help       Show this help\n"
    out += "  --version    Show the version and exit\n"
    out += "\nRun '\(kProgram) <verb> --help' for a verb's own options.\n"
    out += "Exit status: 0 success, 1 usage/argument error, 2 processing error.\n"
    handle.write(Data(out.utf8))
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.isEmpty {
    printGlobalUsage(to: .standardOutput)
    exit(0)
}

let firstArg = arguments[0]

if firstArg == "--help" || firstArg == "-h" {
    printGlobalUsage(to: .standardOutput)
    exit(0)
}
if firstArg == "--version" {
    print(kVersion)
    exit(0)
}
if firstArg.hasPrefix("-") {
    writeErr("\(kProgram): unknown option '\(firstArg)'\nTry '\(kProgram) --help'.\n")
    exit(1)
}

guard let verb = gVerbs.first(where: { $0.name == firstArg }) else {
    writeErr("\(kProgram): unknown verb '\(firstArg)'\nTry '\(kProgram) --help'.\n")
    exit(1)
}

do {
    try verb.run(Array(arguments.dropFirst()))
    exit(0)
} catch let PDFUtilError.usage(message) {
    writeErr("\(kProgram) \(verb.name): \(message)\nTry '\(kProgram) \(verb.name) --help'.\n")
    exit(1)
} catch let PDFUtilError.processing(message) {
    writeErr("\(kProgram) \(verb.name): \(message)\n")
    exit(2)
} catch {
    writeErr("\(kProgram) \(verb.name): \(error.localizedDescription)\n")
    exit(2)
}
