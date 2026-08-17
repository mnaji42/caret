import AppKit
import Observation
import SoflerCore

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
        static let language = "sofler.language"          // hérité, migré vers languages
        static let languages = "sofler.languages.selected"
        static let noteFile = "sofler.notes.file"
        static let livePreview = "sofler.preview.live"
        static let corpus = "sofler.corpus.enabled"
        static let corpusAudio = "sofler.corpus.audio"
        static let engine = "sofler.engine"              // hérité, migré vers final/apple
        static let finalEngine = "sofler.engine.final"
        static let appleTechnology = "sofler.engine.apple"
        static let liveTechnology = "sofler.engine.live"
        static let shortcut = "sofler.shortcut"
        static let corpusEngines = "sofler.corpus.engines"
        static let onboarded = "sofler.onboarded"
        static let updateCheck = "sofler.update.check"
        static let lastValidEngine = "sofler.engine.lastValid"
        static let habits = "sofler.habits"
        /// Marque qu'une installation antérieure au multi-langues a été
        /// reprise. Sert à ne pas changer sous les pieds de quelqu'un des
        /// défauts qui n'ont bougé que pour les installations neuves.
        static let migratedSchema = "sofler.schema.migrated"
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

    /// Les langues de travail, en locales complètes — `["fr-FR", "en-US"]`.
    ///
    /// **L'ordre porte du sens, et il est le seul à en porter :** l'élément
    /// d'indice 0 est la langue principale, celle avec laquelle on dicte. Le
    /// reste est ce qu'on a déclaré vouloir employer, ce qui sert à savoir
    /// quels modèles récupérer d'avance plutôt qu'au moment où l'on bascule.
    ///
    /// Ne peut jamais être vide : sans langue, aucun moteur ne sait quoi
    /// charger, et l'application n'aurait plus qu'à échouer à chaque dictée. Un
    /// appel qui la viderait est donc corrigé sur place plutôt que refusé — le
    /// code appelant n'a aucun moyen raisonnable de traiter ce refus.
    var selectedLanguages: [String] {
        didSet {
            // Dédoublonnage en conservant l'ordre : `Set` le perdrait, et
            // l'ordre *est* l'information ici.
            var seen: Set<String> = []
            let cleaned = selectedLanguages.filter { seen.insert($0).inserted }
            if cleaned.isEmpty {
                selectedLanguages = [Language.fallback]
                return
            }
            if cleaned != selectedLanguages {
                selectedLanguages = cleaned
                return
            }
            defaults.set(selectedLanguages, forKey: Key.languages)
            // La langue principale a pu changer de place. Tout ce qui en dépend
            // — la version de macOS capable de l'écrire, le moteur final — est
            // réévalué au même endroit pour tout le monde.
            if oldValue.first != selectedLanguages.first {
                LanguageSwitchCoordinator.shared.primaryLanguageChanged()
            }
        }
    }

    /// La langue avec laquelle on dicte, c'est-à-dire la première de la liste.
    ///
    /// Calculée plutôt que stockée : deux champs pour une seule vérité, c'est
    /// une occasion de les voir diverger, et ce projet en a déjà payé une
    /// (cf. `DictationController`, où les réglages étaient recopiés).
    ///
    /// L'affecter **déplace** la langue en tête au lieu de l'ajouter : on
    /// choisit sa langue principale parmi celles qu'on a déclarées, on n'en
    /// déclare pas une nouvelle par ce chemin.
    var primaryLanguage: String {
        get { selectedLanguages.first ?? Language.fallback }
        set {
            guard selectedLanguages.contains(newValue) else { return }
            guard newValue != selectedLanguages.first else { return }
            selectedLanguages = [newValue]
                + selectedLanguages.filter { $0 != newValue }
        }
    }

    /// Les langues déclarées, en plus de la principale.
    var secondaryLanguages: [String] { Array(selectedLanguages.dropFirst()) }

    /// Ce que l'utilisateur a dit de son usage, à l'écran 2 de l'accueil.
    ///
    /// Persisté, alors que ça ne pilote aucun comportement : c'est le seul
    /// moyen pour l'écran 4 de justifier sa recommandation quand on y revient
    /// après avoir quitté l'application en cours de route. Un conseil qui
    /// change entre deux lancements parce que sa prémisse a été oubliée est
    /// pire qu'un conseil absent.
    var habits: UsageHabits {
        didSet {
            guard let data = try? JSONEncoder().encode(habits) else { return }
            defaults.set(data, forKey: Key.habits)
        }
    }

    /// Le moteur conseillé, compte tenu des langues retenues.
    ///
    /// La couverture est mesurée sur **toutes** les langues déclarées, pas
    /// seulement la principale : conseiller un moteur qui n'en couvre qu'une
    /// partie reviendrait à promettre un repli silencieux à la première
    /// bascule.
    var recommendation: EngineRecommendation {
        EngineRecommendation.advise(
            habits: habits,
            primaryBase: Language.named(primaryLanguage).base,
            crisperCoversAll: activeLanguages.allSatisfy(\.isCoveredByCrisperWhisper))
    }

    /// Le catalogue restreint à ce que l'utilisateur a retenu, dans son ordre.
    var activeLanguages: [Language] { selectedLanguages.map(Language.named) }

    /// La langue principale, comme objet.
    var primary: Language { Language.named(primaryLanguage) }

    /// Nom historique de la langue principale.
    ///
    /// Conservé parce que tout ce qui transcrit le lit — moteurs, aperçu,
    /// corpus — et que ces appels ne gagneraient rien à être réécrits : « la
    /// langue » y désigne bien la langue courante. Il rend désormais une locale
    /// complète (`fr-FR`) là où il rendait un code court (`fr`), ce qui vaut
    /// mieux pour `SpeechTranscriber` et `SFSpeechRecognizer`, dont les modèles
    /// sont fournis par région.
    ///
    /// **La conversion vers le code court se fait à la frontière du socket**,
    /// et nulle part ailleurs : Whisper compose le jeton `<|fr|>`, et `fr-FR`
    /// lui donnerait un jeton inconnu sans lever la moindre erreur.
    /// Cf. `SocketSpeechEngine` et `Language`.
    var language: String {
        get { primaryLanguage }
        set {
            // Une langue qu'on n'a pas déclarée devient déclarée, et
            // principale : c'est le sens de l'ancien réglage à choix unique,
            // et le seul qui ne surprenne pas l'appelant.
            if selectedLanguages.contains(newValue) {
                primaryLanguage = newValue
            } else {
                selectedLanguages = [newValue] + selectedLanguages
            }
        }
    }

    /// Le moteur retenu au tout premier lancement.
    ///
    /// Choisi sur ce que la machine sait faire, pas sur son numéro de version.
    /// `.apple` était écrit en dur, ce qui donnait un défaut inutilisable sur
    /// un Mac Intel, sur un macOS antérieur à 26, ou sur toute machine sans
    /// Apple Intelligence : l'application s'ouvrait sur un moteur incapable
    /// d'écrire une ligne, et rien ne disait pourquoi.
    ///
    /// L'ordre suit la qualité attendue puis la disponibilité : le moteur de
    /// macOS 26 s'il est là, celui de la Dictée sinon. CrisperWhisper n'est
    /// jamais un défaut — lui seul demande un téléchargement.
    ///
    /// Quand aucune version de macOS ne marche ici, on retient quand même la
    /// famille : l'interface montre alors la ligne « macOS » avec la raison
    /// mesurée et le bouton qui y mène, ce qui vaut mieux que de désigner un
    /// moteur que rien n'explique.
    static func defaultEngine(for language: String) -> EngineChoice {
        EngineChoice.systemEngine(preferring: .apple, for: language) ?? .apple
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
    /// Qui écrit le texte définitif : macOS, ou CrisperWhisper.
    ///
    /// C'est **la** décision, celle qu'on prend à l'écran 4 de l'accueil. La
    /// version de macOS employée n'en est pas une autre : c'est un détail
    /// interne à « macOS », au même titre que le modèle sous CrisperWhisper.
    enum FinalEngineChoice: String, CaseIterable, Codable, Sendable {
        case apple
        case crisperWhisper = "crisperwhisper"
    }

    var finalEngine: FinalEngineChoice {
        didSet {
            defaults.set(finalEngine.rawValue, forKey: Key.finalEngine)
            EngineService.reconcile(needed: needsLocalEngine)
        }
    }

    /// La version de macOS retenue — Apple Intelligence ou Dictée.
    ///
    /// Toujours une des deux, jamais CrisperWhisper : c'est ce que garantit le
    /// point d'entrée `engine`, seul chemin d'écriture exposé aux vues.
    var appleTechnology: EngineChoice {
        didSet {
            defaults.set(appleTechnology.rawValue, forKey: Key.appleTechnology)
        }
    }

    /// La version de macOS qui alimente l'aperçu en direct.
    ///
    /// Stockée à part, mais **pas indépendante**, et c'est délibéré. Quand
    /// macOS écrit, l'aperçu emploie exactement la version qui écrira : il
    /// devient alors une vraie préversion du texte inséré, et non une seconde
    /// opinion qui ne ressemblera pas au résultat. Les documents de conception
    /// demandaient deux réglages libres ; ça aurait fait afficher pendant la
    /// dictée un texte qu'aucun moteur n'allait produire.
    ///
    /// La valeur stockée ne sert donc que lorsque CrisperWhisper écrit — cas où
    /// aucune préversion fidèle n'est possible, puisque le moteur final ne
    /// travaille qu'une fois la phrase finie.
    var liveEngineTechnology: EngineChoice {
        get { finalEngine == .apple ? appleTechnology : storedLiveTechnology }
        set {
            storedLiveTechnology = newValue
            if finalEngine == .apple { appleTechnology = newValue }
        }
    }

    private var storedLiveTechnology: EngineChoice {
        didSet {
            defaults.set(storedLiveTechnology.rawValue, forKey: Key.liveTechnology)
        }
    }

    /// Le moteur qui écrit, recomposé à partir des deux réglages ci-dessus.
    ///
    /// Point d'entrée historique, et toujours le bon : tout ce qui transcrit
    /// veut savoir « qui écrit », pas « quelle case est cochée où ». L'affecter
    /// décompose vers le bon couple, ce qui évite à chaque appelant de savoir
    /// que la décision est désormais rangée en deux morceaux.
    var engine: EngineChoice {
        get { finalEngine == .crisperWhisper ? .crisperWhisper : appleTechnology }
        set {
            switch newValue {
            case .crisperWhisper:
                finalEngine = .crisperWhisper
            case .apple, .appleLegacy:
                appleTechnology = newValue
                finalEngine = .apple
            }
        }
    }

    /// Le dernier moteur dont on a **constaté** qu'il savait écrire.
    ///
    /// Filet de sécurité du commit transactionnel : tant qu'un moteur exploré
    /// dans les réglages n'est pas prêt — poids en cours de téléchargement,
    /// service arrêté, modèle supprimé — la dictée continue avec celui-ci
    /// plutôt que d'échouer. Sans lui, cocher « CrisperWhisper » avant la fin
    /// du téléchargement cassait la dictée en silence, et rien ne disait
    /// pourquoi. Cf. `EngineSafetyManager`.
    var lastValidEngine: EngineChoice {
        didSet { defaults.set(lastValidEngine.rawValue, forKey: Key.lastValidEngine) }
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
    ///
    /// Filtrés sur ce que la machine sait faire, dans la langue en cours. Sans
    /// ce filtre, une case cochée pour un moteur que cette machine n'aura
    /// jamais écrivait `skipped: "apple: indisponible"` à **chaque** dictée,
    /// indéfiniment. Or `skipped` sert à repérer l'accident — une passe
    /// abandonnée parce qu'on a réenchaîné, un moteur qui a échoué — et une
    /// ligne qui se répète toujours à l'identique le noie.
    ///
    /// Le moteur d'écriture, lui, y figure quoi qu'il arrive : c'est lui qui
    /// vient d'écrire, sa transcription existe déjà.
    func enginesToCollect() -> Set<EngineChoice> {
        guard corpusEnabled else { return [engine] }
        return corpusEngines
            .filter { $0.isAvailable(for: language) }
            .union([engine])
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
        // Reprend-on une installation antérieure au multi-langues ?
        //
        // La question n'est pas rhétorique : deux défauts changent avec cette
        // version, et les changer sous les pieds de quelqu'un qui utilise déjà
        // Sofler modifierait la qualité de ses transcriptions au milieu d'une
        // collecte en cours — exactement ce que le corpus existe pour mesurer.
        // On ne peut pas se contenter de l'absence des nouvelles clés : une
        // installation neuve ne les a pas non plus. C'est la présence des
        // **anciennes** qui tranche.
        let isExistingInstall = defaults.object(forKey: Key.migratedSchema) == nil
            && (defaults.object(forKey: Key.onboarded) != nil
                || defaults.object(forKey: Key.language) != nil
                || defaults.object(forKey: Key.engine) != nil)
        defaults.set(true, forKey: Key.migratedSchema)

        // Liste vide pour qui découvre Sofler : la liste intégrée est du
        // vocabulaire de développement web, et un médecin ou un juriste n'a
        // rien à faire de `useEffect`. Mais elle reste en place pour qui
        // l'utilisait déjà — cf. `isExistingInstall`.
        lexicon = defaults.stringArray(forKey: Key.lexicon) ?? []
        useDefaultLexicon = defaults.object(forKey: Key.useDefaultLexicon) as? Bool
            ?? isExistingInstall
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

        // Migration des langues : le réglage était un code court unique
        // (« fr »), il devient une liste de locales complètes (« fr-FR »).
        //
        // Les modèles de macOS sont fournis *par région* : « fr » ne suffit pas
        // à désigner ce qu'il faut télécharger, et `SFSpeechRecognizer` répond
        // mieux à une locale exacte. La région retenue est celle de la machine
        // quand le catalogue la connaît — un francophone au Canada obtient
        // `fr-CA` plutôt que `fr-FR`.
        let languages: [String]
        if let stored = defaults.stringArray(forKey: Key.languages), !stored.isEmpty {
            languages = stored
        } else if let legacy = defaults.string(forKey: Key.language) {
            languages = [Language.preferred(for: legacy)]
        } else {
            languages = [Language.fallback]
        }
        selectedLanguages = languages
        // La langue principale sert plus bas à choisir un moteur par défaut.
        // Elle passe par une locale, et non par `selectedLanguages` : sous
        // `@Observable`, relire une propriété stockée avant que toutes le
        // soient est refusé — et le contournement serait un ordre
        // d'initialisation fragile plutôt qu'une variable de trois caractères.
        let primary = languages[0]

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
        // Migration des moteurs : un réglage unique (`sofler.engine`) devient
        // deux décisions distinctes — qui écrit, et avec quelle version de
        // macOS. L'ancienne valeur porte les deux à la fois, on la décompose.
        let legacyEngine = EngineChoice(rawValue: defaults.string(forKey: Key.engine) ?? "")
        let resolvedFinal: FinalEngineChoice
        if let stored = defaults.string(forKey: Key.finalEngine),
           let choice = FinalEngineChoice(rawValue: stored) {
            resolvedFinal = choice
        } else {
            resolvedFinal = legacyEngine == .crisperWhisper ? .crisperWhisper : .apple
        }
        finalEngine = resolvedFinal
        // La version de macOS : celle explicitement rangée, sinon celle que
        // l'ancien réglage désignait s'il en désignait une, sinon celle que
        // cette machine sait faire tourner — mesuré, jamais déduit du numéro
        // de version.
        let resolvedApple = EngineChoice(rawValue: defaults.string(forKey: Key.appleTechnology) ?? "")
            ?? (legacyEngine?.isSystem == true ? legacyEngine : nil)
            ?? Self.defaultEngine(for: primary)
        appleTechnology = resolvedApple
        storedLiveTechnology = EngineChoice(rawValue: defaults.string(forKey: Key.liveTechnology) ?? "")
            ?? Self.defaultEngine(for: primary)
        // Au premier lancement, le dernier moteur valide est celui qu'on vient
        // de retenir : rien n'a encore échoué, et démarrer sur un repli
        // arbitraire ferait dicter avec autre chose que ce qui est affiché.
        lastValidEngine = EngineChoice(rawValue: defaults.string(forKey: Key.lastValidEngine) ?? "")
            ?? (resolvedFinal == .crisperWhisper ? .crisperWhisper : resolvedApple)

        habits = defaults.data(forKey: Key.habits)
            .flatMap { try? JSONDecoder().decode(UsageHabits.self, from: $0) }
            ?? UsageHabits()

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
