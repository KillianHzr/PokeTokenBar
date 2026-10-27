import Foundation

/// The excavation (`ItemKind.excavation`): every `rockPerDig` Rock-type species graduated digs up a Fossil Egg, one
/// dig per fossil line, and a Fossil Egg hatches a fossil line the player has not graduated yet, at random. A fossil
/// line graduated some other way (a plain egg) counts as dug: its dig is done with nothing to claim, so the eggs to
/// claim always match the lines missing.
enum FossilDig {
    /// The base of every fossil line, Kanto first: Omanyte, Kabuto, Aerodactyl, Lileep, Anorith, Cranidos, Shieldon,
    /// Tirtouga, Archen, Tyrunt, Amaura, and Galar's four. None has forms of its own, so one egg brings one line.
    static let lines = [138, 140, 142, 345, 347, 408, 410, 564, 566, 696, 698, 880, 881, 882, 883]

    static let rockPerDig = 4
    static var digs: Int { lines.count }

    /// Species that are Rock-type in their usual form or in one of their forms (Hisuian Arcanine, Arceus's Rock form):
    /// a species counts once it graduated in a Rock form.
    static let rockSpecies: [Int] = PokemonAssets.animatedSpeciesIDs.filter { id in
        PokemonTypeData.types(forSpeciesID: id, form: nil).contains(.rock)
            || PokemonForm.forms(speciesID: id).contains { PokemonTypeData.types(forSpeciesID: id, form: $0).contains(.rock) }
    }
}
