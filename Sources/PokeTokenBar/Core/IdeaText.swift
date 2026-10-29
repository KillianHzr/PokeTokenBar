import Foundation

/// The words of the ideas page (`IdeaReport`, `IdeasScreen`).
extension L {
    var ideasTitle: String {
        t("아이디어 보내기", "Send an idea", "アイデアを送る", "Enviar una idea", "Proposer une idée", "Enviar uma ideia", "Idee senden",
          "Предложить идею")
    }

    var ideasIntro: String {
        t("아이디어나 버그는 GitHub의 PokeTokenLBI 이슈로 올라가요. 누구나 읽을 수 있어요.",
          "Your idea or bug goes to GitHub, as an issue of PokeTokenLBI that anyone can read.",
          "アイデアやバグはGitHubのPokeTokenLBIのissueになり、だれでも読めます。",
          "Tu idea o error llega a GitHub, como una issue de PokeTokenLBI que cualquiera puede leer.",
          "Ton idée ou ton bug arrive sur GitHub, en issue de PokeTokenLBI, que tout le monde peut lire.",
          "Sua ideia ou bug vai para o GitHub, como uma issue do PokeTokenLBI que qualquer pessoa pode ler.",
          "Deine Idee oder dein Fehler landet auf GitHub als Issue von PokeTokenLBI, das alle lesen können.",
          "Идея или ошибка попадёт на GitHub как issue PokeTokenLBI, которую может прочитать любой.")
    }

    func ideaKind(_ kind: IdeaReport.Kind) -> String {
        switch kind {
        case .idea: return t("아이디어", "Idea", "アイデア", "Idea", "Idée", "Ideia", "Idee", "Идея")
        case .bug: return t("버그", "Bug", "バグ", "Error", "Bug", "Bug", "Fehler", "Ошибка")
        }
    }

    var ideasTitleField: String {
        t("한 줄 요약", "In one line", "ひとことで", "En una línea", "En une ligne", "Em uma linha", "In einer Zeile", "Одной строкой")
    }

    var ideasDetailsPlaceholder: String {
        t("자세히 (선택)", "Details (optional)", "くわしく(任意)", "Detalles (opcional)", "Détails (facultatif)", "Detalhes (opcional)",
          "Details (optional)", "Подробности (необязательно)")
    }

    var ideasIncludeSystem: String {
        t("앱과 macOS 버전 포함", "Include the app and macOS versions", "アプリとmacOSのバージョンを含める",
          "Incluir las versiones de la app y de macOS", "Joindre les versions de l'app et de macOS", "Incluir as versões do app e do macOS",
          "App- und macOS-Version anhängen", "Добавить версии приложения и macOS")
    }

    var ideasSend: String {
        t("GitHub에 올리기", "Post on GitHub", "GitHubに投稿", "Publicar en GitHub", "Publier sur GitHub", "Publicar no GitHub",
          "Auf GitHub posten", "Опубликовать на GitHub")
    }

    var ideasOpenBrowser: String {
        t("브라우저에서 열기", "Open in the browser", "ブラウザで開く", "Abrir en el navegador", "Ouvrir dans le navigateur",
          "Abrir no navegador", "Im Browser öffnen", "Открыть в браузере")
    }

    var ideasGHHint: String {
        t("GitHub CLI(gh)로 로그인돼 있어 앱에서 바로 올릴 수 있어요.",
          "You're signed in with the GitHub CLI (gh): the app can post it directly.",
          "GitHub CLI(gh)でログインしているので、アプリから直接投稿できます。",
          "Iniciaste sesión con la CLI de GitHub (gh): la app puede publicarla directamente.",
          "Tu es connecté avec la CLI GitHub (gh) : l'app peut la publier directement.",
          "Você entrou com a CLI do GitHub (gh): o app pode publicar direto.",
          "Du bist mit der GitHub-CLI (gh) angemeldet: Die App kann es direkt posten.",
          "Вы вошли через GitHub CLI (gh): приложение может опубликовать сразу.")
    }

    var ideasBrowserHint: String {
        t("GitHub 페이지가 미리 채워져 열려요. 로그인한 뒤 보내기만 누르면 돼요.",
          "GitHub's page opens prefilled: sign in and press Submit.",
          "入力済みのGitHubのページが開きます。ログインして送信するだけです。",
          "Se abre la página de GitHub ya rellenada: inicia sesión y pulsa Enviar.",
          "La page GitHub s'ouvre déjà remplie : connecte-toi et appuie sur Envoyer.",
          "A página do GitHub abre preenchida: entre e toque em Enviar.",
          "Die GitHub-Seite öffnet sich ausgefüllt: Melde dich an und drücke auf Senden.",
          "Откроется заполненная страница GitHub: войдите и нажмите \"Отправить\".")
    }

    var ideasSent: String {
        t("올렸어요. 고마워요!", "Posted. Thank you!", "投稿しました。ありがとう!", "Publicada. ¡Gracias!", "Publiée. Merci !",
          "Publicada. Obrigado!", "Gepostet. Danke!", "Опубликовано. Спасибо!")
    }

    var ideasSeeIssue: String {
        t("이슈 보기", "See the issue", "issueを見る", "Ver la issue", "Voir l'issue", "Ver a issue", "Issue ansehen", "Открыть issue")
    }

    var ideasFailed: String {
        t("gh로 올리지 못했어요. 브라우저에서 열어 보세요.", "gh could not post it: open it in the browser instead.",
          "ghで投稿できませんでした。ブラウザで開いてください。", "gh no pudo publicarla: ábrela en el navegador.",
          "gh n'a pas pu la publier : ouvre-la dans le navigateur.", "O gh não conseguiu publicar: abra no navegador.",
          "gh konnte es nicht posten: Öffne es im Browser.", "gh не смог опубликовать: откройте в браузере.")
    }
}
