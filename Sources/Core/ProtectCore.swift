// Core/ProtectCore.swift - the encrypt and decrypt verbs (structure-preserving).
// Both go through PDFKit's writer: encrypt adds password/permission write
// options; decrypt re-saves with none. Annotations, links, outline, and form
// fields survive.

import Foundation
import PDFKit

// Map an --allow FLAGS spec to the OR'd PDFAccessPermissions raw value. The flag
// names are the same short names the info verb prints (kPermissionFlags). With no
// spec (nil), every permission is allowed.
func accessPermissionRaw(fromAllow spec: String?) throws -> UInt {
    guard let spec = spec else {
        return kPermissionFlags.reduce(0) { $0 | $1.0.rawValue }
    }
    let names = spec.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty }
    guard !names.isEmpty else {
        throw PDFUtilError.usage("--allow expects a comma-separated flag list")
    }
    var raw: UInt = 0
    for name in names {
        guard let entry = kPermissionFlags.first(where: { $0.1 == name }) else {
            let valid = kPermissionFlags.map { $0.1 }.joined(separator: ", ")
            throw PDFUtilError.usage("unknown permission '\(name)' (valid: \(valid))")
        }
        raw |= entry.0.rawValue
    }
    return raw
}

// Encrypt: at least one of the two passwords is required. When only one kind is
// given it is used for both write options (so the file always has an owner and a
// user password). Permissions restrict what a user-password holder may do; an
// owner-password holder is unrestricted (this is standard PDF behavior).
func encryptDocument(path: String, output: String?, force: Bool,
                     userPassword: String?, ownerPassword: String?, allow: String?) throws {
    guard userPassword != nil || ownerPassword != nil else {
        throw PDFUtilError.usage("at least one of --user-password / --owner-password is required")
    }
    let doc = try openPDF(path: path, password: nil)
    let user = userPassword ?? ownerPassword!
    let owner = ownerPassword ?? userPassword!
    let raw = try accessPermissionRaw(fromAllow: allow)

    let options: [PDFDocumentWriteOption: Any] = [
        .userPasswordOption: user,
        .ownerPasswordOption: owner,
        .accessPermissionsOption: NSNumber(value: raw),
    ]
    try savePDF(doc, to: output, writeOptions: options, force: force, inPlaceOf: path)
}

// Decrypt: open with the password and write out an unencrypted copy.
//
// A plain re-save is not enough: PDFKit keeps the opened document's encryption
// dictionary and the output stays encrypted (verified with qpdf). We instead
// rebuild a fresh PDFDocument from page copies - a new document carries no
// encryption - and reattach the outline and Info attributes. Page-level
// annotations (including form widgets) travel with the page copies; a
// document-level AcroForm dictionary, if any, is not carried over.
func decryptDocument(path: String, output: String?, force: Bool, password: String) throws {
    let src = try openPDF(path: path, password: password)
    let out = PDFDocument()
    for i in 0..<src.pageCount {
        try autoreleasepool {
            guard let page = src.page(at: i)?.copy() as? PDFPage else {
                throw PDFUtilError.processing("cannot copy page \(i + 1) of \(path)")
            }
            out.insert(page, at: out.pageCount)
        }
    }
    if let root = src.outlineRoot { out.outlineRoot = root }
    if let attrs = src.documentAttributes { out.documentAttributes = attrs }
    try savePDF(out, to: output, writeOptions: [:], force: force, inPlaceOf: path)
}
