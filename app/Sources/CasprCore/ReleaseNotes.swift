import Foundation

/// Ce qui change dans une version, tiré du corps de la release GitHub.
///
/// ## Pourquoi ce texte a besoin d'être nettoyé
///
/// L'application demande à quelqu'un de remplacer le logiciel qu'il est en
/// train d'utiliser. La seule chose qui puisse motiver ce geste, c'est de
/// savoir ce que ça lui apporte — et le corps de la release est le seul endroit
/// où c'est écrit. Il était récupéré depuis toujours (`payload.body`) et
/// affiché nulle part.
///
/// Mais on ne peut pas le poser tel quel dans une fenêtre. Deux formes
/// coexistent, et une seule est rédigée pour être lue :
///
/// - **Les notes écrites à la main** (`docs/releases/vX.Y.Z.md`, cf.
///   `.github/workflows/release.yml`) : des puces en français, une par
///   changement. C'est la forme voulue.
/// - **Les notes engendrées par GitHub** (`--generate-notes`, ce que faisaient
///   les releases jusqu'ici) : un titre `## What's Changed` en anglais, une
///   ligne par commit suffixée de `by @auteur in https://…`, et un
///   `**Full Changelog**` final. Lisible sur une page web, illisible dans une
///   fenêtre de 400 points.
///
/// Ce type ramène les deux à la même chose : une liste de phrases. Les
/// anciennes releases restent donc présentables, ce qui compte — la fenêtre de
/// mise à jour parle d'une version *publiée*, pas de celle qu'on prépare.
///
/// Il ne rend **jamais** de Markdown de structure : les titres, les séparateurs
/// et le lien de comparaison disparaissent. Ce qui reste est du texte, avec au
/// plus du gras et du code en ligne, que `Text(.init(_:))` sait rendre.
public enum ReleaseNotes {

    /// Les changements, une phrase par entrée. Vide quand il n'y a rien à dire.
    public static func lines(from body: String) -> [String] {
        var found: [String] = []
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !isStructure(line) else { continue }
            let cleaned = strippingAttribution(strippingMarker(line))
                .trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { continue }
            // Dédoublonnage : une note recopiée d'un tag à l'autre — ça arrive
            // quand on republie une version — afficherait deux fois la même
            // phrase, ce qui fait douter d'avoir bien lu.
            guard !found.contains(cleaned) else { continue }
            found.append(cleaned)
        }
        return found
    }

    /// Une ligne qui structure le document plutôt que de dire quelque chose.
    ///
    /// Les titres (`## What's Changed`), les filets (`---`), et le lien de
    /// comparaison que GitHub ajoute en pied. Ce dernier est reconnu sur son
    /// libellé et non sur son URL : il est traduit dans certains dépôts, mais
    /// commence toujours par « Full Changelog ».
    private static func isStructure(_ line: String) -> Bool {
        if line.hasPrefix("#") { return true }
        if line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }),
           line.count >= 3 {
            return true
        }
        let withoutBold = line.replacingOccurrences(of: "*", with: "")
        return withoutBold.hasPrefix("Full Changelog")
    }

    /// Retire la puce ou le numéro qui ouvre une entrée de liste.
    ///
    /// La vue pose sa propre puce : garder celle du texte en afficherait deux.
    private static func strippingMarker(_ line: String) -> String {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        // « 1. », « 12. » — le point suivi d'une espace, précédé de chiffres.
        if let dot = line.firstIndex(of: "."),
           line[line.startIndex..<dot].allSatisfy(\.isNumber),
           line[line.startIndex..<dot].count <= 3,
           line.index(after: dot) < line.endIndex,
           line[line.index(after: dot)] == " " {
            return String(line[line.index(dot, offsetBy: 2)...])
        }
        return line
    }

    /// Retire le « by @auteur in https://… » que GitHub accroche à chaque
    /// commit.
    ///
    /// Sur une page de release, savoir qui a écrit quoi a du sens. Dans une
    /// fenêtre qui demande d'installer une mise à jour, c'est une URL de
    /// soixante caractères par ligne, et il n'y a qu'un auteur.
    private static func strippingAttribution(_ line: String) -> String {
        guard let range = line.range(of: " by @") else { return line }
        // Uniquement si ce qui suit ressemble bien au gabarit de GitHub : une
        // phrase peut légitimement contenir « by @quelqu'un ».
        let tail = line[range.upperBound...]
        guard tail.contains(" in http") else { return line }
        return String(line[line.startIndex..<range.lowerBound])
    }
}
