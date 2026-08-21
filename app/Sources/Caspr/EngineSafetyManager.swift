import Foundation
import Observation
import CasprCore

/// Garantit qu'il y a toujours un moteur capable d'écrire.
///
/// ## Le problème qu'il résout
///
/// Choisir un moteur dans les réglages écrivait le choix immédiatement, prêt ou
/// non. Cocher « CrisperWhisper » avant la fin du téléchargement suffisait donc
/// à casser la dictée : le contrôleur appelait le service local, le socket
/// n'existait pas, et l'échec ne nommait pas sa cause — l'utilisateur venait de
/// cliquer sur une option que l'interface présentait comme disponible.
///
/// Le même trou existait dans l'autre sens : supprimer les poids du seul modèle
/// installé laissait `engine == .crisperWhisper` pointer sur un moteur devenu
/// incapable de rien.
///
/// ## Deux mécanismes, et ils ne se confondent pas
///
/// - **Le commit transactionnel** (`isReady`) empêche d'*enregistrer* un choix
///   qui ne marche pas encore. C'est la prévention, et elle vit dans les vues :
///   elles manipulent un brouillon et n'appellent `commit` qu'à `.ready`.
/// - **Le repli** (`effectiveEngine`) rattrape ce que la prévention n'a pas pu
///   voir venir : un modèle supprimé par ailleurs, un service qui refuse de
///   démarrer, une langue qui change et que le moteur retenu ne couvre pas.
///   C'est la guérison, et elle vit au moment de dicter.
///
/// Le repli est **silencieux et temporaire** : il ne réécrit jamais la
/// préférence. Quelqu'un qui a choisi CrisperWhisper et dont le service est
/// arrêté doit retrouver CrisperWhisper quand il redémarre, pas découvrir que
/// l'application a décidé à sa place de repasser sur macOS.
@MainActor
@Observable
final class EngineSafetyManager {
    static let shared = EngineSafetyManager()

    private init() {}

    /// Le moteur qui doit réellement écrire, à cet instant.
    ///
    /// Trois rangs, dans cet ordre : le choix de l'utilisateur s'il tient, le
    /// dernier moteur qu'on a vu fonctionner, puis n'importe quelle version de
    /// macOS utilisable ici. Le dernier repli rend le choix de l'utilisateur
    /// tel quel — quand plus rien ne marche, mieux vaut échouer sur le moteur
    /// demandé, avec son message, que sur un substitut qui rendra l'erreur
    /// incompréhensible.
    var effectiveEngine: EngineChoice {
        let prefs = Preferences.shared
        let language = prefs.primaryLanguage
        let wanted = prefs.engine

        // `isReady`, et non `isAvailable` : pour CrisperWhisper, « disponible »
        // ne veut dire que « installé sur cette machine ». Le service arrêté,
        // ses poids sont toujours sur le disque, donc le repli ne se
        // déclenchait pas — et la dictée partait vers un socket fermé pour
        // échouer sur « le modèle est en cours de chargement », ce qui est
        // faux : rien ne chargeait, le service était éteint. Arrêter le
        // service pour libérer la mémoire cassait donc la dictée jusqu'à ce
        // qu'on pense à rouvrir les réglages.
        if isReady(wanted, for: language) { return wanted }
        if isReady(prefs.lastValidEngine, for: language) {
            return prefs.lastValidEngine
        }
        // `first { isReady }` et non `first` : cette dernière ligne prenait le
        // premier moteur *disponible*, et `availableSystemEngines` range Apple
        // Intelligence en tête. Sur une machine qui n'en a aucun modèle, elle
        // élisait donc précisément le moteur incapable d'écrire — c'est le
        // chemin qui a produit « Rien n'a été entendu » sur la VM, pendant que
        // l'aperçu en direct, lui, tournait très bien sur la Dictée.
        return EngineChoice.availableSystemEngines(for: language)
            .first { isReady($0, for: language) } ?? wanted
    }

    /// Le moteur retenu est-il en train d'être suppléé ?
    ///
    /// Sert aux bandeaux d'information : dire que la dictée marche *quand même*
    /// vaut mieux que laisser croire qu'elle est cassée, mais taire la
    /// substitution ferait passer une transcription de moindre qualité pour un
    /// caprice du moteur choisi.
    var isFallingBack: Bool {
        effectiveEngine != Preferences.shared.engine
    }

    /// Ce moteur est-il prêt à écrire, ici et dans cette langue ?
    ///
    /// C'est la condition du commit. `isAvailable` mesure déjà le gros — modèle
    /// installé, version de macOS présente, poids téléchargés — et
    /// CrisperWhisper demande en plus que son service réponde : des poids sur
    /// le disque ne transcrivent rien tant que le daemon n'est pas debout.
    func isReady(_ choice: EngineChoice, for language: String) -> Bool {
        guard choice.isAvailable(for: language) else { return false }
        // `isLocalService`, et non une égalité : la question posée est
        // « ce moteur a-t-il un démon à attendre ? ». Un second moteur local
        // comparé par égalité sauterait ce contrôle et serait déclaré prêt
        // sans service debout — exactement la panne que cette classe existe
        // pour empêcher, réintroduite par la porte de derrière.
        if choice.isLocalService { return EngineService.isAnswering }
        // ## Apple Intelligence exige une réponse, pas une absence de refus
        //
        // `isAvailable` est **volontairement optimiste** : tant que le système
        // n'a rien dit pour cette langue, elle ne la déclare pas indisponible,
        // sans quoi les cartes annonceraient « non pris en charge » pendant la
        // fraction de seconde où la question est en vol.
        //
        // Cette optimisme-là est sans danger dans une vue et ruineuse ici :
        // router une dictée vers un moteur dont personne n'a jamais mesuré
        // qu'il sait travailler, c'est ce qui a fait rendre une chaîne vide.
        // D'où la coupure entre les deux prédicats — « on peut l'afficher » et
        // « on peut lui confier ce que quelqu'un vient de dire ».
        if choice == .apple { return Language.appleSupports(language) == true }
        return true
    }

    /// Enregistre un choix, **et seulement s'il tient**.
    ///
    /// Rend `false` sans rien écrire quand le moteur n'est pas prêt : l'appelant
    /// garde alors son brouillon affiché et continue d'attendre, plutôt que de
    /// voir sa sélection sautiller entre deux valeurs.
    @discardableResult
    func commit(_ choice: EngineChoice, for language: String) -> Bool {
        guard isReady(choice, for: language) else {
            Log.info("moteur \(choice.rawValue) pas encore prêt — choix non enregistré")
            return false
        }
        let prefs = Preferences.shared
        prefs.engine = choice
        prefs.lastValidEngine = choice
        return true
    }

    /// Constate qu'un moteur vient d'écrire pour de bon.
    ///
    /// Appelé après une insertion réussie, pas après une simple vérification de
    /// disponibilité : un moteur qui répond à `isAvailable` peut encore échouer
    /// à la première phrase, et le repli doit désigner quelque chose dont on a
    /// la preuve, pas quelque chose dont on a l'espoir.
    func confirmWorking(_ choice: EngineChoice) {
        guard Preferences.shared.lastValidEngine != choice else { return }
        Preferences.shared.lastValidEngine = choice
    }
}
