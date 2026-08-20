import Foundation
import Observation

/// L'état du moteur local, relu périodiquement.
///
/// ## Pourquoi une horloge, et une seule
///
/// Ce que cette classe publie ne vient d'aucune notification : des fichiers sur
/// le disque, l'avis de `launchd`, et l'existence d'un socket. Rien là-dedans
/// n'est observable — le service peut finir de charger ses poids, ou tomber,
/// sans que l'application en soit informée. La seule façon de le savoir est de
/// regarder.
///
/// Trois vues regardaient donc, chacune avec sa propre boucle `.task(id:)` à
/// 500 ms : la carte CrisperWhisper, la carte du moteur final, et la fenêtre de
/// démarrage. Trois horloges pour la même question, trois occasions de
/// diverger, et jusqu'à trois appels à `launchctl` par demi-seconde sur le fil
/// principal — c'est-à-dire précisément la dépense que le cache d'une seconde
/// d'`EngineService.isRunning` a été ajouté pour contenir.
///
/// `PermissionsMonitor` résout déjà exactement ce problème pour les
/// autorisations, qui ne se signalent pas non plus. Celle-ci reprend son
/// patron, sans rien inventer : une horloge, un compteur d'observateurs, des
/// valeurs publiées que SwiftUI redessine tout seul.
///
/// ## Deux cadences, parce que les deux situations n'ont rien à voir
///
/// Pendant qu'il se passe quelque chose — installation en cours, service qui
/// démarre, modèle qui n'est pas encore prêt — on regarde deux fois par
/// seconde : c'est le moment où l'écran doit suivre ce que fait l'utilisateur.
///
/// Au repos, toutes les deux secondes. Il reste quelque chose à guetter — le
/// service peut s'arrêter de lui-même, ou être arrêté depuis un terminal — mais
/// personne n'attend l'information, et un sous-processus par demi-seconde
/// pendant qu'on lit tranquillement ses réglages est une dépense sans
/// contrepartie.
///
/// ## Elle ne décide de rien
///
/// Comme `LanguageSwitchCoordinator`, elle constate. Ce sont les vues qui
/// décident quoi faire d'un changement — enregistrer un brouillon, replier un
/// catalogue, se fermer. Leur logique n'a pas bougé.
@MainActor
@Observable
final class EngineStateMonitor {
    static let shared = EngineStateMonitor()

    private init() {}

    /// Le service répond-il sur son socket ? La seule mesure qui dise « prêt ».
    private(set) var isAnswering = EngineService.isAnswering
    /// `launchd` a-t-il lancé le processus ? Ce qui n'est pas la même question.
    private(set) var isRunning = EngineService.isRunning
    /// L'agent de lancement est-il en place ?
    private(set) var isInstalled = EngineService.isInstalled
    /// Le moteur Python est-il là où le descripteur le dit ?
    private(set) var engineIsAvailable = EngineInstall.isAvailable
    /// Les modèles dont les poids sont sur le disque.
    private(set) var downloadedModels = Set(CrisperWhisperModel.downloaded)

    /// L'étape restante **pour un modèle donné**.
    ///
    /// La règle est celle d'`EngineInstall`, et c'est bien la sienne qu'on
    /// appelle : seules les entrées changent — des valeurs relues une fois par
    /// tour, au lieu du disque et de `launchd` interrogés à chaque évaluation.
    /// C'est ce qui permet aux vues d'appeler cette fonction depuis leur corps
    /// sans lancer de sous-processus, alors qu'un seul rendu la relit plusieurs
    /// fois et que le rendu se refait deux fois par seconde pendant une
    /// installation.
    func step(for model: CrisperWhisperModel) -> EngineInstall.Step {
        EngineInstall.step(for: model,
                           engineAvailable: engineIsAvailable,
                           modelDownloaded: downloadedModels.contains(model),
                           serviceInstalled: isInstalled,
                           serviceRunning: isRunning,
                           serviceAnswering: isAnswering)
    }

    /// Y a-t-il quelque chose qui bouge, ou qu'on attend ?
    private var isUnsettled: Bool {
        EngineBootstrap.shared.isBusy
            || step(for: EngineInstall.selectedModel) != .ready
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var currentInterval: TimeInterval = 0

    /// Une vue commence à regarder.
    ///
    /// Relit **toujours**, même si une horloge tourne déjà. Une vue qui
    /// apparaît est évaluée une première fois avant son `onAppear` : sans cette
    /// relecture, elle se dessinerait sur les valeurs d'il y a deux secondes, ou
    /// sur celles laissées par la dernière fenêtre fermée. Ça coûte un
    /// `launchctl` par ouverture de fenêtre, pas un par seconde.
    func observe() {
        observers += 1
        refresh()
        schedule()
    }

    /// Une vue cesse de regarder. L'horloge s'arrête à la dernière.
    func release() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
        currentInterval = 0
    }

    /// Relit tout, tout de suite.
    ///
    /// À appeler après une action dont on connaît déjà l'effet — démarrer ou
    /// arrêter le service — plutôt que d'attendre le prochain battement.
    /// `launchctl` rend la main avant que le serveur ait retiré son socket : le
    /// cache d'`EngineService` est donc vidé d'abord, sans quoi on relirait la
    /// réponse d'avant.
    func refresh() {
        EngineService.forgetRunningState()
        isAnswering = EngineService.isAnswering
        isRunning = EngineService.isRunning
        isInstalled = EngineService.isInstalled
        engineIsAvailable = EngineInstall.isAvailable
        downloadedModels = Set(CrisperWhisperModel.downloaded)
    }

    /// Relit sans vider le cache d'`EngineService`.
    ///
    /// Le battement ordinaire : forcer un `launchctl` à chaque tour annulerait
    /// la mémoire d'une seconde qui existe pour ne pas noyer le fil principal.
    private func tick() {
        isAnswering = EngineService.isAnswering
        isRunning = EngineService.isRunning
        isInstalled = EngineService.isInstalled
        engineIsAvailable = EngineInstall.isAvailable
        downloadedModels = Set(CrisperWhisperModel.downloaded)
        // La cadence suit l'état, qui vient peut-être de changer.
        schedule()
    }

    /// Pose l'horloge à la bonne cadence, et ne la repose que si elle change.
    ///
    /// Sans horloge quand plus personne ne regarde : `observe()` appelle
    /// `schedule()` après avoir incrémenté le compteur, donc il y a toujours au
    /// moins un observateur ici.
    private func schedule() {
        guard observers > 0 else { return }
        let wanted: TimeInterval = isUnsettled ? 0.5 : 2
        // Reposée quand la cadence change, et quand il n'y en a pas : une
        // fenêtre rouverte après la dernière fermeture repart de zéro.
        guard timer == nil || wanted != currentInterval else { return }
        currentInterval = wanted
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: wanted, repeats: true) { _ in
            Task { @MainActor in self.tick() }
        }
    }
}
