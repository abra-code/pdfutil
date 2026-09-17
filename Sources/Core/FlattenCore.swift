// Core/FlattenCore.swift - flatten a PDF's annotations and form fields into the
// page content (structure-preserving save with burn-in). After flattening, form
// widgets and annotation objects are gone but their appearances are painted into
// the page, so a filled form's values become permanent page content.

import Foundation
import PDFKit

func flattenDocument(path: String, output: String?, force: Bool, password: String?) throws {
    let doc = try openPDF(path: path, password: password)
    try savePDF(doc, to: output, writeOptions: [.burnInAnnotationsOption: true],
                force: force, inPlaceOf: path, password: password)
}
