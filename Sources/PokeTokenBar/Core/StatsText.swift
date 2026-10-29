import Foundation

/// The words of the Stats page (`StatsScreen`).
extension L {
    var statsTitle: String {
        t("통계", "Stats", "統計", "Estadísticas", "Statistiques", "Estatísticas", "Statistiken", "Статистика")
    }
    var statsDayByDay: String {
        t("날짜별", "Day by day", "日ごと", "Día a día", "Jour par jour", "Dia a dia", "Tag für Tag", "По дням")
    }
    var statsMonthByMonth: String {
        t("월별", "Month by month", "月ごと", "Mes a mes", "Mois par mois", "Mês a mês", "Monat für Monat", "По месяцам")
    }
    var statsTokens: String { t("토큰", "Tokens", "トークン", "Tokens", "Tokens", "Tokens", "Tokens", "Токены") }
    var statsShinies: String {
        t("이로치", "Shinies", "色違い", "Variocolor", "Chromatiques", "Brilhantes", "Schillernde", "Сияющие")
    }
    var statsLegendaries: String {
        t("전설", "Legendaries", "伝説", "Legendarios", "Légendaires", "Lendários", "Legendäre", "Легендарные")
    }

    // MARK: The period

    var statsNoUsage: String {
        t("이 기간에는 사용량이 없어요.", "No usage in this period.", "この期間の使用量はありません。",
          "Sin uso en este periodo.", "Aucune utilisation sur cette période.", "Nenhum uso neste período.",
          "Keine Nutzung in diesem Zeitraum.", "За этот период расхода нет.")
    }
    /// Under the change of a period that is over: it compares with the whole period before.
    func statsComparePrevious(_ scope: RecapScope) -> String {
        switch scope {
        case .week: t("이전 주와 비교", "Compared with the week before", "前の週と比較", "Comparado con la semana anterior",
                      "Comparé à la semaine précédente", "Comparado com a semana anterior",
                      "Verglichen mit der Woche davor", "По сравнению с предыдущей неделей")
        case .month: t("이전 달과 비교", "Compared with the month before", "前の月と比較", "Comparado con el mes anterior",
                       "Comparé au mois précédent", "Comparado com o mês anterior",
                       "Verglichen mit dem Monat davor", "По сравнению с предыдущим месяцем")
        case .year: t("이전 해와 비교", "Compared with the year before", "前の年と比較", "Comparado con el año anterior",
                      "Comparé à l'année précédente", "Comparado com o ano anterior",
                      "Verglichen mit dem Jahr davor", "По сравнению с предыдущим годом")
        }
    }
    /// When a day with usage of the period has no price: why there is no cost tile.
    var statsCostUnknown: String {
        t("일부 날짜의 비용을 알 수 없어요", "Cost unknown for some days", "一部の日のコストは不明です",
          "Coste desconocido para algunos días", "Coût inconnu pour certains jours", "Custo desconhecido em alguns dias",
          "Kosten für einige Tage unbekannt", "Стоимость некоторых дней неизвестна")
    }
    var statsCost: String { t("비용", "Cost", "コスト", "Coste", "Coût", "Custo", "Kosten", "Стоимость") }
    var statsPerActiveDay: String {
        t("활동일 평균", "Per active day", "稼働日平均", "Por día activo", "Par jour actif", "Por dia ativo",
          "Pro aktivem Tag", "В активный день")
    }
    /// "At this pace, about 1.4B by the end of the month".
    func statsProjection(_ scope: RecapScope, _ value: String) -> String {
        switch scope {
        case .week: t("이 속도면 이번 주 약 \(value)", "At this pace, about \(value) by the end of the week",
                      "このペースなら今週末までに約\(value)", "A este ritmo, unos \(value) a final de semana",
                      "À ce rythme, environ \(value) d'ici la fin de la semaine",
                      "Neste ritmo, cerca de \(value) até o fim da semana",
                      "In diesem Tempo etwa \(value) bis Ende der Woche", "В этом темпе около \(value) к концу недели")
        case .month: t("이 속도면 이번 달 약 \(value)", "At this pace, about \(value) by the end of the month",
                       "このペースなら今月末までに約\(value)", "A este ritmo, unos \(value) a final de mes",
                       "À ce rythme, environ \(value) d'ici la fin du mois",
                       "Neste ritmo, cerca de \(value) até o fim do mês",
                       "In diesem Tempo etwa \(value) bis Ende des Monats", "В этом темпе около \(value) к концу месяца")
        case .year: t("이 속도면 올해 약 \(value)", "At this pace, about \(value) by the end of the year",
                      "このペースなら年末までに約\(value)", "A este ritmo, unos \(value) a final de año",
                      "À ce rythme, environ \(value) d'ici la fin de l'année",
                      "Neste ritmo, cerca de \(value) até o fim do ano",
                      "In diesem Tempo etwa \(value) bis Ende des Jahres", "В этом темпе около \(value) к концу года")
        }
    }

    // MARK: Where the tokens went

