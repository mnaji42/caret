import CaretCore
import Foundation
import FoundationModels

/// Relecture de la transcription par le modèle de langue local d'Apple.
///
/// Troisième mode, explicitement expérimental. Il tourne entièrement
/// sur l'appareil comme le reste de Caret — aucun appel réseau, aucune clé.
///
/// Sa sortie n'est jamais utilisée telle quelle : `TranscriptGuard` la rejette
/// dès qu'elle s'écarte trop de l'original, parce que ce modèle répond parfois
/// à la phrase au lieu de la corriger. En cas de rejet, l'original est
/// conservé — le mode ne peut donc que laisser le texte inchangé ou le
/// réparer légèrement, jamais le remplacer.
/// Requiert macOS 26 : le reste de Caret fonctionne dès macOS 14, seul ce
/// mode dépend des modèles de langue du système.
@available(macOS 26, *)
@MainActor
final class TranscriptReviewer {
    enum Availability {
        case ready
        case unavailable(String)
    }

    private static let instructions = """
    Tu répares des transcriptions vocales d'un développeur francophone qui \
    mélange français et anglais technique.

    Certains mots ont été mal entendus et ne veulent rien dire dans la phrase. \
    Remplace uniquement ceux-là par le mot manifestement voulu.

    Règles absolues :
    - ne réponds jamais à la phrase, tu la corriges seulement
    - ne change que les mots qui n'ont aucun sens
    - si tout est plausible, renvoie la phrase à l'identique
    - ne reformule pas, n'ajoute rien, ne retire rien
    - aucun formatage : ni gras, ni listes, ni guillemets ajoutés
    - garde les termes techniques anglais tels quels
    - réponds uniquement par la phrase, rien d'autre
    """

    static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available: .ready
        case .unavailable(let reason): .unavailable("\(reason)")
        @unknown default: .unavailable("état inconnu")
        }
    }

    /// Relit le texte. Retourne l'original si la relecture est douteuse.
    func review(_ text: String) async -> String {
        guard case .ready = Self.availability else { return text }
        // Une longue dictée dépasse la fenêtre du modèle : on relit phrase par
        // phrase, ce qui limite aussi la casse d'un dérapage isolé.
        let chunks = Self.split(text)
        var pieces: [String] = []
        for chunk in chunks {
            pieces.append(await reviewChunk(chunk))
        }
        return pieces.joined(separator: " ")
    }

    private func reviewChunk(_ chunk: String) async -> String {
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: chunk, options: GenerationOptions(temperature: 0.1))
            switch TranscriptGuard.review(original: chunk,
                                          rewritten: response.content) {
            case .accepted(let corrected):
                if corrected != chunk {
                    NSLog("caret: relu — « %@ » → « %@ »", chunk, corrected)
                }
                return corrected
            case .rejected(let reason):
                NSLog("caret: relecture écartée (%@)", reason)
                return chunk
            }
        } catch {
            // Les garde-fous d'Apple rejettent parfois des phrases techniques
            // anodines ; on garde l'original sans en faire une erreur.
            NSLog("caret: relecture indisponible — %@", "\(error)")
            return chunk
        }
    }

    /// Découpe en phrases, en regroupant pour rester sous la fenêtre du modèle.
    nonisolated static func split(_ text: String, limit: Int = 400) -> [String] {
        var chunks: [String] = []
        var current = ""
        for sentence in text.split(omittingEmptySubsequences: true,
                                   whereSeparator: { ".!?".contains($0) }) {
            let piece = sentence.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            if current.count + piece.count > limit, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += current.isEmpty ? piece + "." : " " + piece + "."
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [text] : chunks
    }
}
