import Foundation

/// Logique de composition du texte, sans dépendance système.
///
/// Isolée ici pour être testable : le reste de l'application manipule
/// l'accessibilité, le micro et les fenêtres, qu'on ne peut pas exercer dans
/// des tests. Ces règles-là sont pures, et ce sont elles qui se cassent
/// silencieusement.
public enum TextComposition {

    // MARK: - Ajout dans un fichier verrouillé

    /// Préfixe à insérer entre le contenu existant et la nouvelle entrée.
    ///
    /// Deux sauts de ligne séparent les entrées — un seul fusionnerait les
    /// paragraphes en Markdown. Mais il ne faut ni ouvrir un fichier vide par
    /// des lignes blanches, ni doubler des sauts déjà présents.
    public static func separatorPrefix(after existing: String) -> String {
        if existing.isEmpty { return "" }
        if existing.hasSuffix("\n\n") { return "" }
        if existing.hasSuffix("\n") { return "\n" }
        return "\n\n"
    }

    /// Contenu complet après ajout d'une entrée.
    public static func appending(_ text: String, to existing: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existing }
        return existing + separatorPrefix(after: existing) + trimmed + "\n"
    }

    // MARK: - Titre de fenêtre

    public struct WindowTitle: Equatable {
        /// Nom de fichier supposé, marqueur de modification retiré.
        public let fileName: String
        /// Segments suivants du titre — typiquement le nom du projet, qui sert
        /// à départager plusieurs fichiers homonymes.
        public let hints: [String]
    }

    /// Extrait le fichier d'un titre de fenêtre d'éditeur.
    ///
    /// Les éditeurs dérivés de VS Code titrent « fichier.ext — projet ». Le
    /// séparateur est un tiret **entouré d'espaces** : découper sur le tiret
    /// seul casserait « test-sofler.md » en « test ».
    public static func parseWindowTitle(_ title: String) -> WindowTitle? {
        let parts = title
            .replacingOccurrences(of: #"\s+[—–-]\s+"#, with: "\u{1}",
                                  options: .regularExpression)
            .components(separatedBy: "\u{1}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let first = parts.first else { return nil }
        let name = first
            .trimmingCharacters(in: CharacterSet(charactersIn: "●•*◆ "))
            .trimmingCharacters(in: .whitespaces)
        // Sans extension, ce n'est pas un fichier : « Untitled-1 », « Réglages ».
        guard name.contains("."), name.count > 2 else { return nil }

        return WindowTitle(fileName: name,
                           hints: parts.dropFirst().map { $0.lowercased() })
    }

    /// Choisit le meilleur chemin parmi des candidats homonymes.
    ///
    /// Un `README.md` existe des dizaines de fois sur un disque : sans
    /// préférence pour le projet, on écrirait dans le mauvais.
    public static func bestCandidate(among paths: [String],
                                     preferring hints: [String]) -> String? {
        guard !paths.isEmpty else { return nil }
        for hint in hints where hint.count > 2 {
            if let match = paths.first(where: { $0.lowercased().contains(hint) }) {
                return match
            }
        }
        // Sans indice exploitable, on ne tranche que s'il n'y a pas d'ambiguïté.
        return paths.count == 1 ? paths[0] : nil
    }
}