    var statsWhereTokensWent: String {
        t("토큰이 쓰인 곳", "Where the tokens went", "トークンの内訳", "En qué se fueron los tokens",
          "Où sont partis les tokens", "Para onde foram os tokens", "Wohin die Tokens gingen", "Куда ушли токены")
    }
    var statsUnsplit: String {
        t("구분 없음", "Unsplit", "内訳なし", "Sin desglose", "Non détaillé", "Sem detalhe", "Ohne Aufteilung", "Без разбивки")
    }
    var statsByTool: String {
        t("도구별", "By tool", "ツール別", "Por herramienta", "Par outil", "Por ferramenta", "Nach Tool", "По инструментам")
    }
    var statsByModel: String {
        t("모델별", "By model", "モデル別", "Por modelo", "Par modèle", "Por modelo", "Nach Modell", "По моделям")
    }
    func statsCacheSaved(_ amount: String) -> String {
        t("캐시로 아낀 비용: 약 \(amount)", "The cache saved you about \(amount)", "キャッシュで節約できた額：約\(amount)",
          "La caché te ahorró unos \(amount)", "Le cache t'a fait économiser environ \(amount)",
          "O cache economizou cerca de \(amount)", "Der Cache hat dir etwa \(amount) gespart",
          "Кэш сэкономил около \(amount)")
    }
    var statsCacheSavedHint: String {
        t("캐시에서 읽은 토큰을 입력 가격 대신 읽기 가격으로 계산하고, 캐시 쓰기의 추가 비용을 뺐어요. API 공개 가격 기준이며 구독 요금이 아니에요.",
          "Tokens read from the cache, priced at the read price instead of the input price, less what writing the cache cost more. Public API prices, not your subscription bill.",
          "キャッシュから読んだトークンを入力価格ではなく読み取り価格で計算し、キャッシュ書き込みの追加分を引いた額です。APIの公開価格で、サブスクリプションの請求ではありません。",
          "Tokens leídos de la caché al precio de lectura en vez del de entrada, menos lo que costó de más escribir la caché. Precios públicos de la API, no tu suscripción.",
          "Les tokens lus du cache, au prix de lecture au lieu du prix d'entrée, moins ce que l'écriture du cache a coûté en plus. Prix publics de l'API, pas ta facture d'abonnement.",
          "Tokens lidos do cache pelo preço de leitura em vez do de entrada, menos o que gravar o cache custou a mais. Preços públicos da API, não sua assinatura.",
          "Aus dem Cache gelesene Tokens zum Lesepreis statt zum Eingabepreis, abzüglich der Mehrkosten fürs Schreiben des Caches. Öffentliche API-Preise, nicht dein Abo.",
          "Токены из кэша по цене чтения вместо цены ввода, минус переплата за запись в кэш. Публичные цены API, а не ваша подписка.")
    }

    // MARK: Since install

    var statsSinceInstall: String {
        t("설치 이후", "Since install", "インストール以来", "Desde la instalación", "Depuis l'installation",
          "Desde a instalação", "Seit der Installation", "С момента установки")
    }
    var statsPokemon: String { t("포켓몬", "Pokémon", "ポケモン", "Pokémon", "Pokémon", "Pokémon", "Pokémon", "Покемоны") }
    var statsTokensPerPokemon: String {
        t("포켓몬당 토큰", "Tokens per Pokémon", "1匹あたりのトークン", "Tokens por Pokémon", "Tokens par Pokémon",
          "Tokens por Pokémon", "Tokens pro Pokémon", "Токенов на покемона")
    }
    var statsRecords: String { t("기록", "Records", "記録", "Récords", "Records", "Recordes", "Rekorde", "Рекорды") }
    var statsBestWeek: String {
        t("최고의 주", "Best week", "最高の週", "Mejor semana", "Meilleure semaine", "Melhor semana", "Beste Woche",
          "Лучшая неделя")
    }
    var statsBestMonth: String {
        t("최고의 달", "Best month", "最高の月", "Mejor mes", "Meilleur mois", "Melhor mês", "Bester Monat", "Лучший месяц")
    }
    var statsStreak: String { t("연속 사용", "Streak", "連続", "Racha", "Série", "Sequência", "Serie", "Серия") }
    /// The streak running now and the longest one.
    func statsStreakValue(current: Int, longest: Int) -> String {
        t("현재 \(current)일 · 최장 \(longest)일", "\(current)d now · best \(longest)d", "現在\(current)日・最長\(longest)日",
          "\(current) d ahora · récord \(longest) d", "\(current) j en cours · record \(longest) j",
          "\(current) d agora · recorde \(longest) d", "\(current) T aktuell · Rekord \(longest) T",
          "сейчас \(current) дн. · рекорд \(longest) дн.")
    }
    func statsWeekOf(_ day: String) -> String {
        t("\(day) 주", "Week of \(day)", "\(day)の週", "Semana del \(day)", "Semaine du \(day)", "Semana de \(day)",
          "Woche vom \(day)", "Неделя с \(day)")
    }
    var statsUsualWeek: String {
        t("평소의 한 주", "A typical week", "いつもの一週間", "Una semana típica", "Ta semaine type", "Uma semana típica",
          "Eine typische Woche", "Обычная неделя")
    }
    /// `day` is the weekday's name from the display locale.
    func statsBusiestDay(_ day: String, _ tokens: String) -> String {
        t("평균적으로 \(day)에 가장 많이 써요 (\(tokens))", "On average your busiest day is \(day) (\(tokens))",
          "平均すると一番多いのは\(day)（\(tokens)）", "De media, tu día con más uso es el \(day) (\(tokens))",
          "En moyenne, ton jour le plus chargé est le \(day) (\(tokens))",
          "Em média, seu dia de mais uso é \(day) (\(tokens))",
          "Im Schnitt ist \(day) dein stärkster Tag (\(tokens))",
          "Самый загруженный день в среднем: \(day) (\(tokens))")
    }
}
