// Ce que macOS 26 offre déjà, sans rien télécharger.
import Foundation
import Vision
import AppKit
import FoundationModels

// --- 1. OCR : lire le texte d'une capture d'écran -------------------------
func ocr(_ url: URL) async -> [String] {
    guard let image = NSImage(contentsOf: url),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return [] }
    var request = RecognizeTextRequest()
    request.recognitionLanguages = [Locale.Language(identifier: "fr-FR"),
                                    Locale.Language(identifier: "en-US")]
    request.recognitionLevel = .accurate
    guard let obs = try? await request.perform(on: cg) else { return [] }
    return obs.compactMap { $0.topCandidates(1).first?.string }
}

// --- 2. Le LLM embarqué d'Apple -------------------------------------------
func llm(_ prompt: String) async -> String {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available: break
    case .unavailable(let raison):
        return "INDISPONIBLE : \(raison)"
    }
    do {
        let session = LanguageModelSession()
        let out = try await session.respond(to: prompt)
        return out.content
    } catch {
        return "ERREUR : \(error)"
    }
}

// --- essai ----------------------------------------------------------------
@main
struct Essai {
    static func main() async {
        let args = CommandLine.arguments
        if args.count > 2, args[1] == "--ocr" {
            let lignes = await ocr(URL(fileURLWithPath: args[2]))
            print("OCR : \(lignes.count) lignes")
            for l in lignes.prefix(14) { print("  \(l)") }
            return
        }
        if args.count > 3, args[1] == "--chain" {
            // La chaîne complète : capture → OCR → LLM, tout sur la machine.
            let lignes = await ocr(URL(fileURLWithPath: args[2]))
            let vu = lignes.joined(separator: "\n")
            print("── ce que l'écran contient (\(lignes.count) lignes) ──")
            print(vu.prefix(200))
            print("\n── demande ──\n\(args[3])")
            print("\n── réponse ──")
            print(await llm("""
                Voici le texte lu à l'écran :
                \(vu)

                Demande de l'utilisateur : \(args[3])

                Réponds en français, sans préambule.
                """))
            return
        }
        print("── disponibilité du modèle Apple ──")
        print(await llm("Réponds en une phrase : quelle est la capitale de la France ?"))
        print("\n── rédaction ──")
        print(await llm("""
            Rédige un mail court et poli en français pour décliner une réunion \
            jeudi, en proposant vendredi à la place. Signe « Mehdi ».
            """))
    }
}
