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
        static let lexicon = "sofler.lexicon"
        static let useDefaultLexicon = "sofler.lexicon.useDefault"
        static let triggerSide = "sofler.trigger.side"
        static let triggerEnabled = "sofler.trigger.enabled"
        static let defaultMode = "sofler.mode"
        static let language = "sofler.language"
        static let noteFile = "sofler.notes.file"
        static let livePreview = "sofler.preview.live"
        static let corpus = "sofler.corpus.enabled"
        static let corpusAudio = "sofler.corpus.audio"
    }

    private let defaults = UserDefaults.standard

    // MARK: - Lexique

    /// Termes privilégiés au décodage, un par ligne dans l'interface.
    ///
    /// C'est le principal levier de qualité de l'application : c'est lui qui
    /// fait sortir `useEffect` plutôt que « use effect ».
    ///
    /// Mais allonger la liste dégrade, et c'est mesuré : à 36 termes le modèle
    /// perd des virgules — « Dans Next.js j'ai envie » au lieu de « Dans
    /// Next.js, j'ai envie ». Un prompt plus long dilue le contexte. Il faut
    /// donc retirer un terme pour en ajouter un, pas empiler.
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

    // MARK: - Notes

    /// Fichier des notes, retenu **indépendamment** de la destination courante.
    ///
    /// Revenir au curseur ne doit pas l'oublier : on alterne entre les deux en
    /// pleine dictée, et redemander le fichier à chaque retour ouvrirait un
    /// sélecteur — qui activerait Sofler et déplacerait le curseur, exactement
    /// ce que l'overlay `nonactivatingPanel` s'applique à éviter.
    ///
    /// Un chemin suffit : l'application n'est pas en bac à sable, donc pas de
    /// signet à conserver pour retrouver le droit d'écrire.
    var noteFile: URL? {
        didSet { defaults.set(noteFile?.path, forKey: Key.noteFile) }
    }

    /// Aperçu en direct pendant la dictée, par le moteur système.
    ///
    /// Réglable depuis la barre elle-même : c'est là qu'on s'aperçoit qu'il
    /// gêne, pas dans une fenêtre de réglages.
    var livePreviewEnabled: Bool {
        didSet { defaults.set(livePreviewEnabled, forKey: Key.livePreview) }
    }

    // MARK: - Collecte

    /// Archive chaque dictée avec les textes des trois moteurs.
    ///
    /// Coûte une seconde passe du moteur par dictée, lancée après insertion et
    /// abandonnée si on réenchaîne — la latence de dictée ne se négocie pas.
    var corpusEnabled: Bool {
        didSet { defaults.set(corpusEnabled, forKey: Key.corpus) }
    }

    /// Conserve aussi l'audio. Séparé de la collecte parce que le coût en
    /// place n'a rien à voir : ~2 Mo par minute contre quelques kilo-octets
    /// de texte. Faux par défaut.
    var corpusKeepsAudio: Bool {
        didSet { defaults.set(corpusKeepsAudio, forKey: Key.corpusAudio) }
    }

    private init() {
        lexicon = defaults.stringArray(forKey: Key.lexicon) ?? Self.starterLexicon
        useDefaultLexicon = defaults.object(forKey: Key.useDefaultLexicon) as? Bool ?? true
        triggerEnabled = defaults.object(forKey: Key.triggerEnabled) as? Bool ?? true
        triggerSide = ModifierKeyMonitor.Side(
            rawValue: defaults.string(forKey: Key.triggerSide) ?? "right") ?? .right
        defaultMode = TranscriptionMode(
            rawValue: defaults.string(forKey: Key.defaultMode) ?? "intended") ?? .intended
        language = defaults.string(forKey: Key.language) ?? "fr"
        // Un fichier supprimé ou renommé depuis la dernière session ne doit
        // pas rester proposé comme destination : la dictée y serait perdue.
        noteFile = defaults.string(forKey: Key.noteFile)
            .map { URL(fileURLWithPath: $0) }
            .flatMap { FileManager.default.isWritableFile(atPath: $0.path) ? $0 : nil }
        livePreviewEnabled = defaults.object(forKey: Key.livePreview) as? Bool ?? true
        corpusEnabled = defaults.bool(forKey: Key.corpus)
        corpusKeepsAudio = defaults.bool(forKey: Key.corpusAudio)
    }

    /// Point de départ quand l'utilisateur passe à sa propre liste : le même
    /// contenu que la liste intégrée, pour qu'il parte de quelque chose qui
    /// marche plutôt que d'une page blanche.
    static let starterLexicon = [
        "useEffect", "useState", "component", "React", "Next.js", "TypeScript",
        "hook", "props", "state",
        "refactor", "merge", "commit", "branch", "pull request",
        "endpoint", "dependencies", "async", "await",
        "chunk",
    ]
}
