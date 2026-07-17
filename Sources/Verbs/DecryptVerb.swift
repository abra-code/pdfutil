// Verbs/DecryptVerb.swift - `pdfutil decrypt`: remove password protection
// (structure-preserving).

import Foundation

private let decryptUsage = """
Usage: pdfutil decrypt --password PW [options] <in.pdf>

Open an encrypted PDF with its password and re-save it with no encryption.
Structure-preserving: annotations, links, outline, and form fields are kept.

The password may be given inline (--password) or read from standard input
(--password-stdin), so it need not appear in the process arguments. Exactly one
of the two is required.

Options:
      --password PW     Password for the encrypted PDF
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
    guard let password = common.password else {
        throw PDFUtilError.usage("--password or --password-stdin is required")
    }
    try decryptDocument(path: scanner.positionals[0], output: common.output,
                        force: common.force, password: password)
}
