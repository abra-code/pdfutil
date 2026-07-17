// CLI.swift - shared command-line plumbing: the option scanner and the common
// option storage used by many verbs. No verb-specific logic lives here.

import Foundation

// Parse a strictly-positive, finite number for an option value (--dpi, --scale).
// Finiteness matters: Double("inf") is > 0 and would later trap in an Int() cast
// or drive a runaway allocation.
func positiveDouble(_ raw: String, option: String) throws -> Double {
    guard let value = Double(raw), value > 0, value.isFinite else {
        throw PDFUtilError.usage("\(option) requires a positive number (got '\(raw)')")
    }
    return value
}

// Read a password from standard input (the --password-stdin family), so it never
// appears in the process argument list where `ps` could show it. Consumes all of
// stdin and strips a single trailing newline, matching `printf pw | tool` and
// `echo pw | tool`. An empty read is an error (usually a missing pipe).
func readPasswordFromStdin(option: String) throws -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard var password = String(data: data, encoding: .utf8) else {
        throw PDFUtilError.usage("\(option): standard input is not valid UTF-8")
    }
    if password.hasSuffix("\n") { password.removeLast() }
    if password.hasSuffix("\r") { password.removeLast() }
    guard !password.isEmpty else {
        throw PDFUtilError.usage("\(option): no password read from standard input")
    }
    return password
}

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

    // Append a positional without the leading-dash check, for verbs that take a
    // legitimately dash-prefixed value like a negative rotation angle.
    mutating func addRawPositional(_ a: String) {
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
