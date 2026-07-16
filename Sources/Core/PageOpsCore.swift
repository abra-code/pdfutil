// Core/PageOpsCore.swift - structure-preserving page operations shared by the
// merge, split, and pages verbs. Pages are copied and re-inserted via PDFKit, so
// annotations, links, outline, and form fields survive.

import Foundation
import PDFKit

// Build a new document from copies of the given source pages, in the given order
// (duplicates allowed, which is what lets `pages --extract` reorder and repeat).
func documentFromPages(_ source: PDFDocument, indices: [Int]) throws -> PDFDocument {
    let out = PDFDocument()
    for idx in indices {
        try autoreleasepool {
            guard let page = source.page(at: idx) else {
                throw PDFUtilError.processing("cannot read page \(idx + 1)")
            }
            guard let copy = page.copy() as? PDFPage else {
                throw PDFUtilError.processing("cannot copy page \(idx + 1)")
            }
            out.insert(copy, at: out.pageCount)
        }
    }
    return out
}

// One merge input: a file and an optional page range that binds to it.
struct MergeInput {
    let path: String
    var range: String?
}

// Concatenate the inputs (each restricted to its range, or all pages) into one
// new document. A single password is tried against every locked input.
func mergeDocuments(_ inputs: [MergeInput], password: String?) throws -> PDFDocument {
    let merged = PDFDocument()
    for input in inputs {
        let doc = try openPDF(path: input.path, password: password)
        let indices = try input.range.map { try PageRange.parse($0, pageCount: doc.pageCount) }
            ?? Array(0..<doc.pageCount)
        for idx in indices {
            try autoreleasepool {
                guard let page = doc.page(at: idx), let copy = page.copy() as? PDFPage else {
                    throw PDFUtilError.processing("cannot copy page \(idx + 1) of \(input.path)")
                }
                merged.insert(copy, at: merged.pageCount)
            }
        }
    }
    return merged
}

enum SplitMode {
    case every(Int)
    case chapters
}

// Split a document into parts written as <prefix>-NNN.pdf (1-based, zero-padded).
// Returns the paths written. Each output file is governed by the overwrite policy.
func splitDocument(doc: PDFDocument, mode: SplitMode, prefix: String, force: Bool) throws -> [String] {
    let pageCount = doc.pageCount
    guard pageCount > 0 else { throw PDFUtilError.processing("document has no pages") }

    var starts: [Int]
    switch mode {
    case .every(let n):
        guard n >= 1 else { throw PDFUtilError.usage("--every must be >= 1") }
        starts = Array(stride(from: 0, to: pageCount, by: n))
    case .chapters:
        guard let root = doc.outlineRoot, root.numberOfChildren > 0 else {
            throw PDFUtilError.processing("document has no outline for --chapters")
        }
        var dests: [Int] = []
        for i in 0..<root.numberOfChildren {
            if let page = root.child(at: i)?.destination?.page {
                let idx = doc.index(for: page)
                if idx != NSNotFound { dests.append(idx) }
            }
        }
        guard !dests.isEmpty else {
            throw PDFUtilError.processing("outline has no chapter page destinations")
        }
        var unique = Array(Set(dests)).sorted()
        if unique.first != 0 { unique.insert(0, at: 0) }   // keep any front matter
        starts = unique
    }

    // Name every part up front and enforce the overwrite policy before writing
    // anything, so a collision fails all-or-nothing instead of leaving a partial
    // set of files behind.
    let paths = (0..<starts.count).map { String(format: "%@-%03d.pdf", prefix, $0 + 1) }
    if !force {
        for path in paths where FileManager.default.fileExists(atPath: path) {
            throw PDFUtilError.processing("output exists: \(path) (use --force to overwrite)")
        }
    }

    for (part, start) in starts.enumerated() {
        let end = (part + 1 < starts.count) ? starts[part + 1] : pageCount
        let outDoc = try documentFromPages(doc, indices: Array(start..<end))
        try savePDF(outDoc, to: paths[part], force: force, inPlaceOf: paths[part])
    }
    return paths
}

// Drop the trailing ".pdf" (case-insensitive) to derive a default output prefix.
func stripPDFExtension(_ path: String) -> String {
    path.lowercased().hasSuffix(".pdf") ? String(path.dropLast(4)) : path
}
