// Verbs/EncryptVerb.swift - `pdfutil encrypt`: add password protection and
// permission restrictions (structure-preserving).

import Foundation

private let encryptUsage = """
Usage: pdfutil encrypt (--user-password PW | --owner-password PW) [options] <in.pdf>

Encrypt a PDF with a user and/or owner password. At least one is required; when
only one is given it is used for both. Structure-preserving: annotations, links,
outline, and form fields are kept.

The user password is required to open the file. The owner password unlocks full
access; a reader who opens with only the user password is limited to --allow.

A password may be given inline (--user-password / --owner-password) or read from
standard input (the matching -stdin flag), so it need not appear in the process
arguments. A password and its -stdin form are mutually exclusive, and at most one
password may be read from stdin.

Options:
      --user-password PW      Password required to open the document
      --owner-password PW     Password granting full (owner) access
      --user-password-stdin   Read the user password from standard input
      --owner-password-stdin  Read the owner password from standard input
      --allow FLAGS           Comma list of permissions granted to user-password
                              readers (default: all). Flags: printing,
                              high-quality-printing, changes, assembly, copying,
                              accessibility, commenting, forms
  -o, --output FILE           Output file (default: edit in place)
      --force                 Overwrite an existing output file
  -h, --help                  Show this help

Note: Apple's writer produces 128-bit AES encryption (revision 4); it cannot
write AES-256. Use qpdf if you need AES-256. Some permission bits are coupled
(granting printing also permits high-quality-printing; copying also permits
accessibility), so the eight flags are not fully independent.

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runEncrypt(_ args: [String]) throws {
    var common = CommonOptions()
    var userPassword: String?
    var ownerPassword: String?
    var userStdin = false
    var ownerStdin = false
    var allow: String?
    var scanner = ArgScanner(verb: "encrypt", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(encryptUsage); return
        case "--user-password": userPassword = try scanner.value(a)
        case "--owner-password": ownerPassword = try scanner.value(a)
        case "--user-password-stdin": userStdin = true
        case "--owner-password-stdin": ownerStdin = true
        case "--allow": allow = try scanner.value(a)
        case "-o", "--output": common.output = try scanner.value(a)
        case "--force": common.force = true
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard scanner.positionals.count == 1 else {
        throw PDFUtilError.usage("expected exactly one input PDF")
    }
    if userStdin && ownerStdin {
        throw PDFUtilError.usage("only one password can be read from standard input")
    }
    if userPassword != nil && userStdin {
        throw PDFUtilError.usage("--user-password and --user-password-stdin are mutually exclusive")
    }
    if ownerPassword != nil && ownerStdin {
        throw PDFUtilError.usage("--owner-password and --owner-password-stdin are mutually exclusive")
    }
    if userStdin { userPassword = try readPasswordFromStdin(option: "--user-password-stdin") }
    if ownerStdin { ownerPassword = try readPasswordFromStdin(option: "--owner-password-stdin") }

    try encryptDocument(path: scanner.positionals[0], output: common.output, force: common.force,
                        userPassword: userPassword, ownerPassword: ownerPassword, allow: allow)
}
