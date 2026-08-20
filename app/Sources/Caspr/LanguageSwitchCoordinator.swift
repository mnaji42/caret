import Foundation
import Observation

/// Le point de passage unique quand la langue principale change.
///
/// ## Pourquoi un service, et pas un `didSet`
///
/// La logique existait déjà, en trois lignes dans le `didSet` de la langue :
/// si la version de macOS retenue ne sait pas écrire dans la nouvelle langue,
/// glisser vers celle qui sait. Elle était juste, et elle était **muette** —
/// l'utilisateur voyait son moteur changer sans qu'aucun écran ne le dise.
///
/// Changer de langue touche trois choses à la fois : l'aperçu en direct, le
/// moteur final, et le modèle qu'il faut avoir téléchargé. Les traiter à trois
/// endroits garantissait qu'un des trois finirait par être oublié. Ils sont
/// donc traités ici, une fois, et ce qui a été décidé d'autorité est **dit**.
///
/// Ce service ne bloque jamais rien. Il constate, replie si nécessaire, et
/// laisse une note que l'interface affiche avec l'action qui la lève.
@MainActor
@Observable
final class LanguageSwitchCoordinator {
    static let shared = LanguageSwitchCoordinator()

    private init() {}

    /// Ce qui a été replié, et pourquoi.
    ///
    /// Chaque cas porte de quoi proposer une action en un clic : on ne renvoie
    /// pas quelqu'un chercher dans un autre onglet ce qu'on peut lui offrir là
    /// où il regarde.
    enum Notice: Equatable {
        /// La version de macOS retenue ne sait pas écrire cette langue ; on est
        /// passé à l'autre.
        case appleVersionSwitched(from: EngineChoice, to: EngineChoice, language: String)
        /// Apple Intelligence n'a pas encore le modèle de cette langue.
        case modelMissing(language: String)
        /// CrisperWhisper ne couvre pas cette langue ; macOS écrit à sa place.
        case crisperUncovered(language: String)
        /// Les poids du modèle retenu ne sont pas sur le disque.
        case crisperWeightsMissing(model: CrisperWhisperModel)
        /// Tout est là, mais le service ne tourne pas — après un « Libérer la
        /// mémoire », ou parce que l'application vient de démarrer.
        case crisperNotRunning(model: CrisperWhisperModel)
        /// Aucune version de macOS ne fonctionne ici pour cette langue.
        case noSystemEngine(language: String, reason: String)

        @MainActor var message: String {
            switch self {
            case .appleVersionSwitched(_, let to, let language):
                let name = Language.named(language).displayName
                return "\(to.versionLabel ?? to.label) prend le relais en "
                    + "\(name) : l'autre version de macOS n'a pas ses modèles "
                    + "pour cette langue."
            case .modelMissing(let language):
                let lang = Language.named(language)
                // Dit ce qui se passe **en attendant**, comme le prototype. Le
                // titre annonce une bascule ; un message qui se contente de
                // constater l'absence du modèle laisse croire que la dictée ne
                // marche plus.
                let touched = Preferences.shared.finalEngine == .crisperWhisper
                    ? "L'aperçu en direct utilise"
                    : "Vos dictées (aperçu en direct et transcription finale) utilisent"
                return "Le modèle Apple Intelligence pour \(lang.displayName) "
                    + "n'est pas encore téléchargé sur ce Mac (environ "
                    + "\(lang.estimatedSizeLabel)). \(touched) la Dictée de "
                    + "macOS en attendant."
            case .crisperUncovered(let language):
                let name = Language.named(language).displayName
                return "CrisperWhisper ne transcrit pas le \(name) : macOS "
                    + "écrit à sa place tant que cette langue est active."
            case .crisperWeightsMissing(let model):
                return "Les poids de \(model.catalogueName) "
                    + "(\(model.downloadSize)) ne sont pas sur ce Mac. macOS "
                    + "écrit en attendant."
            case .crisperNotRunning(let model):
                return "Son service est arrêté, donc \(model.residentMemory) "
                    + "de mémoire sont libres. macOS écrit en attendant — "
                    + "votre choix de moteur n'a pas changé."
            case .noSystemEngine(_, let reason):
                return reason
            }
        }

        /// L'identité de la note, suffixée par la langue.
        ///
        /// Reprend la forme des `id` du prototype (`live-fallback-${code}`) :
        /// écarter un bandeau vaut pour cette langue, pas pour toutes.
        var id: String {
            switch self {
            case .appleVersionSwitched(_, _, let language):
                "apple-version-switched-\(language)"
            case .modelMissing(let language):
                "model-missing-\(language)"
            case .crisperUncovered(let language):
                "crisper-uncovered-\(language)"
            case .crisperWeightsMissing(let model):
                "crisper-weights-missing-\(model.rawValue)"
            case .crisperNotRunning(let model):
                "crisper-not-running-\(model.rawValue)"
            case .noSystemEngine(let language, _):
                "no-system-engine-\(language)"
            }
        }

