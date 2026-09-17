// Verbs/DecryptVerb.swift - `pdfutil decrypt`: remove password protection
// (structure-preserving).

import Foundation

private let decryptUsage = """
Usage: pdfutil decrypt [--password PW] [options] <in.pdf>

Open an encrypted PDF and re-save it with no encryption.
Structure-preserving: annotations, links, outline, and form fields are kept.

A PDF that needs a password to open needs it here too. A PDF that opens
without one - protected only by an owner password that restricts editing,
printing or copying - needs no password: the copy carries no restrictions.

The password may be given inline (--password) or read from standard input
(--password-stdin), so it need not appear in the process arguments. At most
one of the two may be given.

Options:
      --password PW     Password that opens the encrypted PDF
      --password-stdin  Read the password from standard input
  -o, --output FILE     Output file (default: edit in place)
      --force           Overwrite an existing output file
  -h, --help            Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runDecrypt(_ args: [String]) throws {
    var common = CommonOptions()
    var passwordStdin = false
    var scanner = ArgScanner(verb: "decrypt", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(decryptUsage); return
        case "--password": common.password = try scanner.value(a)
        case "--password-stdin": passwordStdin = true
        case "-o", "--output": common.output = try scanner.value(a)
        case "--force": common.force = true
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard scanner.positionals.count == 1 else {
        throw PDFUtilError.usage("expected exactly one input PDF")
    }
    if common.password != nil && passwordStdin {
        throw PDFUtilError.usage("--password and --password-stdin are mutually exclusive")
    }
    if passwordStdin {
        common.password = try readPasswordFromStdin(option: "--password-stdin")
    }
    // No password is a valid request: openPDF refuses a PDF that needs one,
    // with the same message every other verb gives.
    try decryptDocument(path: scanner.positionals[0], output: common.output,
                        force: common.force, password: common.password)
}
