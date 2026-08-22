import Foundation
import FoundationModels

@main
struct Essai {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("indisponible"); return
        }
        let texte = "Un autre souci que je viens de remarquer quand j'appuie sur le bouton là, ben ça marche pas, enfin ça marche mais euh voilà, faut que tu regardes le useEffect et les dependencies du component React."

        // --- 1. le flux : quand le premier mot arrive-t-il ? ---
        let session = LanguageModelSession(instructions: """
            Reformule cette dictée en français écrit correct. Retire les \
            hésitations, ponctue, garde les termes techniques tels quels. \
            N'écris que le texte corrigé.
            """)
        let t = Date()
        var premier: Double?
        var dernier = ""
        do {
            for try await partiel in session.streamResponse(to: texte) {
                if premier == nil { premier = Date().timeIntervalSince(t) * 1000 }
                dernier = String(describing: partiel.content)
            }
        } catch { print("erreur flux : \(error)"); return }
        let total = Date().timeIntervalSince(t) * 1000
        print("── flux ──")
        print(String(format: "   premier fragment : %.0f ms", premier ?? -1))
        print(String(format: "   texte complet    : %.0f ms", total))
        print("   \(dernier.prefix(190))")

        // --- 2. sortie structurée : router une note vers le bon fichier ---
        print("\n── sortie structurée (routage de note) ──")
        let t2 = Date()
        let router = LanguageModelSession(instructions: """
            Tu ranges des notes dictées dans le bon fichier. Fichiers \
            disponibles : bugs.md, idees.md, reunions.md, perso.md. \
            Réponds UNIQUEMENT par le nom du fichier, rien d'autre.
            """)
        for note in ["Le bouton de login plante quand le token a expiré",
                     "Et si on ajoutait un mode sombre automatique le soir",
                     "Rendez-vous avec Claire mardi 9 à 14h30"] {
            if let r = try? await router.respond(to: note) {
                print("   \(note.prefix(46))… → \(r.content.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        print(String(format: "   (%.0f ms pour les trois)", Date().timeIntervalSince(t2) * 1000))
    }
}
