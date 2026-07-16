// PageRange.swift - the qpdf-style page-range grammar.
//
//   RANGE := TERM ("," TERM)*
//   TERM  := N | N-M | N-end | end | all
//
// Ranges are 1-based and inclusive. `end` is the last page, `all` is `1-end`.
// Descending terms (`5-2`) are allowed and expand in descending order.
// Duplicates are allowed and meaningful (they let `pages` reorder/repeat).
// Parsing yields 0-based indices; any page < 1 or > pageCount is a usage error
// that names the offending term.

import Foundation

enum PageRange {
    static func parse(_ spec: String, pageCount: Int) throws -> [Int] {
        guard pageCount >= 1 else {
            throw PDFUtilError.processing("document has no pages")
        }

        var oneBased: [Int] = []
        let terms = spec.split(separator: ",", omittingEmptySubsequences: false)

        for termSub in terms {
            let term = termSub.trimmingCharacters(in: .whitespaces)
            if term.isEmpty {
                throw PDFUtilError.usage("empty page-range term in '\(spec)'")
            }
            if term == "all" {
                oneBased.append(contentsOf: 1...pageCount)
                continue
            }

            let endpoints = term.split(separator: "-", omittingEmptySubsequences: false)

            func resolve(_ sub: Substring) throws -> Int {
                let t = sub.trimmingCharacters(in: .whitespaces)
                if t == "end" { return pageCount }
                guard let n = Int(t), n >= 1 else {
                    throw PDFUtilError.usage("invalid page-range term '\(term)' in '\(spec)'")
                }
                return n
            }

            switch endpoints.count {
            case 1:
                let n = try resolve(endpoints[0])
                guard n <= pageCount else {
                    throw PDFUtilError.usage("page \(n) out of range (document has \(pageCount) pages)")
                }
                oneBased.append(n)
            case 2:
                let a = try resolve(endpoints[0])
                let b = try resolve(endpoints[1])
                guard a <= pageCount, b <= pageCount else {
                    throw PDFUtilError.usage("page-range term '\(term)' out of range (document has \(pageCount) pages)")
                }
                if a <= b {
                    oneBased.append(contentsOf: a...b)
                } else {
                    oneBased.append(contentsOf: stride(from: a, through: b, by: -1))
                }
            default:
                throw PDFUtilError.usage("invalid page-range term '\(term)' in '\(spec)'")
            }
        }

        return oneBased.map { $0 - 1 }
    }
}

// Resolve an optional range spec to 0-based indices; a nil spec means all pages.
func resolvePages(_ spec: String?, pageCount: Int) throws -> [Int]? {
    guard let spec = spec else { return nil }
    return try PageRange.parse(spec, pageCount: pageCount)
}