        /// Le titre du bandeau — ce qui vient de changer, en une ligne.
        ///
        /// Le prototype distingue quatre cas selon que l'aperçu en direct, la
        /// passe finale, ou les deux se replient. Ici l'aperçu suit la version
        /// que la passe finale emploie dès que macOS écrit, si bien qu'un
        /// modèle manquant les emporte tous les deux ; il ne reste indépendant
        /// que sous CrisperWhisper, où la passe finale ne dépend pas d'Apple
        /// Intelligence. Les deux cas mènent donc aux deux titres du
        /// prototype, sans avoir à interroger deux réglages séparés.
        @MainActor var title: String {
            switch self {
            case .modelMissing:
                Preferences.shared.finalEngine == .crisperWhisper
                    ? "Aperçu Live : Bascule sur macOS Dictée"
                    : "Bascule sur macOS Dictée (Aperçu Live & Moteur Final)"
            case .appleVersionSwitched:
                "Moteur Final : Bascule sur macOS Dictée"
            case .crisperUncovered, .crisperWeightsMissing:
                "Moteur Final : Bascule sur macOS Natif (0 Mo)"
            case .crisperNotRunning:
                "CrisperWhisper est en veille"
            case .noSystemEngine:
                "Aucun moteur macOS pour cette langue"
            }
        }

        /// L'intitulé du bouton qui lève la note, quand il y en a un.
        var actionLabel: String? {
            switch self {
            case .modelMissing(let language):
                let lang = Language.named(language)
                return "Télécharger \(lang.name) (environ \(lang.estimatedSizeLabel))"
            case .crisperUncovered:
                return "Configurer dans Moteur IA"
            case .crisperWeightsMissing(let model):
                return "Télécharger les poids (\(model.downloadSize))"
            case .crisperNotRunning:
                return "Démarrer le service"
            case .appleVersionSwitched, .noSystemEngine:
                return nil
            }
        }
    }

    /// La note en cours, **recalculée à chaque lecture**.
    ///
    /// Elle était stockée, et posée par un `audit()` qu'il fallait penser à
    /// appeler. Deux conséquences. Choisir une langue dont le modèle n'est pas
    /// encore sondé produisait « rien à signaler », et l'état arrivait trop
    /// tard pour être vu : le bandeau n'apparaissait qu'en revenant sur
    /// l'onglet, parce qu'une autre vue rappelait `audit()` au passage. Et
    /// deux chemins de changement de langue sur trois oubliaient l'appel.
    ///
    /// Dérivée, elle suit ses entrées : la langue, les deux versions de macOS,
    /// le moteur final, l'inventaire des modèles. Toutes sont observables, donc
    /// SwiftUI redessine dès que l'une bouge — y compris quand le sondage du
    /// modèle se termine, ce qui est exactement le moment où la note devient
    /// vraie. C'est ce que fait le prototype, qui rappelle
    /// `evaluateLanguageSwitch` à chaque rendu.
    var notice: Notice? {
        guard let candidate = evaluate() else { return nil }
        return dismissed.contains(candidate.id) ? nil : candidate
    }

    /// Les notes écartées, par identité.
    ///
    /// L'identité porte la langue : écarter « le modèle espagnol manque » ne
    /// masque pas la même note pour l'allemand, et revenir à l'espagnol la
    /// redonne. C'est le `dismissedBanners` du prototype, dont les
    /// identifiants sont suffixés par le code de langue.
    private var dismissed: Set<String> = []

    /// Ce qui vient de se passer, dit une fois.
    ///
    /// Elle **reste** à l'écran, et disparaît en quittant la page ou au
    /// prochain changement de langue. Un texte qui s'évanouit tout seul oblige
    /// à refaire le geste pour savoir ce qu'il a produit ; et le geste sera
    /// loin quand on reviendra, où l'écran dira l'état plutôt que l'histoire.
    private(set) var confirmation: String?

    // MARK: - Audit

    /// Appelé quand la langue principale vient de changer.
    ///
    /// Il n'y a plus rien à recalculer — la note se déduit. Mais l'inventaire
    /// des modèles, lui, ne connaît que les langues déjà sondées : une langue
    /// fraîchement choisie y vaut « inconnue », ce qui n'est pas « manquante »
    /// et ne déclenchait donc aucune note. Le sondage se lance ici, et la note
    /// apparaît d'elle-même quand il rend son verdict.
    func primaryLanguageChanged() {
        confirmation = nil
        probePrimaryLanguage()
    }

    /// Demande à l'inventaire l'état du modèle de la langue courante.
    ///
    /// Sans effet s'il le connaît déjà. À appeler à l'affichage des vues qui
    /// montrent la note : au tout premier lancement, aucune langue n'a encore
    /// été sondée, et « inconnue » ne dit rien à personne.
    func probePrimaryLanguage() {
        let language = Preferences.shared.primaryLanguage
        Task { await SpeechAssets.shared.check(language) }
    }

