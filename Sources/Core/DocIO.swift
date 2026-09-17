// Core/DocIO.swift - the core error type and the document open/save helpers used
// by every verb. Nothing here prints or exits; callers translate PDFUtilError
// into the exit-code contract (usage -> 1, processing -> 2).

import Foundation
import PDFKit
import CoreGraphics

enum PDFUtilError: Error {
    case usage(String)
    case processing(String)
}

// Open a PDF with PDFKit, applying a password when the document is locked.
// Distinguishes "locked, no password" from "locked, wrong password" from "not a
// readable PDF", mirroring pdftext's care with these cases.
func openPDF(path: String, password: String?) throws -> PDFDocument {
    guard FileManager.default.fileExists(atPath: path) else {
        throw PDFUtilError.processing("file not found: \(path)")
    }
    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
        throw PDFUtilError.processing("cannot open PDF: \(path)")
    }
    if doc.isLocked {
        if let password = password {
            guard doc.unlock(withPassword: password) else {
                throw PDFUtilError.processing("incorrect password: \(path)")
            }
        } else {
            throw PDFUtilError.processing("PDF is password-protected (use --password): \(path)")
        }
    } else if doc.isEncrypted, let password = password {
        // Opens without a password but carries permission restrictions. The
        // owner password lifts them; unlocking an already-open document returns
        // true for any password, so a wrong one simply leaves the restrictions
        // in place for requirePermission to report.
        _ = doc.unlock(withPassword: password)
    }
    return doc
}

// Open a PDF with CoreGraphics (needed for the PDF version and as a render
// fallback). Same password handling as openPDF.
func openCGPDF(path: String, password: String?) throws -> CGPDFDocument {
    guard FileManager.default.fileExists(atPath: path) else {
        throw PDFUtilError.processing("file not found: \(path)")
    }
    guard let doc = CGPDFDocument(URL(fileURLWithPath: path) as CFURL) else {
        throw PDFUtilError.processing("cannot open PDF: \(path)")
    }
    if doc.isEncrypted && !doc.isUnlocked {
        if let password = password {
            guard doc.unlockWithPassword(password) else {
                throw PDFUtilError.processing("incorrect password: \(path)")
            }
        } else {
            throw PDFUtilError.processing("PDF is password-protected (use --password): \(path)")
        }
    }
    return doc
}

// Refuse an edit the document's permissions forbid, before making it.
//
// PDFKit enforces a protected PDF's permissions on every edit, but only by
// logging a line and skipping the change: removePage(at:), PDFPage.rotation,
// documentAttributes, addAnnotation and the widget value setters all return
// nothing. Without this check a refused edit is saved as an unchanged copy and
// reported as a success. Measured against qpdf-restricted copies of the
// fixtures (macOS 26): page removal and rotation need assembly, document
// attributes need changes, a new annotation needs commenting, and a form value
// needs form-field entry. Setting a page box, flattening and OCR embedding were
// not refused. These are PDFKit's flags, not the raw /P bits: PDFKit reports
// changes as allowed when only assembly is, and then applies the attributes.
//
// Opening with the owner password lifts every restriction, and these flags
// then read true.
func requirePermission(_ allowed: Bool, _ what: String, in doc: PDFDocument) throws {
    guard !allowed else { return }
    let name = doc.documentURL?.path ?? "the PDF"
    throw PDFUtilError.processing("\(name): its permissions do not allow \(what); nothing was saved. Open it with the owner password, or remove the restrictions with `pdfutil decrypt` (no password is needed when the PDF opens without one) and run this again")
}

