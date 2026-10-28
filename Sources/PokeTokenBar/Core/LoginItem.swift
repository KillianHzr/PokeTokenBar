import Foundation
import ServiceManagement

/// 로그인 시 실행 + **크래시/비정상 종료 시 자동 재실행**(launchd KeepAlive).
///
/// 배경: `SMAppService.mainApp`(로그인아이템)은 **크래시 시 시스템이 재실행하지 않는다**(Apple 명시).
/// 그래서 KeepAlive 를 가진 LaunchAgent 로 대체한다 — launchd 가 워치독으로 동작해 앱이 비정상
/// 종료(크래시·OOM SIGKILL 등 exit≠0)되면 자동 재실행하고, **정상 종료(exit 0: 사용자 종료·업데이트)
/// 시엔 재실행하지 않는다**(`KeepAlive.SuccessfulExit=false`). ThrottleInterval 10s 로 폭주 방지.
///
/// The agent is a classic plist the app writes itself in `~/Library/LaunchAgents`, which launchd loads at login. The
/// `SMAppService.agent` it replaces carried a launch constraint tied to the binary's signature: every ad-hoc rebuild,
/// so every in-app update, broke it ("spawn failed", exit 78, "needs LWCR update") while Settings showed it on, and
/// registering it again did not help. A plain plist has no such constraint.
///
/// Turning it on or off writes or removes the file, for the next login. No `launchctl` call: loading the agent now
/// would start a second instance (`RunAtLoad`), and unloading it would end this one when the agent started it.
@MainActor
enum LoginItem {
    static let label = "io.github.chattymin.poketokenbar.launch"
    /// The `SMAppService` agent of the builds before, unregistered once (`migrateIfNeeded`). Its plist stays in the
    /// bundle (`build-app.sh`) so that it can still be found to unregister.
    static let legacyPlistName = "io.github.chattymin.poketokenbar.login.plist"
    static let legacyLabel = "io.github.chattymin.poketokenbar.login"

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    static func plistURL(in directory: URL) -> URL { directory.appendingPathComponent("\(label).plist") }

    /// 현재 "로그인 시 실행(+크래시 자동 재실행)" 활성 여부: the agent's plist is there.
    static var isEnabled: Bool { enabled(in: defaultDirectory) }

    static func enabled(in directory: URL) -> Bool { FileManager.default.fileExists(atPath: plistURL(in: directory).path) }

    /// The agent: this build's executable, started at login and again after a crash.
    static func agent(executable: String) -> [String: Any] {
        ["Label": label,
         "ProgramArguments": [executable],
         "RunAtLoad": true,
         "KeepAlive": ["SuccessfulExit": false],
         "ThrottleInterval": 10,
         "LimitLoadToSessionType": "Aqua",
         "ProcessType": "Interactive"]
    }

    /// 토글: 켜면 에이전트 plist 를 쓰고, 끄면 지운다(다음 로그인부터). 실패 시 throw(호출부가 표면화).
    static func setEnabled(_ on: Bool, directory: URL = defaultDirectory,
                           executable: String? = Bundle.main.executablePath) throws {
        let url = plistURL(in: directory)
        if on {
            guard let executable else { throw CocoaError(.fileNoSuchFile) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: agent(executable: executable),
                                                          format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Keeps the agent on this build's executable, once the app was moved: a plist naming another path starts nothing.
    static func refreshIfEnabled(directory: URL = defaultDirectory, executable: String? = Bundle.main.executablePath) {
        guard enabled(in: directory), let executable,
              let data = try? Data(contentsOf: plistURL(in: directory)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              (plist["ProgramArguments"] as? [String])?.first != executable else { return }
        do {
            try setEnabled(true, directory: directory, executable: executable)
            AppLog.write("login item: agent pointed at \(executable)")
        } catch {
            AppLog.write("login item refresh failed: \(error)")
        }
    }

    /// The builds before used an `SMAppService` agent, and those before them a login item (`SMAppService.mainApp`):
    /// either one on moves to the plist once, then is unregistered. Not while that old agent started this very process:
    /// unregistering it would end it, and a later launch does it. 멱등(반복 호출 무해).
    static func migrateIfNeeded(directory: URL = defaultDirectory) {
        let legacyAgent = SMAppService.agent(plistName: legacyPlistName)
        let legacyLoginItem = SMAppService.mainApp
        guard legacyAgent.status == .enabled || legacyLoginItem.status == .enabled else { return }
        if !enabled(in: directory) {
            do {
                try setEnabled(true, directory: directory)
            } catch {
                AppLog.write("login item migration failed (old one kept): \(error)")
                return
            }
        }
        guard AppEnv.launchdJobLabel != legacyLabel else { return }
        do {
            if legacyAgent.status == .enabled { try legacyAgent.unregister() }
            if legacyLoginItem.status == .enabled { try legacyLoginItem.unregister() }
            AppLog.write("login item migrated: SMAppService → LaunchAgent plist")
        } catch {
            AppLog.write("login item: old registration not removed: \(error)")
        }
    }
}
