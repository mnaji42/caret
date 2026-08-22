// Le LLM d'Apple sait-il faire le « texte nettoyé » de Caspr ?
import Foundation
import FoundationModels

let CONSIGNE = """
Tu reformules une dictée vocale en français écrit correct. Retire les \
hésitations et les répétitions, ponctue normalement, garde chaque idée et \
chaque terme technique exactement tel qu'il a été prononcé. Ne traduis pas, \
ne résume pas, n'ajoute rien. N'écris que le texte corrigé.
"""

@main
struct Essai {
    static func main() async {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            print("modèle indisponible"); return
        }
        // Des dictées réelles du corpus, telles que CrisperWhisper les a rendues.
        let brut = [
            "Ouais, donc là, on va continuer un petit peu, donc je vais parler. Donc normalement j'ai activé à la fois le mode pour récupérer le texte et à la fois le mode pour enregistrer l'audio aussi, comme ça tu auras pas mal de data.",
            "Et aussi pour info, donc tout ce que je dis maintenant, à chaque fois tu l'analyseras, tu donneras ton avis sur ce qui fonctionne mieux, ce qui fonctionne mieux. Effects de fonctionnement pas bien, comment on peut améliorer les choses, tout ça.",
            "Un autre souci que je viens de remarquer quand j'appuie sur le bouton là, ben ça marche pas, enfin ça marche mais euh voilà, faut que tu regardes le useEffect et les dependencies du component React.",
        ]
        for (i, texte) in brut.enumerated() {
            let session = LanguageModelSession(instructions: CONSIGNE)
            let t = Date()
            do {
                let out = try await session.respond(to: texte)
                let ms = Date().timeIntervalSince(t) * 1000
                print("── \(i + 1)  \(String(format: "%.0f", ms)) ms  (\(texte.split(separator: " ").count) mots)")
                print("   AVANT : \(texte.prefix(120))")
                print("   APRÈS : \(out.content.prefix(200))\n")
            } catch {
                print("── \(i + 1)  ERREUR : \(error)\n")
            }
        }
    }
}
