import XCTest
@testable import PokeTokenBar

/// Lines straight from the evolution data, so the tests walk the same trees the app loads.
private struct TrackLineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        func node(_ id: Int) -> EvoNode {
            EvoNode(speciesID: id, children: (PokemonEvolutionData.children[id] ?? []).map(node))
        }
        return EvoLine(baseID: baseSpeciesID, tree: node(baseSpeciesID), rarity: .common,
                       names: [4: ["en": "Charmander"], 5: ["en": "Charmeleon"], 6: ["en": "Charizard"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Home's evolution track: the stages reached, the coming ones as silhouettes until caught, and where the line goes
/// several ways, every way to its end.
@MainActor
final class EvolutionTrackTests: XCTestCase {
    private func store(_ path: [Int], stage: Int, caught: [[Int]] = []) async throws -> CompanionStore {
        let suite = "Track-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.active = MonState(baseID: path[0], pathIDs: Array(path.prefix(stage + 1)), plannedPathIDs: path,
                                stageIndex: stage, usedAtStage: 0, rarity: .common, totalForms: path.count,
                                nature: .hardy)
        state.dex = caught.enumerated().map { index, chain in
            DexEntry(baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(index)))
        }
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: TrackLineProvider(), fileURL: file, defaults: defaults)
        store.update(todayTokensByProvider: [:], todayDate: "2026-10-22", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
        for _ in 0..<300 where store.currentLine == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(store.currentLine)
        return store
    }

    private func item(_ id: Int, _ caught: Bool) -> BranchEvolutionItem { BranchEvolutionItem(speciesID: id, isCollected: caught) }

    func testALinearLineHeadsForTheGraduationThroughItsComingStages() async throws {
        let charmander = try await store([4, 5, 6], stage: 0, caught: [[4, 5]])
        XCTAssertEqual(charmander.evolutionTrack, [.reached(4, isCurrent: true), .coming(5, isCaught: true),
                                                   .coming(6, isCaught: false), .graduation])
        let charizard = try await store([4, 5, 6], stage: 2)
        XCTAssertEqual(charizard.evolutionTrack, [.reached(4, isCurrent: false), .reached(5, isCurrent: false),
                                                  .reached(6, isCurrent: true), .graduation])
    }

    func testABranchShowsEveryWayToItsEnd() async throws {
        // Eevee: eight ways of one species each.
        let eevee = try await store([133, 197], stage: 0, caught: [[133, 134]])
        let track = eevee.evolutionTrack
        XCTAssertEqual(track.first, .reached(133, isCurrent: true))
        guard case .branch(let paths)? = track.last else { return XCTFail("\(track)") }
        XCTAssertEqual(track.count, 2, "the line stops where it goes several ways")
        XCTAssertEqual(paths.count, 8)
        XCTAssertTrue(paths.allSatisfy { $0.count == 1 })
        XCTAssertEqual(paths.flatMap { $0 }.filter(\.isCollected).map(\.speciesID), [134])

        // Wurmple: the third stage depends on the second.
        let wurmple = try await store([265, 266, 267], stage: 0, caught: [[265, 266, 267]])
        XCTAssertEqual(wurmple.evolutionTrack, [.reached(265, isCurrent: true),
                                                .branch([[item(266, true), item(267, true)],
                                                         [item(268, false), item(269, false)]])])

        // Applin: two ways of one species, one of two.
        let applin = try await store([840, 841], stage: 0)
        XCTAssertEqual(applin.evolutionTrack, [.reached(840, isCurrent: true),
                                               .branch([[item(841, false)], [item(842, false)],
                                                        [item(1011, false), item(1019, false)]])])

        // Ralts: a coming stage, then the branch.
        let ralts = try await store([280, 281, 282], stage: 0)
        XCTAssertEqual(ralts.evolutionTrack, [.reached(280, isCurrent: true), .coming(281, isCaught: false),
                                              .branch([[item(282, false)], [item(475, false)]])])
    }

    func testTheCaptionNamesTheNextStop() async throws {
        let l = L(.en)
        let charmander = try await store([4, 5, 6], stage: 0)
        let names = [5: "Charmeleon"]
        XCTAssertEqual(CompanionHeader.trackCaption(charmander.evolutionTrack, amount: "95M", percent: "24%",
                                                    names: names, l: l), "95M to Charmeleon · 24%")
        let charizard = try await store([4, 5, 6], stage: 2)
        XCTAssertEqual(CompanionHeader.trackCaption(charizard.evolutionTrack, amount: "127.5M", percent: "32%",
                                                    names: names, l: l), "\(l.toGraduation("127.5M")) · 32%")
        let eevee = try await store([133, 197], stage: 0)
        XCTAssertEqual(CompanionHeader.trackCaption(eevee.evolutionTrack, amount: "425M", percent: "32%",
                                                    names: names, l: l), "\(l.toNextEvolution("425M")) · 32%")
    }

    func testNoTrackForTheEgg() throws {
        let suite = "TrackEgg-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.installBaselineSet = true
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: TrackLineProvider(), fileURL: file, defaults: defaults)
        XCTAssertTrue(store.evolutionTrack.isEmpty)
    }
}
