import Foundation

/// The event eggs' words (`EventEgg`): their names, the banner's wishes during the event, and what it says after.
extension L {
    func eventEggName(_ egg: EventEgg) -> String {
        switch egg {
        case .newYear: return t("새해 알", "New Year Egg", "お正月のタマゴ", "Huevo de Año Nuevo", "Œuf du Nouvel An", "Ovo de Ano Novo",
                                "Neujahrs-Ei", "Новогоднее яйцо")
        case .valentine: return t("밸런타인 알", "Valentine Egg", "バレンタインのタマゴ", "Huevo de San Valentín", "Œuf de la Saint-Valentin",
                                  "Ovo de Dia dos Namorados", "Valentins-Ei", "Валентинково яйцо")
        case .pokemonDay: return t("포켓몬 데이 알", "Pokémon Day Egg", "ポケモンデーのタマゴ", "Huevo del Día de Pokémon",
                                   "Œuf de la Journée Pokémon", "Ovo do Dia Pokémon", "Pokémon-Tag-Ei", "Яйцо Дня покемонов")
        case .easter: return t("부활절 알", "Easter Egg", "イースターのタマゴ", "Huevo de Pascua", "Œuf de Pâques", "Ovo de Páscoa",
                               "Osterei", "Пасхальное яйцо")
        case .halloween: return t("핼러윈 알", "Halloween Egg", "ハロウィンのタマゴ", "Huevo de Halloween", "Œuf d'Halloween",
                                  "Ovo de Halloween", "Halloween-Ei", "Яйцо Хэллоуина")
        case .christmas: return t("크리스마스 알", "Christmas Egg", "クリスマスのタマゴ", "Huevo de Navidad", "Œuf de Noël", "Ovo de Natal",
                                  "Weihnachts-Ei", "Рождественское яйцо")
        case .companion: return t("우정 기념 알", "Friendship Egg", "なかよし記念のタマゴ", "Huevo de la Amistad", "Œuf de l'amitié",
                                  "Ovo da Amizade", "Freundschafts-Ei", "Яйцо дружбы")
        case .spring: return t("봄의 알", "Spring Egg", "春のタマゴ", "Huevo de Primavera", "Œuf du printemps", "Ovo da Primavera",
                               "Frühlings-Ei", "Весеннее яйцо")
        case .summer: return t("여름의 알", "Summer Egg", "夏のタマゴ", "Huevo de Verano", "Œuf de l'été", "Ovo do Verão", "Sommer-Ei",
                               "Летнее яйцо")
        case .autumn: return t("가을의 알", "Autumn Egg", "秋のタマゴ", "Huevo de Otoño", "Œuf de l'automne", "Ovo do Outono", "Herbst-Ei",
                               "Осеннее яйцо")
        case .winter: return t("겨울의 알", "Winter Egg", "冬のタマゴ", "Huevo de Invierno", "Œuf de l'hiver", "Ovo do Inverno", "Winter-Ei",
                               "Зимнее яйцо")
        }
    }

    /// The banner's wish while the event is on.
    func eventEggWish(_ egg: EventEgg) -> String {
        switch egg {
        case .newYear: return t("새해 복 많이 받으세요!", "Happy New Year!", "あけましておめでとう！", "¡Feliz Año Nuevo!", "Bonne année !",
                                "Feliz Ano Novo!", "Frohes neues Jahr!", "С Новым годом!")
        case .valentine: return t("해피 밸런타인!", "Happy Valentine's Day!", "ハッピーバレンタイン！", "¡Feliz San Valentín!",
                                  "Joyeuse Saint-Valentin !", "Feliz Dia dos Namorados!", "Alles Liebe zum Valentinstag!",
                                  "С Днём святого Валентина!")
        case .pokemonDay: return t("즐거운 포켓몬 데이!", "Happy Pokémon Day!", "ハッピーポケモンデー！", "¡Feliz Día de Pokémon!",
                                   "Joyeuse Journée Pokémon !", "Feliz Dia Pokémon!", "Fröhlichen Pokémon-Tag!", "С Днём покемонов!")
        case .easter: return t("즐거운 부활절!", "Happy Easter!", "ハッピーイースター！", "¡Felices Pascuas!", "Joyeuses Pâques !",
                               "Feliz Páscoa!", "Frohe Ostern!", "Счастливой Пасхи!")
        case .halloween: return t("해피 핼러윈!", "Happy Halloween!", "ハッピーハロウィン！", "¡Feliz Halloween!", "Joyeux Halloween !",
                                  "Feliz Halloween!", "Fröhliches Halloween!", "Счастливого Хэллоуина!")
        case .christmas: return t("메리 크리스마스!", "Merry Christmas!", "メリークリスマス！", "¡Feliz Navidad!", "Joyeux Noël !",
                                  "Feliz Natal!", "Frohe Weihnachten!", "С Рождеством!")
        case .companion: return t("우정 기념일 축하해요!", "Happy friendship day!", "なかよし記念日おめでとう！",
                                  "¡Feliz aniversario de amistad!", "Joyeux anniversaire d'amitié !", "Feliz aniversário de amizade!",
                                  "Alles Gute zum Freundschaftstag!", "С днём дружбы!")
        case .spring: return t("봄이 왔어요!", "Spring is here!", "春が来た！", "¡Llegó la primavera!", "Le printemps est là !",
                               "A primavera chegou!", "Der Frühling ist da!", "Пришла весна!")
        case .summer: return t("여름이 왔어요!", "Summer is here!", "夏が来た！", "¡Llegó el verano!", "L'été est là !", "O verão chegou!",
                               "Der Sommer ist da!", "Пришло лето!")
        case .autumn: return t("가을이 왔어요!", "Autumn is here!", "秋が来た！", "¡Llegó el otoño!", "L'automne est là !",
                               "O outono chegou!", "Der Herbst ist da!", "Пришла осень!")
        case .winter: return t("겨울이 왔어요!", "Winter is here!", "冬が来た！", "¡Llegó el invierno!", "L'hiver est là !",
                               "O inverno chegou!", "Der Winter ist da!", "Пришла зима!")
        }
    }

