// Core/SearchCore.swift - "grep for PDFs" over the text layer via PDFKit's
// findString. Shared by the `search` verb and, later, the MCP `pdf_search` tool.

import Foundation
import PDFKit

struct SearchMatch: Codable {
    let page: Int          // 1-based
    let snippet: String
    let bounds: Box
}

// Find every occurrence of `query`, optionally restricted to `pages` (0-based;
// nil = all pages). Each match's snippet is the match extended by `context`
// characters on each side, with runs of whitespace collapsed to single spaces.
func searchDocument(doc: PDFDocument, query: String, pages: [Int]?,
                    caseSensitive: Bool, context: Int) -> [SearchMatch] {
    let pageSet = pages.map { Set($0) }
    let options: NSString.CompareOptions = caseSensitive ? [] : .caseInsensitive
    let selections = doc.findString(query, withOptions: options)

    var matches: [SearchMatch] = []
    for selection in selections {
        autoreleasepool {
            guard let page = selection.pages.first else { return }
            let pageIndex = doc.index(for: page)
            if pageIndex == NSNotFound { return }
            if let set = pageSet, !set.contains(pageIndex) { return }

            let extended = (selection.copy() as? PDFSelection) ?? selection
            if extended !== selection {
                extended.extend(atStart: context)
                extended.extend(atEnd: context)
            }
            let raw = extended.string ?? selection.string ?? query
            let snippet = raw
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            matches.append(SearchMatch(
                page: pageIndex + 1,
                snippet: snippet,
                bounds: Box(selection.bounds(for: page))))
        }
    }
    return matches
}
