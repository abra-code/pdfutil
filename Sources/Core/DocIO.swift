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

// Save a PDFDocument under the overwrite policy (decision 6): a named output that
// already exists is refused unless force; with no output the input is edited in
// place. In every case we write to a sibling temp file and then atomically
// replace, so PDFKit never writes over a file it is lazily reading.
func savePDF(_ doc: PDFDocument,
             to output: String?,
             writeOptions: [PDFDocumentWriteOption: Any] = [:],
             force: Bool,
             inPlaceOf inputPath: String) throws {
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
