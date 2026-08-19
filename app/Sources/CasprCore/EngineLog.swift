import Foundation

/// Lecture du journal du service de transcription.
///
/// Ici plutôt qu'à côté de `EngineService`, pour la raison qui a fait naître ce
/// module : c'est une règle pure, et c'est exactement le genre de règle qui se
/// casse sans bruit. Elle décide entre deux messages opposés — « patientez, le
/// modèle charge » et « le service n'a pas pu démarrer » — et se tromper ne
/// produit aucune erreur : ça laisse quelqu'un attendre indéfiniment quelque
/// chose qui n'arrivera pas.
///
/// C'est arrivé, sur la panne la plus bête qui soit. Le moteur choisissait
/// Metal sans le mesurer ; une machine virtuelle macOS n'en a pas ; le service
/// mourait au chargement du modèle, launchd le relançait toutes les trente
/// secondes, et l'application répétait « réessayez dans un instant » à chaque
/// dictée. Rien ne pointait vers la cause, qui tenait pourtant en une ligne
/// dans le journal.
public enum EngineLog {

    /// La dernière erreur fatale, si le service est mort depuis son dernier
    /// démarrage annoncé.
    ///
    /// Deux conditions, et les deux comptent. La trace doit venir **après** le
    /// dernier « chargement de » : le journal est en ajout seul, donc la panne
    /// d'avant-hier y figure encore alors qu'elle est réparée, et la ressortir
    /// enverrait chercher un problème qui n'existe plus. Et il faut une trace
    /// Python : un service qui charge encore n'en a produit aucune.
    ///
    /// - Returns: la ligne d'exception, ou `nil` si rien n'indique une panne.
    public static func fatalError(in log: String) -> String? {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        guard let started = lines.lastIndex(where: { $0.contains(startMarker) })
        else { return nil }

        let after = lines[lines.index(after: started)...]
        guard after.contains(where: { $0.contains(tracebackMarker) }) else { return nil }

        // La dernière ligne non vide et non indentée : dans une trace Python
        // c'est « RuntimeError: … », la seule que quelqu'un puisse lire sans
        // dérouler la pile. Les lignes de pile, elles, commencent toutes par
        // des espaces.
        return after.last { line in
            !line.isEmpty && !line.hasPrefix(" ") && line.contains(":")
        }
        .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Ce que le serveur écrit juste avant de charger le modèle. Sert de borne :
    /// tout ce qui précède appartient à un démarrage révolu.
    static let startMarker = "chargement de"
    static let tracebackMarker = "Traceback (most recent call last)"
}
