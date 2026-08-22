import Foundation
import FoundationModels

/// Sortie contrainte : le modèle ne *peut pas* répondre autre chose.
@Generable
enum Destination: String {
    case bugs, idees, reunions, perso
}

@Generable
struct Rangement {
    @Guide(description: "Le fichier où cette note doit aller")
    var fichier: Destination
    @Guide(description: "La note reformulée en une phrase claire")
    var note: String
}

@main
struct Essai {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("indisponible"); return
        }
        let session = LanguageModelSession(instructions: """
            Tu ranges des notes dictées. Choisis le fichier et reformule la \
            note en français écrit correct.
            """)
        let notes = ["Le bouton de login plante quand le token a expiré",
                     "Et si on ajoutait un mode sombre automatique le soir",
                     "Rendez-vous avec Claire mardi 9 à 14h30"]
        let t = Date()
        for n in notes {
            do {
                let r = try await session.respond(to: n, generating: Rangement.self)
                print("   \(r.content.fichier.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) │ \(r.content.note)")
            } catch { print("   ERREUR : \(error)") }
        }
        print(String(format: "\n   %.0f ms pour les trois", Date().timeIntervalSince(t) * 1000))
    }
}
