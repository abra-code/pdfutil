// Core/OcrCore.swift - optical character recognition via the Vision framework.
// Every page is rasterized (OCR always works on pixels; the `text` verb is the
// text-layer reader) and recognized text is returned in reading order. The
// --searchable path instead hands the whole document to PDFKit's built-in OCR.

import Foundation
import PDFKit
import Vision
import CoreGraphics

// Recognize text on one rendered page image, returned as lines in reading order:
// top to bottom (boundingBox.midY descending), then left to right (midX
// ascending) for observations sharing a line (midY within 0.01 normalized).
func recognizeText(in image: CGImage, languages: [String], fast: Bool) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = fast ? .fast : .accurate
    request.usesLanguageCorrection = true
    if !languages.isEmpty {
        request.recognitionLanguages = languages
    }

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
        try handler.perform([request])
    } catch {
        throw PDFUtilError.processing("text recognition failed: \(error.localizedDescription)")
    }

    let observations = request.results ?? []
    // Reading order: quantize midY into ~0.01-tall row bands, then sort by band
    // (top first) and midX (left first). Quantizing up front keeps the comparator
    // a strict weak ordering (transitive), so the output order is deterministic;
    // a raw abs-tolerance compare is not transitive across a band boundary.
    func band(_ o: VNRecognizedTextObservation) -> Int { Int((o.boundingBox.midY / 0.01).rounded()) }
    let ordered = observations.sorted { a, b in
        let ba = band(a), bb = band(b)
        if ba != bb { return ba > bb }
        return a.boundingBox.midX < b.boundingBox.midX
    }
    return ordered.compactMap { $0.topCandidates(1).first?.string }
}

// OCR the selected pages (0-based) and join them. Pages are separated by a
// form-feed page break (always on, so multi-page output is unambiguous).
func ocrText(doc: PDFDocument, pages: [Int], dpi: Double,
             languages: [String], fast: Bool) throws -> String {
    var parts: [String] = []
    parts.reserveCapacity(pages.count)

    for idx in pages {
        let pageText = try autoreleasepool { () throws -> String in
            guard let page = doc.page(at: idx) else {
                throw PDFUtilError.processing("cannot read page \(idx + 1)")
            }
            let image = try renderPageToImage(page, dpi: dpi, transparent: false)
            return try recognizeText(in: image, languages: languages, fast: fast)
                .joined(separator: "\n")
        }
        parts.append(pageText)
    }
    return parts.joined(separator: "\u{0C}\n")
}

// Embed a searchable text layer using PDFKit's own OCR, then save. This is
// Apple's OCR-embed path; the manual --dpi/--lang/--fast options do not apply to
// it (PDFKit chooses the recognition parameters).
func ocrSearchable(doc: PDFDocument, output: String, force: Bool, inPlaceOf path: String) throws {
    try savePDF(doc, to: output, writeOptions: [.saveTextFromOCROption: true],
                force: force, inPlaceOf: path)
}
