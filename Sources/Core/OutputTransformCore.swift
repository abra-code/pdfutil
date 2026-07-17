// Core/OutputTransformCore.swift - the linearize and pdfa verbs: thin callers of
// the redraw engine that only add an auxiliary context key. Both redraw the
// document (annotations, links, outline, and form fields are not carried over);
// the source Info metadata is carried across.

import Foundation
import CoreGraphics

// Redraw the document with `extra` merged into the auxiliary context dictionary
// (on top of the carried-over metadata). No filter, no overlay.
private func redrawWithAux(path: String, output: String?, force: Bool,
                           password: String?, extra: [CFString: Any]) throws {
    let cgDoc = try openCGPDF(path: path, password: password)
    guard cgDoc.numberOfPages > 0 else {
        throw PDFUtilError.processing("PDF has no pages: \(path)")
    }
    var aux = extra
    if let doc = try? openPDF(path: path, password: password) {
        for (key, value) in metadataContextInfo(from: doc) { aux[key] = value }
    }
    try writeAtomically(to: output, force: force, inPlaceOf: path) { tmpURL in
        try redraw(document: cgDoc, to: tmpURL, auxiliaryInfo: aux, filter: nil)
    }
}

// Rewrite the PDF in linearized ("fast web view") form.
func linearizeDocument(path: String, output: String?, force: Bool, password: String?) throws {
    try redrawWithAux(path: path, output: output, force: force, password: password,
                      extra: [kCGPDFContextCreateLinearizedPDF: true])
}

// Rewrite the PDF as PDF/A (PDF/A-2B via Apple's writer; see the verb help).
func pdfaDocument(path: String, output: String?, force: Bool, password: String?) throws {
    try redrawWithAux(path: path, output: output, force: force, password: password,
                      extra: [kCGPDFContextCreatePDFA: true])
}
