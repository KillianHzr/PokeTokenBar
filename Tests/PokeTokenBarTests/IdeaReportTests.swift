import XCTest
@testable import PokeTokenBar

/// The ideas page sends what the player wrote to the fork's issues, through the GitHub CLI or the browser, and
/// nothing else about them unless they agree.
final class IdeaReportTests: XCTestCase {
    func testTitleAndBodyHoldOnlyWhatThePlayerWrote() {
        XCTAssertEqual(IdeaReport.title(.idea, "  A stats page \n"), "Idea: A stats page")
        XCTAssertEqual(IdeaReport.title(.bug, "Badge cut"), "Bug: Badge cut")
        XCTAssertEqual(IdeaReport.body(" Details ", system: nil), "Details\n\n_Sent from the app._")
        XCTAssertEqual(IdeaReport.body("Details", system: "PokeTokenLBI 2.5 · macOS 15.6.0"),
                       "Details\n\n---\nPokeTokenLBI 2.5 · macOS 15.6.0\n\n_Sent from the app._")
        XCTAssertEqual(IdeaReport.body("", system: nil), "_Sent from the app._")
        XCTAssertEqual(IdeaReport.body(String(repeating: "a", count: 9_000), system: nil).count, IdeaReport.maxBodyLength)
        XCTAssertTrue(IdeaReport.systemDescription.contains("macOS "))
    }

    /// The prefilled page of the fork, every character escaped.
    func testTheNewIssuePageIsPrefilled() throws {
        let url = try XCTUnwrap(IdeaReport.newIssueURL(title: "Idea: Æ & ?", body: "a=b\n#1"))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/KillianHzr/PokeTokenLBI/issues/new?"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "Idea: Æ & ?")
        XCTAssertEqual(items.first { $0.name == "body" }?.value, "a=b\n#1")
    }

    private func fakeGH(_ script: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fake-gh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("gh").path
        try ("#!/bin/sh\n" + script).write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    /// `gh issue create` prints the issue's URL last; its arguments name the fork, the title and the body.
    func testTheCLICreatesTheIssueAndGivesItsURL() async throws {
        let argsFile = FileManager.default.temporaryDirectory.appendingPathComponent("gh-args-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: argsFile) }
        let gh = try fakeGH("printf '%s\\n' \"$@\" > '\(argsFile.path)'\necho 'Creating issue in KillianHzr/PokeTokenLBI'\necho\necho 'https://github.com/KillianHzr/PokeTokenLBI/issues/99'\n")
        let url = try await IdeaReport.create(with: gh, title: "Idea: X", body: "Body")
        XCTAssertEqual(url.absoluteString, "https://github.com/KillianHzr/PokeTokenLBI/issues/99")
        let args = try String(contentsOf: argsFile, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(args, ["issue", "create", "--repo", "KillianHzr/PokeTokenLBI", "--title", "Idea: X", "--body", "Body"])
    }

    func testAFailingCLIThrowsAndASignedOutOneIsNotUsed() async throws {
        let failing = try fakeGH("echo 'HTTP 401' >&2\nexit 1\n")
        do {
            _ = try await IdeaReport.create(with: failing, title: "Idea: X", body: "Body")
            XCTFail("a failed create must throw")
        } catch IdeaReport.SendError.failed(let output) {
            XCTAssertTrue(output.contains("401"))
        }
        let signedOut = await IdeaReport.ghIsSignedIn(failing)
        XCTAssertFalse(signedOut)
        let signedIn = await IdeaReport.ghIsSignedIn(try fakeGH("exit 0\n"))
        XCTAssertTrue(signedIn)
    }
}