    /// Interroge le système sur **toutes** les langues déclarées.
    ///
    /// Lancé au démarrage. Sans ça, la prise en charge de chaque langue n'est
    /// connue qu'après avoir ouvert l'écran qui la montre : la toute première
    /// dictée après un lancement se ferait sur un « on ne sait pas encore »,
    /// et c'est justement le moment où il vaut mieux savoir.
    func probeSelectedLanguages() {
        let languages = Preferences.shared.selectedLanguages
        Task {
            for language in languages { await SpeechAssets.shared.check(language) }
        }
    }

    /// Réévalue l'état complet et replie ce qui doit l'être.
    ///
    /// Sans effet de bord quand tout va bien : c'est le cas courant, et il ne
    /// doit produire aucune note. Un bandeau qui apparaît à chaque bascule
    /// finit par se faire ignorer, y compris le jour où il dit quelque chose.
    ///
    /// ## Ce service ne décide rien, il constate
    ///
    /// Il repliait en écrivant `prefs.finalAppleTechnology`. Deux raisons de ne
    /// plus le faire. D'abord c'était redondant : `EngineSafetyManager`
    /// calcule déjà le moteur effectif au moment de dicter, donc la dictée
    /// était juste sans cette écriture. Ensuite c'était destructeur — passer
    /// une heure sur une langue dont le modèle Apple Intelligence n'est pas
    /// téléchargé suffisait à convertir définitivement le réglage en
    /// « Dictée », et revenir au français ne le rendait pas. Le choix de
    /// quelqu'un n'est pas à nous.
    ///
    /// C'est aussi ce que fait le service du prototype : il rend un
    /// `effective` à côté du `requested`, sans jamais toucher au second.
    private func evaluate() -> Notice? {
        let prefs = Preferences.shared
        let language = prefs.primaryLanguage

        // 1. La version de macOS sait-elle écrire cette langue ?
        let requested = prefs.finalAppleTechnology
        let effective: EngineChoice
        if requested.isAvailable(for: language) {
            effective = requested
        } else if let usable = EngineChoice.systemEngine(preferring: requested,
                                                         for: language) {
            effective = usable
            return .appleVersionSwitched(from: requested, to: usable,
                                         language: language)
        } else {
            return .noSystemEngine(
                language: language,
                reason: LegacySpeechEngine.unavailabilityReason(for: language)
                    ?? "Aucune version du moteur de macOS n'est utilisable "
                       + "ici pour cette langue.")
        }

        // 2. CrisperWhisper couvre-t-il cette langue ? Ses poids embarquent
        //    leurs langues : il n'y a rien à télécharger, mais la couverture
        //    n'est pas universelle, et écrire du vietnamien avec un modèle qui
        //    ne le connaît pas produit du charabia plutôt qu'une erreur.
        if prefs.finalEngine == .crisperWhisper,
           !Language.named(language).isCoveredByCrisperWhisper {
            return .crisperUncovered(language: language)
        }

        // 3. Le modèle Apple Intelligence de cette langue est-il là ? Posé en
        //    dernier parce que c'est le seul cas qui se répare tout seul, en
        //    téléchargeant — et le seul dont la note porte un bouton qui agit.
        //    Mesuré sur la version **effective** : quand la version demandée
        //    ne sait déjà pas écrire cette langue, ses modèles ne sont pas le
        //    sujet, et l'annoncer remplacerait une note juste par une autre.
        if effective == .apple,
           case .missing = SpeechAssets.shared.state(of: language) {
            return .modelMissing(language: language)
        }

        return nil
    }

    // MARK: - Résolution

    /// Télécharge le modèle manquant, puis relève le repli.
    ///
    /// Le rétablissement est automatique et **constaté**, pas supposé : on
    /// réévalue l'état après l'installation plutôt que de décréter que tout va
    /// bien parce que la requête est revenue sans erreur.
    func installMissingModel(for language: String) async {
        await SpeechAssets.shared.ensure(language)
        guard SpeechAssets.shared.state(of: language).isReady else { return }
        let name = Language.named(language).displayName
        // La confirmation n'a de sens que si rien d'autre ne cloche : la poser
        // par-dessus une note encore active dirait « c'est réglé » devant un
        // bandeau qui dit le contraire.
        if notice == nil {
            announce("Modèle installé — Apple Intelligence réactivé en \(name).")
        }
    }

    /// Dit ce qui vient de se passer.
    ///
    /// Pour les gestes voulus, dont il n'y a rien à redire — arrêter le
    /// service, installer un modèle. Un bandeau d'avertissement dirait qu'il y
    /// a un problème là où quelqu'un a simplement obtenu ce qu'il demandait.
    func announce(_ message: String) {
        confirmation = message
    }

    /// Écarte la note affichée — celle-là, et pour cette langue-là.
    func dismiss() {
        if let shown = evaluate() { dismissed.insert(shown.id) }
        confirmation = nil
    }
}
