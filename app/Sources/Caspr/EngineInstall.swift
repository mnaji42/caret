import Foundation

/// Le lien entre l'application et le moteur Python installé à côté d'elle.
///
/// Caspr est un bundle de deux mégaoctets ; CrisperWhisper demande Python,
/// torch et transformers, soit plus d'un gigaoctet de bibliothèques qu'on ne
/// peut raisonnablement ni embarquer ni télécharger depuis l'application. Le
/// moteur s'installe donc à part, une fois, depuis le Terminal.
///
/// Mais **une fois seulement**. Le script d'installation dépose ici un
/// descripteur disant où il s'est mis, et à partir de là l'application sait
/// tout faire elle-même : écrire l'agent de lancement, démarrer et arrêter le
/// service, changer de modèle. Sans ce descripteur, une application installée
/// depuis le .dmg n'a aucun moyen de deviner où vit un dépôt git, et chaque
/// geste retomberait dans le Terminal.
@MainActor
enum EngineInstall {

    /// Ce que le script d'installation laisse derrière lui.
    struct Descriptor: Codable {
        /// Dossier du projet Python, celui qui contient `pyproject.toml`.
        var project: String
        /// Chemin absolu de `uv` — le PATH d'un agent de lancement n'est pas
        /// celui d'un terminal, et « uv » tout court n'y est pas trouvable.
        var uv: String
        /// Modèle à charger. Écrit par l'application quand on en change.
        var model: CrisperWhisperModel
    }

