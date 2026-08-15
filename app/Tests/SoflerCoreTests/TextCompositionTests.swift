import Testing
@testable import SoflerCore

// MARK: - Ajout dans un fichier verrouillé

@Suite("Ajout de texte")
struct AppendingTests {

    @Test("Un fichier vide ne commence pas par des lignes blanches")
    func emptyFile() {
        #expect(TextComposition.appending("Première note.", to: "")
                == "Première note.\n")
    }

    @Test("Les entrées sont séparées par une ligne blanche")
    func separatesEntries() {
        var content = ""
        for note in ["Un.", "Deux.", "Trois."] {
            content = TextComposition.appending(note, to: content)
        }
        #expect(content == "Un.\n\nDeux.\n\nTrois.\n")
    }

    @Test("Un fichier sans saut final en reçoit un")
    func fileWithoutTrailingNewline() {
        #expect(TextComposition.appending("Ajout.", to: "# Titre")
                == "# Titre\n\nAjout.\n")
    }

    @Test("Un saut existant n'est pas doublé")
    func doesNotDoubleExistingNewline() {
        #expect(TextComposition.appending("Suite.", to: "Texte.\n\n")
                == "Texte.\n\nSuite.\n")
    }

    @Test("Un texte vide ne modifie rien")
    func emptyTextIsIgnored() {
        #expect(TextComposition.appending("   \n  ", to: "Existant.\n")
                == "Existant.\n")
    }

    @Test("Les espaces autour de l'entrée sont retirés")
    func trimsWhitespace() {
        #expect(TextComposition.appending("  Note.  ", to: "") == "Note.\n")
    }
}

// MARK: - Titre de fenêtre

@Suite("Analyse du titre de fenêtre")
struct WindowTitleTests {

    @Test("Un nom contenant un tiret survit",
          arguments: [
            "test-sofler.md — sofler",
            "● test-sofler.md — sofler",
            "test-sofler.md - sofler - Antigravity",
          ])
    func dashInFileName(title: String) {
        // Régression réelle : découper sur le tiret nu donnait « test ».
        #expect(TextComposition.parseWindowTitle(title)?.fileName == "test-sofler.md")
    }

    @Test("Le marqueur de modification est retiré")
    func stripsModifiedMarker() {
        #expect(TextComposition.parseWindowTitle("● index.tsx — app")?.fileName
                == "index.tsx")
    }

    @Test("Le projet est retenu comme indice")
    func capturesHints() {
        let parsed = TextComposition.parseWindowTitle("README.md — mon-projet")
        #expect(parsed?.hints == ["mon-projet"])
    }

    @Test("Un titre sans extension est rejeté",
          arguments: ["Untitled-1", "Réglages", "Sans titre — app"])
    func rejectsNonFiles(title: String) {
        #expect(TextComposition.parseWindowTitle(title) == nil)
    }

    @Test("Un titre vide est rejeté")
    func rejectsEmpty() {
        #expect(TextComposition.parseWindowTitle("") == nil)
    }

    @Test("Un nom seul reste exploitable")
    func bareFileName() {
        let parsed = TextComposition.parseWindowTitle("notes.md")
        #expect(parsed?.fileName == "notes.md")
        #expect(parsed?.hints.isEmpty == true)
    }
}

// MARK: - Choix parmi les homonymes

@Suite("Choix du bon fichier")
struct CandidateTests {

    @Test("Le chemin contenant le projet l'emporte")
    func prefersProjectPath() {
        let paths = ["/Users/x/autre/README.md", "/Users/x/mon-projet/README.md"]
        #expect(TextComposition.bestCandidate(among: paths,
                                              preferring: ["mon-projet"])
                == "/Users/x/mon-projet/README.md")
    }

    @Test("Un candidat unique est retenu sans indice")
    func singleCandidate() {
        #expect(TextComposition.bestCandidate(among: ["/a/notes.md"],
                                              preferring: [])
                == "/a/notes.md")
    }

    @Test("L'ambiguïté n'est pas tranchée au hasard")
    func refusesAmbiguity() {
        // Mieux vaut ouvrir le sélecteur que d'écrire dans le mauvais fichier.
        let paths = ["/a/README.md", "/b/README.md"]
        #expect(TextComposition.bestCandidate(among: paths, preferring: []) == nil)
    }

    @Test("Un indice trop court est ignoré")
    func ignoresShortHints() {
        let paths = ["/a/x.md", "/b/x.md"]
        #expect(TextComposition.bestCandidate(among: paths, preferring: ["a"]) == nil)
    }

    @Test("Aucun candidat donne nil")
    func noCandidates() {
        #expect(TextComposition.bestCandidate(among: [], preferring: ["x"]) == nil)
    }
}
