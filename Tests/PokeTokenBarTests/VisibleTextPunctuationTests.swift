import XCTest

/// The texts a player reads carry no em dash, no en dash and no curly or angle quotes: the project writes straight
/// quotes and plain punctuation in every language. The audit of 2026-10-28 found 142 em dashes, 34 en dashes, 47 pairs
/// of « » and 3 of „ “ in them, with no test.
final class VisibleTextPunctuationTests: XCTestCase {
    /// Log lines (`AppLog`, the crash log) are for the developer and keep their own style.
    private static let logFiles: Set<String> = ["CrashReporter.swift", "AppLog.swift"]
    private static let banned: Set<Character> = ["\u{2014}", "\u{2013}", "\u{00AB}", "\u{00BB}", "\u{201E}", "\u{201C}"]

    func testNoDashOrCurlyQuoteInAVisibleString() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar")
        var offenders: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" && !Self.logFiles.contains(url.lastPathComponent) {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where !line.contains("AppLog.") {
                if Self.literals(in: String(line)).contains(where: { $0.contains(where: Self.banned.contains) }) {
                    offenders.append("\(url.lastPathComponent):\(index + 1)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "use a colon, a comma or straight quotes: \(offenders.joined(separator: ", "))")
    }

    /// The string literals of one line, outside its `//` comment.
    static func literals(in line: String) -> [String] {
        var literals: [String] = []
        var current = ""
        var inString = false
        var escaped = false
        var previous: Character = " "
        for character in line {
            if inString {
                if escaped { escaped = false; current.append(character); continue }
                if character == "\\" { escaped = true; current.append(character); continue }
                if character == "\"" { inString = false; literals.append(current); current = ""; continue }
                current.append(character)
            } else {
                if character == "/" && previous == "/" { break }
                if character == "\"" { inString = true }
                previous = character
            }
        }
        return literals
    }

    func testTheScanReadsLiteralsNotComments() {
        XCTAssertEqual(Self.literals(in: #"t("a \"b\" c", "d") // "e""#), [#"a \"b\" c"#, "d"])
        XCTAssertEqual(Self.literals(in: "// \u{2014} \"x\""), [])
    }
}
