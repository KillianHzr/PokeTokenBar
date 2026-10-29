import SwiftUI

struct PokemonNameItem: Hashable, Sendable {
    let resource: PokemonNameResource
    var suffix = ""
}

/// A plain Text preserves wrapping of joined ability names and all parent typography.
@MainActor
struct PokemonNameText: View {
    let items: [PokemonNameItem]
    let language: AppLanguage
    let names: [PokemonNameResource: [String: String]]
    var failed: Set<PokemonNameResource> = []

    init(items: [PokemonNameItem], language: AppLanguage, names: [PokemonNameResource: [String: String]],
         failed: Set<PokemonNameResource> = []) {
        self.items = items
        self.language = language
        self.names = names
        self.failed = failed
    }

    /// Reads only the names of `items`: the view is redrawn when one of them arrives, not when any other does.
    init(items: [PokemonNameItem], language: AppLanguage, names: PokemonNameDisplayStore.Names,
         failed: Set<PokemonNameResource> = []) {
        self.init(items: items, language: language,
                  names: Dictionary(items.compactMap { item in names[item.resource].map { (item.resource, $0) } },
                                    uniquingKeysWith: { first, _ in first }),
                  failed: failed)
    }

    var text: String {
        items.map { item in
            guard let translations = names[item.resource] else {
                return (failed.contains(item.resource)
                        ? PokemonNameLocalization.identifier(item.resource.name) : "…") + item.suffix
            }
            return (language.resolveName(translations)
                    ?? PokemonNameLocalization.identifier(item.resource.name)) + item.suffix
        }.joined(separator: " · ")
    }
    var body: some View { Text(text) }
}

/// Synchronous presentation snapshot: reopening a detail starts with the last translated names.
/// The API client still owns disk caching, request deduplication, and freshness checks.
///
/// Each name is observed on its own: one observed dictionary made every name loaded redraw every view reading any
/// name, and the move list's rows each load theirs as they scroll in, so scrolling it redrew the whole Pokédex page
/// for each row.
@MainActor
final class PokemonNameDisplayStore {
    static let shared = PokemonNameDisplayStore()

    @MainActor @Observable
    final class Entry {
        fileprivate(set) var translations: [String: String]?
    }

    /// Created on first read, so that a view waiting for a name is redrawn when it arrives.
    private var entries: [PokemonNameResource: Entry] = [:]

    private func entry(_ resource: PokemonNameResource) -> Entry {
        if let entry = entries[resource] { return entry }
        let entry = Entry()
        entries[resource] = entry
        return entry
    }

    /// The names known so far, read one resource at a time: `names[resource]`.
    var names: Names { Names(store: self) }

    @MainActor
    struct Names {
        fileprivate let store: PokemonNameDisplayStore

        subscript(resource: PokemonNameResource) -> [String: String]? { store.entry(resource).translations }

        var isEmpty: Bool { store.entries.values.allSatisfy { $0.translations == nil } }
    }

    func load(_ resource: PokemonNameResource, provider: any PokemonNameProviding) async -> Bool {
        do {
            let translations = try await provider.names(for: resource)
            guard !Task.isCancelled else { return false }
            let entry = entry(resource)
            // Written again unchanged, it would redraw the views reading it all the same.
            if entry.translations != translations { entry.translations = translations }
            return true
        } catch {
            return false
        }
    }
}

/// A Pokémon's name in the player's language as its tooltip (PokéAPI's species names, fetched once and cached), in
/// its form; "#25" until it is known. The form's name is loaded too: read from names another view had loaded, it
/// showed the identifier ("Icy Snow") in every language until the Pokédex page was opened.
@MainActor
struct SpeciesNameTooltip: ViewModifier {
    let speciesID: Int
    var form: PokemonForm?
    let language: AppLanguage
    var displayStore = PokemonNameDisplayStore.shared
    var provider: any PokemonNameProviding = PokemonNameClient.shared

    private var resources: [PokemonNameResource] {
        [.init(kind: .pokemonSpecies, name: String(speciesID))]
            + (form.flatMap { PokemonForm.nameResource(speciesID: speciesID, form: $0) }.map { [$0] } ?? [])
    }

    func body(content: Content) -> some View {
        let base = displayStore.names[resources[0]].flatMap(language.resolveName) ?? "#\(speciesID)"
        let name = PokemonForm.displayName(base, speciesID: speciesID, form: form,
                                           label: PokemonForm.label(speciesID: speciesID, form: form, language: language,
                                                                    names: displayStore))
        content
            .hoverTip(HoverTip(id: "species:\(speciesID):\(form?.rawValue ?? "")", title: name))
            .task(id: resources) { await displayStore.loadMissing(resources, provider: provider) }
    }
}

/// Loads the names of a species' forms, for a hover that names them all (a forms goal too long to draw).
@MainActor
struct FormNamesLoader: ViewModifier {
    let speciesID: Int
    var displayStore = PokemonNameDisplayStore.shared
    var provider: any PokemonNameProviding = PokemonNameClient.shared

    func body(content: Content) -> some View {
        content.task(id: speciesID) {
            await displayStore.loadMissing(PokemonForm.nameResources(speciesID: speciesID), provider: provider)
        }
    }
}

extension PokemonNameDisplayStore {
    /// Loads the resources not known yet, one after the other (the client caches each on disk).
    func loadMissing(_ resources: [PokemonNameResource], provider: any PokemonNameProviding) async {
        for resource in resources where names[resource] == nil {
            guard !Task.isCancelled else { return }
            _ = await load(resource, provider: provider)
        }
    }
}

extension View {
    func speciesNameTooltip(_ speciesID: Int, form: PokemonForm? = nil, language: AppLanguage) -> some View {
        modifier(SpeciesNameTooltip(speciesID: speciesID, form: form, language: language))
    }

    func loadsFormNames(_ speciesID: Int) -> some View { modifier(FormNamesLoader(speciesID: speciesID)) }
}

/// Only mounted rows fetch names, following the LazyVStack's lazy row creation.
/// Language changes resolve the already-loaded multilingual response without restarting I/O.
@MainActor
struct PokemonNameLabel: View {
    let items: [PokemonNameItem]
    let language: AppLanguage
    var provider: any PokemonNameProviding = PokemonNameClient.shared
    var displayStore = PokemonNameDisplayStore.shared
    @State private var failed: Set<PokemonNameResource> = []

    init(_ kind: PokemonNameResource.Kind, _ name: String, language: AppLanguage, suffix: String = "") {
        items = [PokemonNameItem(resource: .init(kind: kind, name: name), suffix: suffix)]
        self.language = language
    }

    init(items: [PokemonNameItem], language: AppLanguage) {
        self.items = items
        self.language = language
    }

    var body: some View {
        PokemonNameText(items: items, language: language, names: displayStore.names, failed: failed)
            .task(id: items.map(\.resource)) {
                failed.subtract(items.map(\.resource))
                await withTaskGroup(of: (PokemonNameResource, Bool).self) { group in
                    // A row scrolled back in knows its name already.
                    for resource in Set(items.map(\.resource)) where displayStore.names[resource] == nil {
                        group.addTask { (resource, await displayStore.load(resource, provider: provider)) }
                    }
                    for await (resource, loaded) in group {
                        guard !Task.isCancelled else { return }
                        if !loaded { failed.insert(resource) }
                    }
                }
            }
    }
}