// Save a PDFDocument under the overwrite policy (decision 6): a named output that
// already exists is refused unless force; with no output the input is edited in
// place. In every case we write to a sibling temp file and then atomically
// replace, so PDFKit never writes over a file it is lazily reading.
//
// `password` is the password `doc` was opened with (nil when it opened without
// one, or is a new document). The written file must open with it, or with the
// user password the write options set; otherwise nothing is saved. PDFKit keeps
// an opened document's encryption when it re-saves it, and for a PDF whose
// permission value (/P) is stored as a positive number - legal to read, but not
// the form the standard writes - it rewrites /P and keeps the old /O and /U
// entries. The password check depends on /P, so the saved copy no longer opens
// with any password, including the empty one the original opened with.
func savePDF(_ doc: PDFDocument,
             to output: String?,
             writeOptions: [PDFDocumentWriteOption: Any] = [:],
             force: Bool,
             inPlaceOf inputPath: String,
             password: String?) throws {
    let fm = FileManager.default
    let destPath = output ?? inputPath
    let destURL = URL(fileURLWithPath: destPath).standardizedFileURL
    let destExists = fm.fileExists(atPath: destURL.path)

    if output != nil && destExists && !force {
        throw PDFUtilError.processing("output exists: \(destPath) (use --force to overwrite)")
    }

    let dir = destURL.deletingLastPathComponent()
    let tmpURL = dir.appendingPathComponent(".pdfutil-" + UUID().uuidString + ".pdf")

    guard doc.write(to: tmpURL, withOptions: writeOptions) else {
        try? fm.removeItem(at: tmpURL)
        throw PDFUtilError.processing("failed to write PDF: \(destPath)")
    }

    let expectedPassword = (writeOptions[.userPasswordOption] as? String) ?? password
    if let problem = writtenPDFProblem(tmpURL, password: expectedPassword, destPath: destPath) {
        try? fm.removeItem(at: tmpURL)
        throw PDFUtilError.processing(problem)
    }

    do {
        if destExists {
            _ = try fm.replaceItemAt(destURL, withItemAt: tmpURL)
        } else {
            try fm.moveItem(at: tmpURL, to: destURL)
        }
    } catch {
        try? fm.removeItem(at: tmpURL)
        throw PDFUtilError.processing("failed to save output: \(destPath)")
    }
}

// Why the PDF just written to `url` cannot be delivered, or nil when it opens
// (with `password`, if it is locked). A separate function so the reopened
// document is released before the file is moved into place.
private func writtenPDFProblem(_ url: URL, password: String?, destPath: String) -> String? {
    autoreleasepool {
        guard let written = PDFDocument(url: url) else {
            return "failed to write PDF: \(destPath) (the written file does not open)"
        }
        if !written.isLocked { return nil }
        if let password = password, written.unlock(withPassword: password) { return nil }
        return "\(destPath): PDFKit wrote a copy that does not open with the original's password, so nothing was saved. This PDF's protection is stored in a form PDFKit cannot re-save. Remove the protection with `pdfutil decrypt` (no password is needed when the PDF opens without one), then run this again"
    }
}

// The overwrite policy for the redraw verbs, which produce their output through a
// CGPDFContext rather than PDFDocument.write. `body` receives a sibling temp URL
// to write into; on success it is atomically put in place (replacing an existing
// file only when force allows it), and on any error the temp file is removed.
//
// `accept` is consulted once `body` has written the temp file and before it is
// put in place. Returning false discards the result and leaves the destination
// exactly as it was; the call returns false so the caller can say so. reduce is
// what needs this: a recompression that produced a BIGGER file has failed at its
// only job, and shipping it is worse than doing nothing. Deciding after the fact
// rather than predicting is the point - whether Quartz can shrink a given
// document is not knowable until it has tried.
@discardableResult
func writeAtomically(to output: String?,
                     force: Bool,
                     inPlaceOf inputPath: String,
                     accept: ((URL) -> Bool)? = nil,
                     _ body: (URL) throws -> Void) throws -> Bool {
    let fm = FileManager.default
    let destPath = output ?? inputPath
    let destURL = URL(fileURLWithPath: destPath).standardizedFileURL
    let destExists = fm.fileExists(atPath: destURL.path)

    if output != nil && destExists && !force {
        throw PDFUtilError.processing("output exists: \(destPath) (use --force to overwrite)")
    }

    let dir = destURL.deletingLastPathComponent()
    let tmpURL = dir.appendingPathComponent(".pdfutil-" + UUID().uuidString + ".pdf")

    do {
        try body(tmpURL)
    } catch {
        try? fm.removeItem(at: tmpURL)
        throw error
    }

    if let accept = accept, !accept(tmpURL) {
        try? fm.removeItem(at: tmpURL)
        return false
    }

    do {
        if destExists {
            _ = try fm.replaceItemAt(destURL, withItemAt: tmpURL)
        } else {
            try fm.moveItem(at: tmpURL, to: destURL)
        }
    } catch {
        try? fm.removeItem(at: tmpURL)
        throw PDFUtilError.processing("failed to save output: \(destPath)")
    }
    return true
}
