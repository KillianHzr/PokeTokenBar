import XCTest
@testable import PokeTokenBar

private struct FormNames: PokemonNameProviding {
    let names: [String: [String: String]]
    func names(for resource: PokemonNameResource) async throws -> [String: String] { names[resource.name] ?? [:] }
}

/// The forms #56 and the catalog left out: Origin Dialga and Palkia, Hoopa Unbound, Bloodmoon Ursaluna, the female
/// Indeedee and Oinkologne, Maushold's two families, Partner Eevee and Alcremie's 63 looks; and the names #55 found
/// shared.
@MainActor
final class NewFormsTests: XCTestCase {
    func testTheNewFormsAreCatalogued() {
        XCTAssertEqual(PokemonForm.forms(speciesID: 483).map(\.rawValue), ["normal", "origin"])
        XCTAssertEqual(PokemonForm.forms(speciesID: 484).map(\.rawValue), ["normal", "origin"])
        XCTAssertEqual(PokemonForm.forms(speciesID: 720).map(\.rawValue), ["confined", "unbound"])
        XCTAssertEqual(PokemonForm.forms(speciesID: 901).map(\.rawValue), ["normal", "bloodmoon"])
        XCTAssertEqual(PokemonForm.forms(speciesID: 876).map(\.rawValue), ["male", "female"])
        XCTAssertEqual(PokemonForm.forms(speciesID: 916).map(\.rawValue), ["male", "female"])
        XCTAssertEqual(PokemonForm.forms(speciesID: 925).map(\.rawValue), ["family-of-four", "family-of-three"])
        XCTAssertEqual(PokemonForm.forms(speciesID: 133).map(\.rawValue), ["normal", "starter"])
        XCTAssertEqual(PokemonForm.forms(speciesID: 869).count, 63)
        XCTAssertEqual(PokemonForm.forms(speciesID: 869).first?.rawValue, "vanilla-cream-strawberry")
        // Eggs of the line bring them.
        XCTAssertEqual(PokemonForm.lineBase(of: 869), 868)
        XCTAssertEqual(PokemonForm.lineBase(of: 901), 216)
        XCTAssertEqual(PokemonForm.lineBase(of: 916), 915)
        XCTAssertEqual(PokemonForm.lineBase(of: 925), 924)
        XCTAssertEqual(PokemonTypeData.types(forSpeciesID: 720, form: PokemonForm("unbound")), [.psychic, .dark])
        XCTAssertEqual(PokemonTypeData.types(forSpeciesID: 720, form: nil), [.psychic, .ghost])
    }

    /// Partner Eevee stays an Eevee; any other Eevee still evolves eight ways.
    func testPartnerEeveeDoesNotEvolve() {
        XCTAssertTrue(PokemonEvolutionData.children(of: 133, form: PokemonForm("starter")).isEmpty)
        XCTAssertEqual(PokemonEvolutionData.children(of: 133, form: PokemonForm("normal")).count, 8)
    }

    /// Showdown's `925` is the Family of Three and `925-four` the Family of Four, PokéAPI's default.
    func testMausholdLoadsEachFamilysOwnFile() {
        func gif(_ form: String?) -> String? {
            SpriteStore.spriteURLs(speciesID: 925, animated: true, shiny: false, form: form.map { PokemonForm($0) })
                .first?.lastPathComponent
        }
        XCTAssertEqual(gif(nil), "925-four.gif")
        XCTAssertEqual(gif("family-of-four"), "925-four.gif")
        XCTAssertEqual(gif("family-of-three"), "925.gif")
        XCTAssertEqual(SpriteStore.spriteURLs(speciesID: 925, animated: false, shiny: false,
                                              form: PokemonForm("family-of-three")).first?.lastPathComponent, "10257.png")
    }

    /// Alcremie's GIFs drop PokéAPI's "-sweet", its PNGs keep it.
    func testAlcremiesGIFsAndPNGsHaveTheirOwnNames() {
        let ruby = PokemonForm("ruby-cream-strawberry")
        XCTAssertEqual(SpriteStore.spriteURLs(speciesID: 869, animated: true, shiny: false, form: ruby).first?.lastPathComponent,
                       "869-ruby-cream-strawberry.gif")
        XCTAssertEqual(SpriteStore.spriteURLs(speciesID: 869, animated: false, shiny: true, form: ruby).first?.lastPathComponent,
                       "869-ruby-cream-strawberry-sweet.png")
        XCTAssertEqual(SpriteStore.spriteURLs(speciesID: 869, animated: false, shiny: false, form: nil).first?.lastPathComponent,
                       "869.png")
    }

    /// Maushold's default used to cache the Family of Three: its files are dropped once and download again.
    func testMausholdsCachedSpritesArePurgedOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maushold-purge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = ["925-a.gif", "925-s.png", "925-sha.gif"], kept = ["924-a.gif", "92-a.gif", "9250-s.png"]
        for name in stale + kept { try Data("x".utf8).write(to: directory.appendingPathComponent(name)) }
        _ = SpriteStore(directory: directory)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertTrue(left.isDisjoint(with: stale), "\(left)")
        XCTAssertTrue(Set(kept).isSubset(of: left), "\(left)")
        try Data("x".utf8).write(to: directory.appendingPathComponent("925-a.gif"))
        _ = SpriteStore(directory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("925-a.gif").path),
                      "a sprite cached after the purge stays")
    }

    /// Names PokéAPI lacks or shares (#55): each Paldean Tauros its breed, Galarian Zen Mode the region's name and the
    /// mode's, Hoopa's forms without the species, Partner Eevee and Maushold's families in every language.
    func testFormsHaveTheirOwnNames() async {
        let store = PokemonNameDisplayStore()
        let provider = FormNames(names: ["10336": ["fr": "Forme de Galar"], "10067": ["fr": "Mode Transe"]])
        _ = await store.load(PokemonNameResource(kind: .pokemonForm, name: "10336"), provider: provider)
        _ = await store.load(PokemonNameResource(kind: .pokemonForm, name: "10067"), provider: provider)
        func label(_ id: Int, _ form: String) -> String? {
            PokemonForm.label(speciesID: id, form: PokemonForm(form), language: .fr, names: store)
        }
        XCTAssertEqual(label(555, "galar-zen"), "Forme de Galar, Mode Transe")
        XCTAssertEqual(label(555, "zen"), "Mode Transe")
        XCTAssertEqual([label(128, "paldea-combat"), label(128, "paldea-blaze"), label(128, "paldea-aqua")],
                       ["Race Combative", "Race Flamboyante", "Race Aquatique"])
        XCTAssertEqual(label(720, "unbound"), "Déchaîné")
        XCTAssertEqual(label(133, "starter"), "Partenaire")
        XCTAssertEqual(label(925, "family-of-three"), "Famille de Trois")
        XCTAssertEqual(label(483, "normal"), L(.fr).normalForm, "Dialga's usual look has no name")
        for language in AppLanguage.allCases {
            let l = L(language)
            let breeds = Set([l.formTaurosCombatBreed, l.formTaurosBlazeBreed, l.formTaurosAquaBreed])
            XCTAssertEqual(breeds.count, 3, "\(language): three breeds, three names")
            XCTAssertNotEqual(l.formFamilyOfFour, l.formFamilyOfThree, "\(language)")
        }
    }
}
