import AppKit

/// Empêche de se servir de Caspr tant qu'il ne peut pas encore dicter.
///
/// ## Le problème
///
/// L'accueil pouvait se fermer à n'importe quelle étape, et il ne rouvrait
/// jamais : le drapeau `onboarded` n'est posé qu'au bouton « Terminer ». Rester
/// bloqué au milieu de l'étape des autorisations laissait donc une icône dans
/// la barre de menus, une touche de dictée qui ne faisait rien, et aucune
/// explication nulle part — l'accueil était précisément l'écran qui portait
/// l'explication, et on venait de le fermer.
///
/// ## Ce qui compte comme « socle minimal »
///
/// Trois choses, et pas une de plus : une langue retenue, le micro et
/// l'accessibilité accordés, et un moteur de macOS capable d'écrire dans cette
/// langue. Avec ça, on dicte. Le moteur final et la destination, eux, ont des
/// valeurs par défaut qui fonctionnent — quitter à l'étape 4 ou 5 n'empêche
/// rien, et bloquer dessus serait une exigence sans contrepartie.
///
/// ## Ce que la garde n'intercepte pas
///
/// **Le clic sur l'icône de la barre de menus.** Les documents demandaient de
/// le détourner aussi. Ce serait retirer le seul chemin vers « Quitter » :
/// quelqu'un qui refuse l'accessibilité en connaissance de cause se
/// retrouverait avec une fenêtre qui revient à chaque tentative de fermer
/// l'application. Le menu s'ouvre donc toujours, réduit à ce qui a du sens
/// tant que la configuration n'est pas finie.
///
/// **Et rien du tout une fois l'accueil terminé.** Perdre l'accessibilité six
/// mois plus tard — ce qui arrive à chaque mise à jour d'une copie signée ad
/// hoc — ne doit pas faire surgir l'accueil par-dessus le travail en cours. Le
/// menu porte déjà l'avertissement, et `TriggerCard` le bouton qui répare.
@MainActor
enum SetupRecoveryGuard {

    /// Caspr dispose-t-il du strict nécessaire pour dicter ?
    static var isMinimumViableSetupCompleted: Bool {
        let prefs = Preferences.shared
        guard !prefs.selectedLanguages.isEmpty else { return false }
        guard TriggerCard.isValid else { return false }
        // Le moteur de macOS, mesuré : sans lui, l'aperçu comme l'écriture
        // par défaut n'ont rien pour travailler.
        return AppleEngineCard.isValid
    }

    /// L'accueil doit-il reprendre la main ?
    ///
    /// Uniquement tant qu'il n'a jamais été mené à terme. Une fois `onboarded`
    /// posé, l'utilisateur a vu les explications et sait où les retrouver.
    static var shouldIntercept: Bool {
        !Preferences.shared.onboarded && !isMinimumViableSetupCompleted
    }

    /// Intercepte une action qui suppose une configuration terminée.
    ///
    /// Rend `true` quand l'action a été détournée, pour que l'appelant
    /// s'arrête là.
    @discardableResult
    static func intercept(_ reason: Reason,
                          reopening onboarding: OnboardingWindowController) -> Bool {
        guard shouldIntercept else { return false }
        Log.info("configuration incomplète — accueil rouvert (\(reason.rawValue))")
        onboarding.show()
        return true
    }

    enum Reason: String {
        case dictation
        case settings
        case launch
    }
}
