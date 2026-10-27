import Foundation

/// An idea or a bug sent from the app as an issue of the fork on GitHub: created with the GitHub CLI when it is
/// installed and signed in, else prefilled in the browser, where the player signs in to send it. The app itself holds
/// no token and sends nothing on its own.
enum IdeaReport {
    static let repository = "KillianHzr/PokeTokenLBI"

    enum Kind: String, CaseIterable, Sendable {
        case idea, bug

        /// The issue title's prefix, in English like the rest of the repository.
        var prefix: String { self == .idea ? "Idea" : "Bug" }
    }

    /// Beyond this, a prefilled URL may be refused: the body is cut, the browser keeps what fits.
    static let maxBodyLength = 6_000

    static func title(_ kind: Kind, _ text: String) -> String {
        "\(kind.prefix): \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// What the player wrote, then, when they agree, the app's version and macOS's: nothing else about them.
    static func body(_ details: String, system: String?) -> String {
        var body = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if let system { body += (body.isEmpty ? "" : "\n\n") + "---\n" + system }
        body += (body.isEmpty ? "" : "\n\n") + "_Sent from the app._"
        return String(body.prefix(maxBodyLength))
    }

    /// The app's version and commit, and macOS's version.
    static var systemDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let commit = (info["PTBCommitSHA"] as? String).map { " (\($0.prefix(7)))" } ?? ""
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "PokeTokenLBI \(version)\(commit) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    /// The new-issue page of the fork, prefilled.
    static func newIssueURL(title: String, body: String) -> URL? {
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")
        components?.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        return components?.url
    }

    /// The GitHub CLI, when installed.
    static func ghPath() -> String? {
        BinaryLocator.resolve("gh", staticPaths: BinaryLocator.commonToolDirectories().map { "\($0)/gh" })
    }

    /// Whether the CLI is signed in to GitHub.
    static func ghIsSignedIn(_ gh: String) async -> Bool {
        (try? await ProcessRunner.run(binary: gh, arguments: ["auth", "status", "--hostname", "github.com"]).status) == 0
    }

    enum SendError: Error { case failed(String) }

    /// Creates the issue with the CLI: its URL, which `gh issue create` prints last.
    static func create(with gh: String, title: String, body: String) async throws -> URL {
        let result = try await ProcessRunner.run(binary: gh, arguments: ["issue", "create", "--repo", repository,
                                                                         "--title", title, "--body", body])
        let link = result.output.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard result.status == 0, let link, link.hasPrefix("https://"), let url = URL(string: link) else {
            AppLog.write("idea: gh issue create failed (\(result.status)): \(result.output.suffix(300))")
            throw SendError.failed(String(result.output.suffix(300)))
        }
        return url
    }
}
