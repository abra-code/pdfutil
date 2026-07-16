// CLI.swift - shared command-line plumbing: the option scanner and the common
// option storage used by many verbs. No verb-specific logic lives here.

import Foundation

// Options shared by many verbs, parsed identically wherever they appear.
struct CommonOptions {
    var output: String?
    var pages: String?      // raw range spec; resolved against the page count later
    var password: String?
    var force = false
    var json = false
}

// A minimal left-to-right token scanner in the style of the predecessor tools.
// Each verb drives its own switch; the scanner handles cursor movement, option
// values, "--", and the unknown-option / positional distinction.
struct ArgScanner {
    let verb: String
    private let tokens: [String]
    private var index = 0
    private(set) var positionals: [String] = []

    init(verb: String, _ tokens: [String]) {
        self.verb = verb
        self.tokens = tokens
    }

    // Next token to examine, advancing the cursor; nil at end of input.
    mutating func nextToken() -> String? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }

    // Consume the value that follows the option `opt`.
    mutating func value(_ opt: String) throws -> String {
        guard index < tokens.count else {
            throw PDFUtilError.usage("option '\(opt)' requires a value")
        }
        defer { index += 1 }
        return tokens[index]
    }

    // Consume an integer value following `opt`.
    mutating func intValue(_ opt: String) throws -> Int {
        let raw = try value(opt)
        guard let n = Int(raw) else {
            throw PDFUtilError.usage("option '\(opt)' requires an integer (got '\(raw)')")
        }
        return n
    }

    // Treat `a` as a positional; reject anything that looks like an unknown option.
    mutating func addPositional(_ a: String) throws {
        if a.hasPrefix("-") && a != "-" {
            throw PDFUtilError.usage("unknown option '\(a)'")
        }
        positionals.append(a)
    }

    // Called on "--": every remaining token is positional, dashes and all.
    mutating func endOptions() {
        while index < tokens.count {
            positionals.append(tokens[index])
            index += 1
        }
    }
}
