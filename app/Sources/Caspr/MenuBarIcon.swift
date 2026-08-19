import AppKit

/// Le glyphe de la barre de menus, dessiné plutôt qu'emprunté.
///
/// Il utilisait `mic`, `mic.fill` et `mic.badge.plus` — c'est-à-dire très
/// exactement les symboles de la dictée d'Apple. Deux problèmes. Dans une
/// barre de menus, l'utilisateur ne distinguait pas Caspr d'un élément du
/// système ; et une application qui réclame le micro *et* le droit de piloter
/// le clavier a tout intérêt à s'annoncer comme elle-même.
///
/// Le motif est le caret, la barre d'insertion du texte, parce que c'est ce
/// que Caspr fait de particulier : le texte atterrit là où le curseur est
/// déjà. Les ondes ne sont pas décoratives, elles portent l'état — elles
/// n'apparaissent que pendant l'écoute. Un coup d'œil suffit alors à savoir
/// si le micro tourne, ce qui est la seule question urgente que pose une app
/// de dictée.
///
/// Dessiné à l'exécution et non chargé depuis un PNG : le `drawingHandler` est
/// rappelé à chaque rendu, donc à la résolution réelle de l'écran, et les
/// variantes d'état ne coûtent pas un fichier chacune.
enum MenuBarIcon {
    /// 18 pt de haut, la hauteur utile de la barre de menus.
    private static let size = NSSize(width: 18, height: 18)

    /// Ce que l'icône dit, et rien d'autre.
    ///
    /// La grammaire vient des dessins : **le fantôme ne change jamais**, une
    /// bulle apparaît en bas à droite, et c'est son contenu qui porte l'état —
    /// cinq barres pour l'écoute, trois points pour le traitement. L'œil
    /// reconnaît l'application d'abord, son état ensuite.
    /// La forme dit *quoi*, la couleur dit *si c'est grave* — cyan pour ce qui
    /// est normal ou souhaitable, rouge pour ce qui demande une intervention.
    enum State {
        case idle, listening, processing, error, update

        var fileName: String {
            switch self {
            case .idle: "caspr-ghost"
            case .listening: "caspr-ghost-listening"
            case .processing: "caspr-ghost-processing"
            case .error: "caspr-ghost-error"
            case .update: "caspr-ghost-update"
            }
        }
    }

    static func image(_ state: State) -> NSImage? {
        guard let url = Bundle.main.url(forResource: state.fileName,
                                        withExtension: "svg",
                                        subdirectory: "icons"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.size = size
        // **Gabarit**, y compris pour les états colorés : la barre de menus est
        // claire en thème clair, et un fantôme blanc y serait invisible. macOS
        // reteint alors le dessin dans la couleur du texte, ce qui garde la
        // silhouette lisible partout — c'est elle qui identifie l'application,
        // et la forme de la bulle suffit à distinguer les trois états sans la
        // couleur. Le cyan reste dans les fenêtres, où le fond est maîtrisé.
        image.isTemplate = true
        return image
    }
}