    static var descriptorURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Caspr/engine.json")
    }

    static var descriptor: Descriptor? {
        guard let data = try? Data(contentsOf: descriptorURL) else { return nil }
        return try? JSONDecoder().decode(Descriptor.self, from: data)
    }

    /// Le moteur Python est-il installé et utilisable ?
    ///
    /// On revérifie les chemins plutôt que de croire le descripteur : un dépôt
    /// déplacé ou effacé laisserait un fichier qui ment.
    static var isAvailable: Bool {
        guard let d = descriptor else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: d.project) && fm.fileExists(atPath: d.uv)
    }

    static var selectedModel: CrisperWhisperModel { descriptor?.model ?? .turbo }

    // MARK: - Étapes restantes

    /// Ce qui manque encore, dans l'ordre où il faut s'en occuper.
    ///
    /// Un seul état à interroger, pour que l'accueil, les réglages et les
    /// messages d'erreur racontent la même histoire.
    enum Step: Equatable {
        /// Ni Python ni moteur : il faut passer une fois par le Terminal.
        case engineMissing
        /// Moteur installé, mais les poids du modèle choisi ne sont pas là.
        case modelMissing(CrisperWhisperModel)
        /// Tout est là, le service n'est pas encore en place.
        case serviceMissing
        /// Service installé mais arrêté.
        case serviceStopped
        /// Service lancé, modèle pas encore en mémoire — donc pas utilisable.
        ///
        /// Cet état manquait, et son absence coûtait cher : `serviceStopped`
        /// et `ready` étant les deux seules possibilités, tout service lancé
        /// était déclaré prêt. Pendant la minute que dure le chargement des
        /// poids, l'accueil affichait « Prêt » et la dictée ne rendait rien.
        case serviceStarting
        /// Prêt à écrire.
        case ready
    }

    /// L'étape, mesurée à l'instant.
    ///
    /// Interroge le disque et `launchd` à chaque appel : c'est ce qu'il faut
    /// hors des vues — le chemin de dictée, l'installateur — où l'on veut la
    /// vérité, pas une valeur d'il y a deux secondes.
    ///
    /// Les vues, elles, passent par `EngineStateMonitor`, qui pose la **même
    /// règle** sur des valeurs relues une fois par tour. C'est la surcharge
    /// ci-dessous qui la porte, pour qu'il n'y en ait qu'une : une règle
    /// recopiée à deux endroits finit par diverger, et c'est exactement le
    /// défaut que ce moniteur existe pour supprimer.
    static func step(for model: CrisperWhisperModel) -> Step {
        step(for: model,
             engineAvailable: isAvailable,
             modelDownloaded: model.isDownloaded,
             serviceInstalled: EngineService.isInstalled,
             serviceRunning: EngineService.isRunning,
             serviceAnswering: EngineService.isAnswering)
    }

    /// La règle, sur des faits déjà constatés.
    ///
    /// L'ordre importe : chaque étape suppose la précédente franchie, et
    /// annoncer « service arrêté » à quelqu'un dont les poids ne sont pas
    /// téléchargés l'enverrait démarrer un service qui n'a rien à charger.
    static func step(for model: CrisperWhisperModel,
                     engineAvailable: Bool,
                     modelDownloaded: Bool,
                     serviceInstalled: Bool,
                     serviceRunning: Bool,
                     serviceAnswering: Bool) -> Step {
        guard engineAvailable else { return .engineMissing }
        guard modelDownloaded else { return .modelMissing(model) }
        guard serviceInstalled else { return .serviceMissing }
        guard serviceRunning else { return .serviceStopped }
        // launchd dit « lancé », le socket dit « prêt ». Cf.
        // EngineService.isAnswering : ce n'est pas la même question.
        return serviceAnswering ? .ready : .serviceStarting
    }

    // MARK: - Agent de lancement

    /// Écrit l'agent et démarre le service, avec le modèle demandé.
    ///
    /// L'application écrit ce fichier elle-même plutôt que d'appeler le script
    /// du dépôt : elle doit pouvoir changer de modèle sans que l'utilisateur
    /// retourne dans un terminal, et un bouton qui lance un script qu'on n'a
    /// pas forcément est un bouton cassé.
    @discardableResult
    static func installService(model: CrisperWhisperModel) -> Bool {
        guard var d = descriptor, isAvailable else { return false }
        d.model = model
        save(d)

        let label = EngineService.label
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/Caspr")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                d.uv, "run", "--project", d.project,
                "python", "-m", "caspr_engine.server",
                "--model", model.identifier,
            ],
            "WorkingDirectory": d.project,
            // `uv run` refait la recherche d'interpréteur à chaque démarrage du
            // service, donc il peut déclencher l'amorce `/usr/bin/python3` et
            // ses 19 Go d'outils Xcode exactement comme l'installation. Le
            // dialogue apparaîtrait alors sans qu'aucune fenêtre de Caspr soit
            // ouverte pour l'expliquer. Cf. EngineBootstrap.toolEnvironment.
            // Le `PATH` reprend celui d'un agent launchd, précédé du dossier
            // des leurres : `uv run` réinstallerait un Python si celui-ci
            // venait à manquer, et déclencherait alors l'amorce Xcode sans
            // qu'aucune fenêtre de Caspr soit ouverte pour l'expliquer.
            // Cf. EngineBootstrap.prepareShims.
            "EnvironmentVariables": [
                "UV_MANAGED_PYTHON": "1",
                "PATH": "\(EngineBootstrap.shimDirectory.path)"
                    + ":/usr/bin:/bin:/usr/sbin:/sbin",
            ],
            "RunAtLoad": true,
            // On relance s'il tombe, sans insister en boucle quand le
            // démarrage échoue vraiment : le modèle occupe plusieurs
            // gigaoctets, un cycle serré épuiserait la machine.
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 30,
            "StandardOutPath": logs.appending(path: "engine.log").path,
            "StandardErrorPath": logs.appending(path: "engine.log").path,
            "ProcessType": "Interactive",
        ]

        let agents = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents")
        try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let url = agents.appending(path: "\(label).plist")

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0),
            (try? data.write(to: url)) != nil
        else { return false }

        // Recharger un service déjà présent échoue : on le sort d'abord.
        _ = launchctl(["bootout", "gui/\(getuid())/\(label)"])
        let started = launchctl(["bootstrap", "gui/\(getuid())", url.path])
        // L'état mémorisé vient d'être rendu faux par ce qu'on vient de faire.
        EngineService.forgetRunningState()
        return started
    }

    /// Change le modèle chargé, ce qui suppose de redémarrer le service.
    @discardableResult
    static func select(model: CrisperWhisperModel) -> Bool {
        guard var d = descriptor else { return false }
        d.model = model
        save(d)
        guard EngineService.isInstalled else { return true }
        return installService(model: model)
    }

    /// Écrit le descripteur de toutes pièces.
    ///
    /// C'était `setup-engine.sh` qui le déposait, en fin de course. Depuis que
    /// l'installation se fait dans l'application, c'est elle qui le remplit —
    /// mais le format ne change pas d'un octet : une installation faite au
    /// Terminal du temps où c'était la seule voie reste lisible, et continue
    /// de fonctionner sans rien réinstaller.
    static func write(project: String, uv: String, model: CrisperWhisperModel) {
        save(Descriptor(project: project, uv: uv, model: model))
    }

    /// Retire les poids d'un modèle, à la corbeille.
    ///
    /// Si c'est celui qui tourne, le service s'arrête et l'écriture retombe
    /// sur le moteur de macOS. Sans ce repli, la dictée suivante échouerait
    /// sur un modèle absent — et rien n'est plus déroutant qu'une application
    /// qui cesse d'écrire après une suppression dont on ne voit pas le
    /// rapport. Le repli est la conséquence annoncée du bouton, pas un effet
    /// de bord.
    ///
    /// **Le repli change de famille, jamais de version.** C'était
    /// `prefs.engine = .apple`, et ce point d'entrée porte les deux décisions
    /// à la fois : il écrivait donc aussi `finalAppleTechnology = .apple`.
    /// Quelqu'un qui avait choisi la Dictée se retrouvait sur Apple
    /// Intelligence pour avoir supprimé des poids Whisper — c'est-à-dire un
    /// réglage effacé par un geste qui ne le concernait pas, et sur un Mac
    /// Intel ou une machine sans Apple Intelligence, un moteur incapable
    /// d'écrire. `finalEngine` seul dit « ce n'est plus CrisperWhisper qui
    /// écrit » et laisse intacte la version de macOS retenue.
    /// Cf. `CrisperEngineCard.stop()`, qui fait déjà ce choix.
    @discardableResult
    static func remove(model: CrisperWhisperModel) -> Bool {
        guard FileManager.default.fileExists(atPath: model.cacheDirectory.path)
        else { return false }

        if selectedModel == model {
            _ = launchctl(["bootout", "gui/\(getuid())/\(EngineService.label)"])
            EngineService.forgetRunningState()
            if Preferences.shared.finalEngine == .crisperWhisper {
                Preferences.shared.finalEngine = .apple
            }
        }
        do {
            try FileManager.default.trashItem(at: model.cacheDirectory,
                                              resultingItemURL: nil)
            Log.info("modèle retiré : \(model.rawValue)")
            return true
        } catch {
            Log.error("retrait du modèle \(model.rawValue) : \(error.localizedDescription)")
            return false
        }
    }

    /// Les modèles présents sur la machine, hors celui passé en argument.
    static func otherDownloaded(than model: CrisperWhisperModel) -> [CrisperWhisperModel] {
        CrisperWhisperModel.allCases.filter { $0 != model && $0.isDownloaded }
    }

    private static func save(_ d: Descriptor) {
        try? FileManager.default.createDirectory(
            at: descriptorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(d).write(to: descriptorURL)
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    // MARK: - Installation initiale

    /// La commande à coller dans un terminal, et pourquoi celle-là.
    ///
    /// Elle est donnée en clair, et copiable : demander à quelqu'un d'exécuter
    /// une commande qu'il ne peut pas lire est une mauvaise habitude, et
    /// celle-ci récupère du code et installe plus d'un gigaoctet de
    /// dépendances.
    ///
    /// Elle dépend de ce qui est déjà sur la machine, et ce n'est pas un
    /// raffinement. La forme fixe `git clone … && setup-engine.sh` a un défaut
    /// qu'on ne rencontre qu'au **deuxième** essai : `git clone` refuse un
    /// dossier non vide, le `&&` coupe, et l'installateur n'est jamais lancé.
    /// La commande affichée devient alors définitivement inopérante.
    ///
    /// Or le deuxième essai n'est pas un cas rare, c'est le cas courant.
    /// `setup-engine.sh` s'interrompt de lui-même quand `uv` manque — il ne
    /// l'installe pas à la place de l'utilisateur, exprès — et il s'interrompt
    /// aussi quand la licence du modèle n'est pas acceptée, ce qui est la
    /// réponse par défaut de son invite. Dans les deux cas le dépôt est déjà
    /// cloné, et l'accueil renvoyait vers une impasse.
    struct Bootstrap {
        let command: String
        let explanation: String
    }

    static var bootstrap: Bootstrap {
        let fm = FileManager.default
        let clone = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".caspr")
        let script = clone.appending(path: "scripts/setup-engine.sh")
        let fresh = "git clone --depth 1 https://github.com/mnaji42/caspr.git "
            + "~/.caspr && ~/.caspr/scripts/setup-engine.sh"

        if fm.fileExists(atPath: script.path) {
            return Bootstrap(
                command: "~/.caspr/scripts/setup-engine.sh",
                explanation: "Le code est déjà récupéré : une installation "
                    + "précédente s'est arrêtée avant la fin, faute de `uv` ou "
                    + "parce que la licence du modèle n'a pas été acceptée. Il "
                    + "ne reste qu'à relancer l'installateur, qui reprend où "
                    + "il s'était arrêté.")
        }
        if fm.fileExists(atPath: clone.path) {
            return Bootstrap(
                command: "rm -rf ~/.caspr && " + fresh,
                explanation: "Le dossier `~/.caspr` existe mais ne contient "
                    + "pas l'installateur — un téléchargement précédent s'est "
                    + "interrompu en chemin. La commande remplace ce dossier "
                    + "avant de reprendre.")
        }
        return Bootstrap(
            command: fresh,
            explanation: "La commande récupère le code du projet et installe "
                + "les dépendances. Elle vous demandera d'accepter la licence "
                + "du modèle avant de télécharger quoi que ce soit.")
    }

    // MARK: - Retour au script, après coup

    /// Le script d'installation, là où il se trouve **réellement**.
    ///
    /// `~/.caspr/scripts/setup-engine.sh` n'est vrai que pour quelqu'un qui a
    /// suivi `bootstrapCommand` à la lettre. Écrit en dur, ce chemin envoie
    /// tous les autres — celui qui a cloné ailleurs, celui qui travaille
    /// depuis le dépôt — sur un `no such file or directory` au beau milieu de
    /// l'accueil, avec pour seule issue de deviner où le projet est parti.
    ///
    /// Le descripteur, lui, sait où le moteur s'est installé : `project` est
    /// le dossier Python, le script est dans le `scripts/` voisin. Il n'y a
    /// aucune raison de deviner ce qu'on a noté.
    static var setupScript: URL? {
        guard let d = descriptor else { return nil }
        let url = URL(fileURLWithPath: d.project)
            .deletingLastPathComponent()
            .appending(path: "scripts/setup-engine.sh")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Ce qu'il faut taper pour récupérer les poids d'un modèle quand le
    /// moteur, lui, est déjà en place.
    ///
    /// `nil` si le script est introuvable : le dossier a été déplacé ou vidé
    /// depuis l'installation. Mieux vaut alors renvoyer à une installation
    /// complète que d'afficher un chemin mort, qui est exactement la panne
    /// qu'on corrige ici.
    static func modelCommand(for model: CrisperWhisperModel) -> String? {
        guard let script = setupScript else { return nil }
        return "\(shellPath(script.path)) --model \(model.rawValue)"
    }

    /// Un chemin prêt à être collé dans un terminal.
    ///
    /// Deux exigences qui se gênent : lisible — donc `~/…` plutôt que le
    /// `/Users/prénom/…` complet — et exécutable tel quel, donc protégé si le
    /// chemin contient une espace. Le tilde ne survit pas aux guillemets, zsh
    /// ne le développe pas entre quotes. On tranche : sans caractère gênant,
    /// le tilde ; sinon le chemin entier entre apostrophes.
    private static func shellPath(_ path: String) -> String {
        let plain = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789./_-")
        guard path.unicodeScalars.allSatisfy(plain.contains) else {
            return "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
