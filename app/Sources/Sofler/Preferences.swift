import AppKit
import Observation

extension Notification.Name {
    /// Le déclencheur a changé : le tap clavier doit être reconstruit.
    static let soflerTriggerChanged = Notification.Name("sofler.trigger.changed")

    /// L'accessibilité vient d'être accordée, alors que l'application tourne
    /// déjà. Le tap clavier n'a pas pu être créé au lancement et rien ne le
    /// recrée de lui-même : sans ce signal, la touche Option reste morte
    /// jusqu'au prochain démarrage.
    static let soflerAccessibilityGranted = Notification.Name("sofler.accessibility.granted")
}

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
        static let triggerEnabled = "sofler.trigger.enabled"   // hérité, migré vers triggerKind
        static let triggerKind = "sofler.trigger.kind"
        static let defaultMode = "sofler.mode"
        static let language = "sofler.language"
        static let noteFile = "sofler.notes.file"
        static let livePreview = "sofler.preview.live"
        static let corpus = "sofler.corpus.enabled"
        static let corpusAudio = "sofler.corpus.audio"
        static let engine = "sofler.engine"
        static let shortcut = "sofler.shortcut"
        static let corpusEngines = "sofler.corpus.engines"
        static let onboarded = "sofler.onboarded"
        static let updateCheck = "sofler.update.check"
    }

    private let defaults = UserDefaults.standard

    // MARK: - Accueil

    /// L'accueil a-t-il été mené jusqu'au bout ?
    ///
    /// Un drapeau explicite, et non l'état des autorisations : quelqu'un peut
    /// refuser le micro en connaissance de cause, ou rester sur le moteur
    /// d'Apple sans jamais rien installer. Déduire l'accueil de ces états
    /// reviendrait à le rouvrir à chaque lancement chez ces gens-là.
    var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: Key.onboarded) }
    }

    /// Sofler doit-il regarder tout seul s'il existe une version plus récente ?
    ///
    /// **Désactivé par défaut**, et c'est un choix. C'est la seule requête
    /// réseau que l'application sache faire ; tant qu'on ne l'a pas activée,
    /// Sofler ne contacte rien ni personne, et la promesse « rien ne sort de
    /// votre Mac » n'a aucune exception à énoncer. Une exception, même
    /// bénigne, oblige à la mentionner partout et fait douter du reste.
    ///
    /// Ce que la requête envoie une fois activée : un GET sur l'API publique
    /// de GitHub, donc une adresse IP et rien d'autre — aucun identifiant,
    /// aucun compteur, rien de ce qui est dicté.
    ///
    /// Le bouton « Vérifier maintenant » des Réglages, lui, marche toujours :
    /// il est déclenché par l'utilisateur, qui sait donc ce qu'il demande.
    var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: Key.updateCheck) }
    }

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

    /// Comment on lance une dictée. **Une seule façon à la fois.**
    ///
    /// Les deux coexistaient, et c'était incohérent : quelqu'un qui se donnait
    /// la peine de choisir ⌘K voyait la touche Option continuer de déclencher
    /// dans son dos. Choisir un déclencheur, c'est écarter l'autre.
    ///
    /// Conséquence assumée : sous « raccourci clavier », maintenir Option
    /// n'ouvre plus les réglages non plus, puisque le tap n'est pas installé.
    /// Le menu reste là pour ça.
    enum TriggerKind: String, CaseIterable, Codable, Sendable {
        /// La touche Option seule, par un tap clavier. Demande l'accessibilité.
        case option
        /// Une combinaison classique, par Carbon. N'exige aucune autorisation.
        case shortcut
    }

    /// Le déclencheur est le seul réglage qui ne peut pas être simplement lu
    /// au moment de s'en servir : le tap clavier est construit une fois, avec
    /// son côté. Il faut donc prévenir pour qu'il soit reconstruit.
    var triggerKind: TriggerKind {
        didSet {
            defaults.set(triggerKind.rawValue, forKey: Key.triggerKind)
            NotificationCenter.default.post(name: .soflerTriggerChanged, object: nil)
        }
    }

    /// Raccourci clavier de dictée, personnalisable.
    ///
    /// Un raccourci global s'approprie la combinaison dans *toutes* les
    /// applications : celui qui convient dépend donc de ce que l'utilisateur
    /// fait tourner par ailleurs, et aucun défaut ne peut convenir à tout le
    /// monde.
    var dictateShortcut: HotkeyMonitor.Shortcut {
        didSet {
            defaults.set(["keyCode": Int(dictateShortcut.keyCode),
                          "modifiers": Int(dictateShortcut.modifiers),
                          "label": dictateShortcut.label], forKey: Key.shortcut)
            NotificationCenter.default.post(name: .soflerTriggerChanged, object: nil)
        }
    }

    var triggerSide: ModifierKeyMonitor.Side {
        didSet {
            defaults.set(triggerSide.rawValue, forKey: Key.triggerSide)
            NotificationCenter.default.post(name: .soflerTriggerChanged, object: nil)
        }
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

    /// Le moteur retenu au tout premier lancement.
    ///
    /// Choisi sur ce que la machine sait faire, pas sur son numéro de version.
    /// `.apple` était écrit en dur, ce qui donnait un défaut inutilisable sur
    /// un Mac Intel, sur un macOS antérieur à 26, ou sur toute machine sans
    /// Apple Intelligence : l'application s'ouvrait sur un moteur incapable
    /// d'écrire une ligne, et rien ne disait pourquoi.
    ///
    /// L'ordre suit la qualité attendue puis la disponibilité : le moteur de
    /// macOS 26 s'il est là, celui de la Dictée sinon, et CrisperWhisper en
    /// dernier — lui seul demande un téléchargement, il ne peut pas être un
    /// défaut.
    static func defaultEngine(for language: String) -> EngineChoice {
        if EngineChoice.apple.isAvailable(for: language) { return .apple }
        if EngineChoice.appleLegacy.isAvailable(for: language) { return .appleLegacy }
        return .apple
    }

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

    // MARK: - Moteur

    /// Moteur qui écrit réellement le texte inséré.
    ///
    /// Apple par défaut : il est inclus dans le système, sans téléchargement
    /// ni licence à accepter, et il transcrit pendant qu'on parle. Il ne sait
    /// pas écrire `useEffect` — c'est mesuré — donc l'utilisateur qui dicte du
    /// code choisira CrisperWhisper en connaissance de cause.
    var engine: EngineChoice {
        didSet {
            defaults.set(engine.rawValue, forKey: Key.engine)
            EngineService.reconcile(needed: needsLocalEngine)
        }
    }

    /// Moteurs à faire tourner **en plus** pour la collecte, après insertion.
    ///
    /// C'est ce qui permet de comparer sans changer d'outil : on dicte avec
    /// Apple, on archive aussi ce qu'aurait écrit CrisperWhisper.
    var corpusEngines: Set<EngineChoice> {
        didSet {
            defaults.set(corpusEngines.map(\.rawValue), forKey: Key.corpusEngines)
            EngineService.reconcile(needed: needsLocalEngine)
        }
    }

    /// Le service local doit-il tourner ? Un modèle de 3 Go ne reste pas
    /// chargé « au cas où » : il faut qu'il écrive, ou qu'il soit coché dans
    /// une collecte réellement active.
    var needsLocalEngine: Bool {
        if engine == .crisperWhisper { return true }
        return corpusEnabled && corpusEngines.contains(.crisperWhisper)
    }

    /// Moteurs qui produiront une transcription pour cette dictée.
    func enginesToCollect() -> Set<EngineChoice> {
        guard corpusEnabled else { return [engine] }
        return corpusEngines.union([engine])
    }

    // MARK: - Collecte

    /// Archive chaque dictée avec les textes des trois moteurs.
    ///
    /// Coûte une seconde passe du moteur par dictée, lancée après insertion et
    /// abandonnée si on réenchaîne — la latence de dictée ne se négocie pas.
    var corpusEnabled: Bool {
        didSet {
            defaults.set(corpusEnabled, forKey: Key.corpus)
            EngineService.reconcile(needed: needsLocalEngine)
        }
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
        // Migration : l'ancien réglage était un simple interrupteur sur la
        // touche Option, le raccourci restant actif en parallèle. Le couper
        // voulait donc dire « je préfère le raccourci ».
        if let stored = defaults.string(forKey: Key.triggerKind) {
            triggerKind = TriggerKind(rawValue: stored) ?? .option
        } else if let legacy = defaults.object(forKey: Key.triggerEnabled) as? Bool {
            triggerKind = legacy ? .option : .shortcut
        } else {
            triggerKind = .option
        }
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
        // Fermée par défaut — rien n'est archivé sans un geste explicite.
        // Mais une fois ouverte, complète : conserver l'audio et transcrire
        // avec tous les moteurs, parce qu'une collecte amputée ne répond pas
        // à la question qu'on se pose en l'activant.
        onboarded = defaults.bool(forKey: Key.onboarded)
        checksForUpdates = defaults.bool(forKey: Key.updateCheck)
        corpusEnabled = defaults.bool(forKey: Key.corpus)
        corpusKeepsAudio = defaults.object(forKey: Key.corpusAudio) as? Bool ?? true
        // Apple par défaut : inclus dans le système, aucun téléchargement,
        // aucune licence à accepter, et rien ne réside en mémoire. Une
        // installation neuve ne charge donc aucun modèle tant que
        // l'utilisateur n'a pas explicitement choisi le contraire.
        if let stored = defaults.dictionary(forKey: Key.shortcut),
           let code = stored["keyCode"] as? Int,
           let modifiers = stored["modifiers"] as? Int,
           let label = stored["label"] as? String {
            dictateShortcut = HotkeyMonitor.Shortcut(
                keyCode: UInt32(code), modifiers: UInt32(modifiers),
                label: label, id: HotkeyMonitor.Shortcut.dictate.id)
        } else {
            dictateShortcut = .dictate
        }
        let storedLanguage = defaults.string(forKey: Key.language) ?? "fr"
        engine = EngineChoice(rawValue: defaults.string(forKey: Key.engine) ?? "")
            ?? Self.defaultEngine(for: storedLanguage)
        corpusEngines = defaults.stringArray(forKey: Key.corpusEngines)
            .map { Set($0.compactMap(EngineChoice.init(rawValue:))) }
            ?? Set(EngineChoice.allCases)
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
