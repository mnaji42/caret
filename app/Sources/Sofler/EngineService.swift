import Foundation

/// Démarre et arrête le service CrisperWhisper selon qu'on en a besoin.
///
/// Le service garde le modèle chargé en permanence — c'est ce qui fait sa
/// vitesse, et ça coûte environ 3 Go de mémoire vive. Tant qu'il était le seul
/// moteur, le laisser tourner au démarrage de session allait de soi. Dès lors
/// qu'on peut lui préférer celui d'Apple, faire résider trois gigaoctets pour
/// un modèle dont personne ne se sert n'est plus défendable.
///
/// La règle est donc : le service tourne **si et seulement si** CrisperWhisper
/// est le moteur d'écriture, ou qu'il est coché dans une collecte active.
@MainActor
enum EngineService {
    // Une constante, lue aussi bien depuis le fil principal que depuis le
    // moteur socket qui travaille en fond.
    nonisolated static let label = "fr.lyriastudio.sofler.engine"

    /// Le service est-il installé sur cette machine ?
    ///
    /// Distinct de « chargé » : sans agent installé, l'utilisateur n'a jamais
    /// mis en place CrisperWhisper, et lui proposer de le démarrer n'aurait
    /// pas de sens.
    nonisolated static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: agentPath)
    }

    static var isRunning: Bool {
        run(["list", label]) != nil
    }

    /// Le service **répond**-il ? Ce qui n'est pas la même question.
    ///
    /// `isRunning` demande à launchd s'il a lancé le processus, et il répond
    /// oui dans la milliseconde. Le serveur Python, lui, charge le modèle
    /// **avant** d'ouvrir son socket — `engine.load()` puis `bind()`, dans cet
    /// ordre — et ce chargement demande de trente secondes à une minute au
    /// premier démarrage, le temps d'importer torch et de lire 1,6 Go de poids.
    ///
    /// Entre les deux, l'application affichait « Prêt · Turbo chargé » et la
    /// première dictée ne produisait rien : `connect()` échouait sur un socket
    /// qui n'existait pas encore. L'utilisateur changeait de moteur, revenait,
    /// et ça marchait — non pas grâce à l'aller-retour, mais parce qu'il avait
    /// pris le temps de le faire.
    ///
    /// La présence du fichier de socket est la seule mesure exacte : le
    /// serveur ne le crée qu'une fois le modèle en mémoire.
    nonisolated static var isAnswering: Bool {
        FileManager.default.fileExists(atPath: SocketSpeechEngine.defaultSocketPath)
    }

    /// Les poids sont-ils déjà sur la machine ?
    ///
    /// Séparé de « le service est installé », parce que les deux se défont
    /// indépendamment — désinstaller Sofler en gardant le modèle laisse
    /// précisément 1,6 Go de poids sans rien pour les charger. L'application
    /// annonçait alors qu'il fallait tout télécharger, ce qui est faux et
    /// coûterait une heure à quelqu'un qui le croirait.
    nonisolated static var modelIsDownloaded: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub/models--nyralabs--CrisperWhisper2.0_turbo")
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Ce qui manque pour que CrisperWhisper puisse écrire.
    ///
    /// Une seule question posée à un seul endroit : l'accueil et les réglages
    /// doivent dire la même chose, et « moteur indisponible » ne dit rien
    /// d'actionnable.
    nonisolated enum Readiness {
        /// Le service tourne, ou démarrera à la sélection.
        case ready
        /// Poids présents, mais rien pour les charger — cas d'une
        /// désinstallation qui a gardé le modèle.
        case serviceMissing
        /// Ni poids ni service.
        case notInstalled

        var summary: String {
            switch self {
            case .ready: "Prêt sur cette machine."
            case .serviceMissing:
                "Le modèle est déjà téléchargé, mais le service qui le charge "
                    + "n'est pas installé."
            case .notInstalled: "Pas encore installé sur cette machine."
            }
        }
    }

    nonisolated static var readiness: Readiness {
        if isInstalled { return .ready }
        return modelIsDownloaded ? .serviceMissing : .notInstalled
    }

    /// Ce qu'on affiche quand le socket ne répond pas.
    ///
    /// Trois causes très différentes se ressemblent vues du socket, et la
    /// consigne à donner n'est la même dans aucun des trois cas. Une seule
    /// phrase générique enverrait deux utilisateurs sur trois dans le mur.
    nonisolated static var unreachableAdvice: String {
        switch readiness {
        case .ready:
            // La cause de loin la plus fréquente est le démarrage, pas la
            // panne : le service est installé, donc il vient probablement
            // d'être lancé et lit encore ses poids. Mener avec « voir le
            // journal » enverrait chercher une panne là où il suffit
            // d'attendre dix secondes.
            "le modèle est en cours de chargement en mémoire — jusqu'à une "
                + "minute au premier démarrage. Réessayez dans un instant ; si "
                + "ça persiste, voir ~/Library/Logs/Sofler/engine.log"
        case .serviceMissing:
            "le modèle est là, mais le service qui le charge a été retiré — "
                + "réinstallez-le depuis le dépôt, ou repassez au moteur macOS"
        case .notInstalled:
            "CrisperWhisper n'est pas installé sur cette machine — "
                + "le moteur macOS écrit sans rien installer"
        }
    }

    /// Aligne l'état du service sur le besoin réel.
    ///
    /// Appelée à chaque changement de réglage plutôt qu'en continu : c'est le
    /// choix de l'utilisateur qui décide, pas un minuteur.
    static func reconcile(needed: Bool) {
        guard isInstalled else { return }
        switch (needed, isRunning) {
        case (true, false):
            NSLog("sofler: démarrage du moteur CrisperWhisper")
            _ = run(["bootstrap", domain, agentPath]) ?? run(["kickstart", "\(domain)/\(label)"])
        case (false, true):
            NSLog("sofler: arrêt du moteur CrisperWhisper — inutilisé")
            _ = run(["bootout", "\(domain)/\(label)"])
        default:
            break
        }
    }

    private static var domain: String { "gui/\(getuid())" }

    nonisolated private static var agentPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist").path
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
