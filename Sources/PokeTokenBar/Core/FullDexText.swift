import Foundation

/// The words of the whole Pokédex (`FullDexView`): its views and what a species not caught says.
extension L {
    func dexScope(_ scope: PopoverNavigation.DexScope) -> String {
        switch scope {
        case .all: return t("전체", "All", "すべて", "Todos", "Tous", "Todos", "Alle", "Все")
        case .caught: return t("보유", "Caught", "入手済み", "Obtenidos", "Obtenus", "Obtidos", "Gefangen", "Пойманы")
        case .missing: return t("미보유", "Missing", "未入手", "Faltan", "Manquants", "Faltando", "Fehlend", "Не хватает")
        }
    }

    func dexMissingHint(_ id: Int) -> String {
        t("#\(id) 아직 도감에 없어요", "#\(id) not in your Pokédex yet", "#\(id) まだ図鑑にいません", "#\(id) aún no está en tu Pokédex",
          "#\(id) pas encore dans ton Pokédex", "#\(id) ainda não está na sua Pokédex", "#\(id) noch nicht in deinem Pokédex",
          "#\(id) ещё нет в покедексе")
    }

    func dexShinySpecies(_ count: Int) -> String {
        let one = count == 1
        return t("이로치 \(count)종", "\(count) shiny species", "色違い\(count)種",
                 one ? "1 especie variocolor" : "\(count) especies variocolor",
                 one ? "1 espèce chromatique" : "\(count) espèces chromatiques",
                 one ? "1 espécie brilhante" : "\(count) espécies brilhantes",
                 one ? "1 schillernde Art" : "\(count) schillernde Arten", "Сияющих видов: \(count)")
    }

    func dexPercent(_ percent: Int) -> String {
        t("\(percent)% 완성", "\(percent)% complete", "\(percent)%完成", "\(percent) % completado", "\(percent) % complété",
          "\(percent)% completo", "\(percent) % vollständig", "Собрано \(percent)%")
    }
}
