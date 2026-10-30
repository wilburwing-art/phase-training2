// CSVRows.swift — split CSV text into rows of fields.
//
// Fitbod's export never quotes, so FitbodCSVParser splits on commas. Hevy
// quotes every field and its notes can hold commas and newlines, and Strong
// writes `;` in some locales, so their parsers need real quoting: a field in
// double quotes may contain the delimiter, a newline, or "" for a quote.

import Foundation

enum CSVRows {

    /// Rows of trimmed fields, with fully blank rows dropped. Each row carries
    /// its 1-based line number in the file for error reporting.
    static func parse(_ text: String, delimiter: Character) -> [(line: Int, fields: [String])] {
        var rows: [(Int, [String])] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1, rowStart = 1
        var chars = Array(text)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0

        func endRow() {
            fields.append(field.trimmingCharacters(in: .whitespaces))
            if !(fields.count == 1 && fields[0].isEmpty) { rows.append((rowStart, fields)) }
            fields = []; field = ""
        }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    if c == "\n" { line += 1 }
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                fields.append(field.trimmingCharacters(in: .whitespaces)); field = ""
            } else if c == "\n" || c == "\r\n" {
                endRow(); line += 1; rowStart = line
            } else if c == "\r" {
                endRow(); if i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                line += 1; rowStart = line
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !fields.isEmpty { endRow() }
        return rows
    }
}
