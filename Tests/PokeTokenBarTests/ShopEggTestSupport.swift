@testable import PokeTokenBar

@MainActor
extension CompanionStore {
    /// Buys a Shop egg and uses it from the Bag at once: what buying one did before the egg went to the Bag.
    @discardableResult
    func buyAndUseEgg(_ tier: Rarity?) -> Bool {
        guard buyEgg(tier), let kind = ItemKind(shopEgg: tier) else { return false }
        return useBagEgg(kind)
    }
}
