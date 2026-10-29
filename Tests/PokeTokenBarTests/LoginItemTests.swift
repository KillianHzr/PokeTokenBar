import XCTest
@testable import PokeTokenBar

/// Launch at login is a LaunchAgent plist the app writes itself (`LoginItem`): the `SMAppService` agent before it broke
/// at every ad-hoc rebuild (launchd "spawn failed", exit 78). Always in a temporary folder, never the user's.
@MainActor
final class LoginItemTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("launch-agents-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func plist(in directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: LoginItem.plistURL(in: directory))
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testTurningItOnWritesTheAgentAndOffRemovesIt() throws {
        let dir = try folder()
        let app = "/Applications/PokeTokenLBI.app/Contents/MacOS/PokeTokenLBI"
        XCTAssertFalse(LoginItem.enabled(in: dir))
        try LoginItem.setEnabled(true, directory: dir, executable: app)
        XCTAssertTrue(LoginItem.enabled(in: dir))
        let agent = try plist(in: dir)
        XCTAssertEqual(agent["Label"] as? String, LoginItem.label)
        XCTAssertNotEqual(LoginItem.label, LoginItem.legacyLabel, "never the label of the old registration")
        XCTAssertEqual(agent["ProgramArguments"] as? [String], [app])
        XCTAssertEqual(agent["RunAtLoad"] as? Bool, true)
        XCTAssertEqual((agent["KeepAlive"] as? [String: Bool])?["SuccessfulExit"], false, "a crash restarts it, a quit not")
        try LoginItem.setEnabled(false, directory: dir)
        XCTAssertFalse(LoginItem.enabled(in: dir))
        try LoginItem.setEnabled(false, directory: dir)
    }

    /// The app moved: the agent follows the executable; one already right is left as it is.
    func testTheAgentFollowsTheExecutable() throws {
        let dir = try folder()
        try LoginItem.setEnabled(true, directory: dir, executable: "/Old/PokeTokenLBI.app/Contents/MacOS/PokeTokenLBI")
        LoginItem.refreshIfEnabled(directory: dir, executable: "/Applications/PokeTokenLBI.app/Contents/MacOS/PokeTokenLBI")
        XCTAssertEqual(try plist(in: dir)["ProgramArguments"] as? [String],
                       ["/Applications/PokeTokenLBI.app/Contents/MacOS/PokeTokenLBI"])
        let off = try folder()
        LoginItem.refreshIfEnabled(directory: off, executable: "/Applications/PokeTokenLBI.app/Contents/MacOS/PokeTokenLBI")
        XCTAssertFalse(LoginItem.enabled(in: off), "turned off, it stays off")
    }
}
