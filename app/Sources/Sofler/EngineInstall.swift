import Foundation

/// Le lien entre l'application et le moteur Python installé à côté d'elle.
///
/// Sofler est un bundle de deux mégaoctets ; CrisperWhisper demande Python,
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
            .appending(path: "Library/Application Support/Sofler/engine.json")
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
        /// Prêt à écrire.
        case ready
    }

    static func step(for model: CrisperWhisperModel) -> Step {
        guard isAvailable else { return .engineMissing }
        guard model.isDownloaded else { return .modelMissing(model) }
        guard EngineService.isInstalled else { return .serviceMissing }
        return EngineService.isRunning ? .ready : .serviceStopped
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
            .appending(path: "Library/Logs/Sofler")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                d.uv, "run", "--project", d.project,
                "python", "-m", "sofler_engine.server",
                "--model", model.identifier,
            ],
            "WorkingDirectory": d.project,
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
        return launchctl(["bootstrap", "gui/\(getuid())", url.path])
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

    /// La commande à coller dans un terminal, une seule fois.
    ///
    /// Elle est donnée en clair, et copiable : demander à quelqu'un d'exécuter
    /// une commande qu'il ne peut pas lire est une mauvaise habitude, et celle
    /// -ci récupère du code et installe plus d'un gigaoctet de dépendances.
    static let bootstrapCommand =
        "git clone --depth 1 https://github.com/mnaji42/sofler.git ~/.sofler "
        + "&& ~/.sofler/scripts/setup-engine.sh"

    // MARK: - Retour au script, après coup

    /// Le script d'installation, là où il se trouve **réellement**.
    ///
    /// `~/.sofler/scripts/setup-engine.sh` n'est vrai que pour quelqu'un qui a
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
