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
        /// Aucune version de macOS ne fonctionne ici pour cette langue.
        case noSystemEngine(language: String, reason: String)

        var message: String {
            switch self {
            case .appleVersionSwitched(_, let to, let language):
                let name = Language.named(language).displayName
                return "\(to.versionLabel ?? to.label) prend le relais en "
                    + "\(name) : l'autre version de macOS n'a pas ses modèles "
                    + "pour cette langue."
            case .modelMissing(let language):
                let lang = Language.named(language)
                return "Le modèle Apple Intelligence de \(lang.displayName) "
                    + "n'est pas encore installé (environ "
                    + "\(lang.estimatedSizeLabel))."
            case .crisperUncovered(let language):
                let name = Language.named(language).displayName
                return "CrisperWhisper ne transcrit pas le \(name) : macOS "
                    + "écrit à sa place tant que cette langue est active."
            case .noSystemEngine(_, let reason):
                return reason
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
            case .appleVersionSwitched, .noSystemEngine:
                return nil
            }
        }
    }

    private(set) var notice: Notice?

    /// Une confirmation brève, affichée puis retirée.
    ///
    /// « Le modèle est là, Apple Intelligence est de retour » n'a d'intérêt que
    /// dans les secondes qui suivent le téléchargement : laissé à l'écran, il
    /// devient un élément d'interface permanent qui ne dit plus rien.
    private(set) var confirmation: String?

    // MARK: - Audit

    /// Appelé quand la langue principale vient de changer.
    func primaryLanguageChanged() {
        notice = nil
        confirmation = nil
        audit()
    }

    /// Réévalue l'état complet et replie ce qui doit l'être.
    ///
    /// Sans effet de bord quand tout va bien : c'est le cas courant, et il ne
    /// doit produire aucune note. Un bandeau qui apparaît à chaque bascule
    /// finit par se faire ignorer, y compris le jour où il dit quelque chose.
    func audit() {
        let prefs = Preferences.shared
        let language = prefs.primaryLanguage

        // 1. La version de macOS. C'est la logique qui vivait dans le `didSet`
        //    de la langue — déplacée, pas dupliquée.
        let current = prefs.appleTechnology
        if !current.isAvailable(for: language) {
            if let usable = EngineChoice.systemEngine(preferring: current, for: language) {
                prefs.appleTechnology = usable
                notice = .appleVersionSwitched(from: current, to: usable,
                                               language: language)
            } else {
                notice = .noSystemEngine(
                    language: language,
                    reason: LegacySpeechEngine.unavailabilityReason(for: language)
                        ?? "Aucune version du moteur de macOS n'est utilisable "
                           + "ici pour cette langue.")
                return
            }
        }

        // 2. CrisperWhisper couvre-t-il cette langue ? Ses poids embarquent
        //    leurs langues : il n'y a rien à télécharger, mais la couverture
        //    n'est pas universelle, et écrire du vietnamien avec un modèle qui
        //    ne le connaît pas produit du charabia plutôt qu'une erreur.
        if prefs.finalEngine == .crisperWhisper,
           !Language.named(language).isCoveredByCrisperWhisper {
            notice = .crisperUncovered(language: language)
            return
        }

        // 3. Le modèle Apple Intelligence de cette langue est-il là ? Posé en
        //    dernier parce que c'est le seul cas qui se répare tout seul, en
        //    téléchargeant — et le seul dont la note porte un bouton qui agit.
        if prefs.appleTechnology == .apple,
           case .missing = SpeechAssets.shared.state(of: language) {
            notice = .modelMissing(language: language)
        }
    }

    // MARK: - Résolution

    /// Télécharge le modèle manquant, puis relève le repli.
    ///
    /// Le rétablissement est automatique et **constaté**, pas supposé : on
    /// réévalue l'état après l'installation plutôt que de décréter que tout va
    /// bien parce que la requête est revenue sans erreur.
    func installMissingModel(for language: String) async {
        await SpeechAssets.shared.ensure(language)
        guard SpeechAssets.shared.state(of: language).isReady else {
            audit()
            return
        }
        let name = Language.named(language).displayName
        notice = nil
        audit()
        // La confirmation n'a de sens que si rien d'autre ne cloche : la poser
        // par-dessus une note encore active dirait « c'est réglé » devant un
        // bandeau qui dit le contraire.
        if notice == nil {
            confirmation = "Modèle installé — Apple Intelligence réactivé en \(name)."
            Task {
                try? await Task.sleep(for: .seconds(3))
                if confirmation != nil { confirmation = nil }
            }
        }
    }

    func dismiss() {
        notice = nil
        confirmation = nil
    }
}