    /// The banner's title in the two weeks after the event.
    func eventEggStillWaiting(_ egg: EventEgg) -> String {
        let name = eventEggName(egg)
        return t("\(name)이 아직 기다리고 있어요", "Your \(name) is still waiting", "\(name)がまだ待っています",
                 "Tu \(name) aún te espera", "Ton \(name) t'attend encore", "Seu \(name) ainda está esperando",
                 "Dein \(name) wartet noch", "«\(name)» всё ещё ждёт вас")
    }

    func eventEggBody(_ egg: EventEgg) -> String {
        let name = eventEggName(egg)
        return t("\(name)이 기다리고 있어요. 무엇이 태어날까요?", "Your \(name) is waiting. What will hatch from it?",
                 "\(name)が待っています。なにが生まれるかな？", "Tu \(name) te espera. ¿Qué saldrá de él?",
                 "Ton \(name) t'attend. Qu'est-ce qui va en sortir ?", "Seu \(name) está esperando. O que vai sair dele?",
                 "Dein \(name) wartet. Was wohl daraus schlüpft?", "Вас ждёт «\(name)». Кто из него вылупится?")
    }

    var eventEggClaim: String {
        t("받기", "Take it", "受け取る", "Recogerlo", "Le prendre", "Pegar", "Nehmen", "Забрать")
    }

    func eventEggClaimed(_ egg: EventEgg) -> String {
        let name = eventEggName(egg)
        return t("\(name)을 가방에 넣었어요. 원할 때 써 보세요.", "The \(name) is in your Bag: use it whenever you like.",
                 "\(name)をバッグに入れました。好きなときに使ってね。", "El \(name) está en tu Bolsa: úsalo cuando quieras.",
                 "L'\(name) est dans ton Sac : utilise-le quand tu veux.", "O \(name) está na sua Bolsa: use quando quiser.",
                 "Das \(name) ist in deinem Beutel: Nutze es, wann du willst.", "«\(name)» в вашей сумке: используйте, когда захотите.")
    }

    /// The Bag's description: when it came, and that it sends the Pokémon off for it.
    func eventEggDescription(_ egg: EventEgg) -> String {
        let name = eventEggName(egg)
        return t("\(name). 지금 포켓몬을 놓아주고 이 알을 받아요. 무엇이 태어날지는 비밀이에요.",
                 "The \(name). Send off your current Pokémon for it; what hatches is a surprise.",
                 "\(name)。いまのポケモンを手放してこのタマゴにします。なにが生まれるかはお楽しみ。",
                 "El \(name). Suelta a tu Pokémon actual por él; lo que salga es una sorpresa.",
                 "L'\(name). Laisse partir ton Pokémon actuel contre lui ; ce qui en sortira est une surprise.",
                 "O \(name). Solte seu Pokémon atual por ele; o que sair é surpresa.",
                 "Das \(name). Gib dein aktuelles Pokémon dafür ab; was schlüpft, ist eine Überraschung.",
                 "«\(name)». Отпустите текущего покемона ради него; кто вылупится, это сюрприз.")
    }
}
