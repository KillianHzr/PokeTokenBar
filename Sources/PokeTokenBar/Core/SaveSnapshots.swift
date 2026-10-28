import Foundation

/// A point-in-time local snapshot of CompanionState, with summary metadata for listing and rollback.
struct SaveSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let fileURL: URL
    let date: Date
    let dexCount: Int
    let lifetimeTokens: Int
    let currentSpeciesID: Int?
    let currentIsShiny: Bool
    let currentForm: PokemonForm?
}

enum SaveSnapshotManager {
    static let snapshotPrefix = "companion-snapshot-"
    static let maxSnapshotsToKeep = 10
    static let minAutoSnapshotInterval: TimeInterval = 12 * 3600 // 12 hours between auto-snapshots

    static var defaultDeviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    static var defaultAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.5.0"
    }

    /// Directory where local snapshots are stored: `<stateDir>/.snapshots/<stateFileName>/`
    static func snapshotsDirectory(for stateURL: URL) -> URL {
        let dir = stateURL.deletingLastPathComponent()
            .appendingPathComponent(".snapshots")
            .appendingPathComponent(stateURL.lastPathComponent, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Generates a snapshot filename for the given timestamp.
    static func snapshotFileName(date: Date) -> String {
        "\(snapshotPrefix)\(secondStamp(date)).json"
    }

    private static func secondStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }

    private static func parseStamp(_ filename: String) -> Date? {
        guard filename.hasPrefix(snapshotPrefix) && filename.hasSuffix(".json") else { return nil }
        var raw = String(filename.dropFirst(snapshotPrefix.count).dropLast(".json".count))
        if let dash = raw.lastIndex(of: "-"), let _ = Int(raw[raw.index(after: dash)...]) {
            raw = String(raw[..<dash])
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.date(from: raw)
    }

    /// The summary of each snapshot file already read, by its path, its modification date and its size: listing
    /// decoded every snapshot in full (about 1.2 MB each, ten of them) on each Settings opening and twice per new
    /// snapshot, on the main thread.
    private struct SummaryKey: Hashable {
        let path: String
        let modified: Date?
        let size: Int?
    }
    nonisolated(unsafe) private static var summaries: [SummaryKey: SaveSnapshot] = [:]
    private static let summariesLock = NSLock()

    /// Lists all available snapshots in chronological order (newest first).
    static func listSnapshots(for stateFileURL: URL) -> [SaveSnapshot] {
        let dir = snapshotsDirectory(for: stateFileURL)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }

        var results: [SaveSnapshot] = []
        for file in files where file.hasPrefix(snapshotPrefix) && file.hasSuffix(".json") {
            let url = dir.appendingPathComponent(file)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let key = SummaryKey(path: url.path, modified: attributes?[.modificationDate] as? Date,
                                 size: (attributes?[.size] as? NSNumber)?.intValue)
            if let known = summariesLock.withLock({ summaries[key] }) {
                results.append(known)
                continue
            }
            guard let summary = readSummary(file: file, url: url) else { continue }
            summariesLock.withLock { summaries[key] = summary }
            results.append(summary)
        }

        return results.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id > $1.id
        }
    }

    /// One snapshot's summary, read from its envelope, or from a bare state for an older snapshot.
    private static func readSummary(file: String, url: URL) -> SaveSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let st: CompanionState
        let date: Date
        if let envelope = try? SaveTransfer.decode(data) {
            st = envelope.state
            date = envelope.exportedAt
        } else if let bare = try? JSONDecoder().decode(CompanionState.self, from: data) {
            st = bare
            date = parseStamp(file) ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        } else {
            return nil
        }
        return SaveSnapshot(id: file, fileURL: url, date: date, dexCount: st.dex.count,
                            lifetimeTokens: st.usedSinceInstall, currentSpeciesID: st.active?.currentID,
                            currentIsShiny: st.active?.displaysShiny ?? false, currentForm: st.active?.spriteForm)
    }

    /// Loads and returns the SaveEnvelope from a snapshot file.
    static func loadEnvelope(from url: URL) throws -> SaveEnvelope {
        let data = try Data(contentsOf: url)
        if let envelope = try? SaveTransfer.decode(data) {
            return envelope
        }
        if let st = try? JSONDecoder().decode(CompanionState.self, from: data) {
            let date = parseStamp(url.lastPathComponent)
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? Date()
            return SaveEnvelope(
                format: SaveEnvelope.formatID,
                schema: SaveEnvelope.schemaVersion,
                appVersion: defaultAppVersion,
                exportedAt: date,
                sourceDevice: defaultDeviceName,
                state: SaveTransfer.sanitized(st)
            )
        }
        throw SaveTransferError.notASaveFile
    }

    /// Loads sanitized CompanionState from a snapshot file.
    static func loadState(from url: URL) -> CompanionState? {
        try? loadEnvelope(from: url).state
    }

    /// Creates a snapshot from the current CompanionState and saves it into the snapshots directory.
    @discardableResult
    static func createSnapshot(
        state: CompanionState,
        for stateFileURL: URL,
        date: Date,
        appVersion: String = defaultAppVersion,
        deviceName: String = defaultDeviceName
    ) throws -> SaveSnapshot {
        let dir = snapshotsDirectory(for: stateFileURL)
        let filename = snapshotFileName(date: date)
        var targetURL = dir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            let base = filename.dropLast(".json".count)
            var counter = 1
            while FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(base)-\(counter).json").path) {
                counter += 1
            }
            targetURL = dir.appendingPathComponent("\(base)-\(counter).json")
        }
        let data = try SaveTransfer.encode(state: state, appVersion: appVersion, deviceName: deviceName, now: date)
        try data.write(to: targetURL, options: .atomic)
        pruneOldSnapshots(for: stateFileURL)
        return SaveSnapshot(
            id: targetURL.lastPathComponent,
            fileURL: targetURL,
            date: date,
            dexCount: state.dex.count,
            lifetimeTokens: state.usedSinceInstall,
            currentSpeciesID: state.active?.currentID,
            currentIsShiny: state.active?.displaysShiny ?? false,
            currentForm: state.active?.spriteForm
        )
    }

    /// Prunes snapshots keeping only the newest `maxSnapshotsToKeep`.
    static func pruneOldSnapshots(for stateFileURL: URL) {
        let snapshots = listSnapshots(for: stateFileURL)
        guard snapshots.count > maxSnapshotsToKeep else { return }
        for old in snapshots.dropFirst(maxSnapshotsToKeep) {
            try? FileManager.default.removeItem(at: old.fileURL)
        }
    }

    /// Returns the most recent valid snapshot, if any.
    static func latestSnapshot(for stateFileURL: URL) -> SaveSnapshot? {
        listSnapshots(for: stateFileURL).first
    }

    /// Loads the latest valid snapshot as CompanionState, if available.
    static func loadLatestValidSnapshot(for stateFileURL: URL) -> CompanionState? {
        guard let latest = latestSnapshot(for: stateFileURL) else { return nil }
        return loadState(from: latest.fileURL)
    }
}
