// Core/TextCore.swift - text-layer extraction. Page-scoped (never the whole
// document at once) so memory stays flat on large files and page ranges are
// honored. Shared by the `text` verb and, later, the MCP `pdf_text` tool.

import Foundation
import PDFKit

// Extract text from the given pages (0-based; nil = all pages). Pages are joined
// with a newline, or a form-feed page break when requested. Throws .processing
// when no selected page carries an extractable text layer.
func extractText(doc: PDFDocument, pages: [Int]?, pageBreaks: Bool) throws -> String {
    let indices = pages ?? Array(0..<doc.pageCount)
    var parts: [String] = []
    parts.reserveCapacity(indices.count)
    var anyText = false

    for idx in indices {
        let pageText: String = autoreleasepool {
            guard let page = doc.page(at: idx) else { return "" }
            return page.string ?? ""
        }
        // Trimmed test, so a whitespace-only layer counts as "no text" here and
        // agrees with the `info` verb's hasText.
        if !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            anyText = true
        }
        parts.append(pageText)
    }

    guard anyText else {
        throw PDFUtilError.processing("no extractable text")
    }

    let separator = pageBreaks ? "\u{0C}\n" : "\n"
    return parts.joined(separator: separator)
}
