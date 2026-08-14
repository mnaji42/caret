import AppKit
import Observation

/// Réglages persistants.
///
/// Tout passe par `UserDefaults` : ce sont quelques scalaires et une liste de
/// mots, une base de données serait disproportionnée. Aucun réglage ne quitte
/// la machine.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let lexicon = "caret.lexicon"
        static let useDefaultLexicon = "caret.lexicon.useDefault"
        static let triggerSide = "caret.trigger.side"
        static let triggerEnabled = "caret.trigger.enabled"
        static let defaultMode = "caret.mode"
        static let language = "caret.language"
    }

    private let defaults = UserDefaults.standard

    // MARK: - Lexique

    /// Termes privilégiés au décodage, un par ligne dans l'interface.
    ///
    /// C'est le principal levier de qualité de l'application : c'est lui qui
    /// fait sortir `useEffect` plutôt que « use effect ». Mais il a un revers
    /// mesuré — plus la liste est longue, plus le modèle risque de placer un
    /// de ces termes sur un passage ambigu où rien n'a été dit. À garder
    /// court et centré sur les mots qui échouent réellement.
    var lexicon: [String] {
        didSet { defaults.set(lexicon, forKey: Key.lexicon) }
    }

    /// Quand vrai, le moteur applique sa liste intégrée et ignore `lexicon`.
    var useDefaultLexicon: Bool {
        didSet { defaults.set(useDefaultLexicon, forKey: Key.useDefaultLexicon) }
    }

    /// Liste effectivement envoyée au moteur. `nil` lui laisse la sienne.
    var effectiveLexicon: [String]? {
        useDefaultLexicon ? nil : lexicon
    }

    // MARK: - Déclencheur

    var triggerEnabled: Bool {
        didSet { defaults.set(triggerEnabled, forKey: Key.triggerEnabled) }
    }

    var triggerSide: ModifierKeyMonitor.Side {
        didSet { defaults.set(triggerSide.rawValue, forKey: Key.triggerSide) }
    }

    // MARK: - Transcription

    var defaultMode: TranscriptionMode {
        didSet { defaults.set(defaultMode.rawValue, forKey: Key.defaultMode) }
    }

    /// Langue principale. Whisper impose un choix unique par passage ; « auto »
    /// existe mais coûte une passe de détection et se trompe régulièrement sur
    /// les phrases mêlant deux langues, ce qui est précisément le cas d'usage.
    var language: String {
        didSet { defaults.set(language, forKey: Key.language) }
    }

    static let languages = [("fr", "Français"), ("en", "English")]

    private init() {
        lexicon = defaults.stringArray(forKey: Key.lexicon) ?? Self.starterLexicon
        useDefaultLexicon = defaults.object(forKey: Key.useDefaultLexicon) as? Bool ?? true
        triggerEnabled = defaults.object(forKey: Key.triggerEnabled) as? Bool ?? true
        triggerSide = ModifierKeyMonitor.Side(
            rawValue: defaults.string(forKey: Key.triggerSide) ?? "right") ?? .right
        defaultMode = TranscriptionMode(
            rawValue: defaults.string(forKey: Key.defaultMode) ?? "intended") ?? .intended
        language = defaults.string(forKey: Key.language) ?? "fr"
    }

    /// Point de départ quand l'utilisateur passe à sa propre liste : le même
    /// contenu que la liste intégrée, pour qu'il parte de quelque chose qui
    /// marche plutôt que d'une page blanche.
    static let starterLexicon = [
        "useEffect", "useState", "useMemo", "useRef", "component", "React",
        "Next.js", "TypeScript", "hook", "props", "state",
        "refactor", "merge", "commit", "rebase", "branch", "pull request",
        "review", "deploy", "build",
        "endpoint", "middleware", "dependencies", "async", "await", "API",
        "JSON", "query", "schema", "cache", "buffer",
        "chunk", "chunking", "prompt", "token", "embedding",
    ]
}
