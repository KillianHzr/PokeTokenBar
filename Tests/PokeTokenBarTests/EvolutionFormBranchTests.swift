import XCTest
@testable import PokeTokenBar

/// A coming evolution that brings forms the current stage doesn't show used to appear as one faded sprite of
/// the form already rolled. Like a species branch, its forms now show as candidates: owned ones faded, the
/// others as silhouettes.
@MainActor
final class EvolutionFormBranchTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func line(_ ids: [Int]) -> EvoLine {
        let tree = ids.reversed().reduce(nil as EvoNode?) { child, id in
            EvoNode(speciesID: id, children: child.map { [$0] } ?? [])
        }!
        return EvoLine(baseID: ids[0], tree: tree, rarity: .common,
                       names: Dictionary(uniqueKeysWithValues: ids.map { ($0, ["en": "P\($0)"]) }))
    }

    private func hatched(_ ids: [Int], dex: [DexEntry] = []) async throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-21"
        st.dex = dex
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("form-branch-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: line(ids)), clock: { self.date }, fileURL: url,
                               rng: SeededRNG(seed: 1))
        await s.hatch(baseID: ids[0])
        return s
    }

    func testDudunsparceFormsShowAsCandidatesUnderDunsparce() async throws {
        let s = try await hatched([206, 982])
        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(206), .current),
            EvoLineItem(.branch([
                BranchEvolutionItem(speciesID: 982, isCollected: false, form: PokemonForm("two-segment")),
                BranchEvolutionItem(speciesID: 982, isCollected: false, form: PokemonForm("three-segment")),
            ]), .future),
        ])
    }

    func testAnOwnedFormIsShownAndTheOtherStaysASilhouette() async throws {
        let owned = DexEntry(baseID: 206, finalID: 982, chainOrder: [206, 982], rarity: .common, caughtAt: date,
                             form: PokemonForm("two-segment"))
        let s = try await hatched([206, 982], dex: [owned])
        XCTAssertEqual(s.lineNodes.last, EvoLineItem(.branch([
            BranchEvolutionItem(speciesID: 982, isCollected: true, form: PokemonForm("two-segment")),
            BranchEvolutionItem(speciesID: 982, isCollected: false, form: PokemonForm("three-segment")),
        ]), .future))
    }

    /// Shellos already shows its form (west or east), and Gastrodon keeps it: nothing to guess.
    func testAFormAlreadyShownStaysASingleStage() async throws {
        let s = try await hatched([422, 423])
        XCTAssertEqual(s.lineNodes.last, EvoLineItem(.species(423), .future))
    }

    /// The forms can sit two stages ahead: Pichu, Pikachu, then Raichu in its Kanto or Alolan form.
    func testFormsTwoStagesAheadShowAsCandidates() async throws {
        let s = try await hatched([172, 25, 26])
        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(172), .current),
            EvoLineItem(.species(25), .future),
            EvoLineItem(.branch([
                BranchEvolutionItem(speciesID: 26, isCollected: false, form: PokemonForm("normal")),
                BranchEvolutionItem(speciesID: 26, isCollected: false, form: PokemonForm("alola")),
            ]), .future),
        ])
    }
}
