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
    static let label = "fr.lyriastudio.sofler.engine"

    /// Le service est-il installé sur cette machine ?
    ///
    /// Distinct de « chargé » : sans agent installé, l'utilisateur n'a jamais
    /// mis en place CrisperWhisper, et lui proposer de le démarrer n'aurait
    /// pas de sens.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: agentPath)
    }

    static var isRunning: Bool {
        run(["list", label]) != nil
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

    private static var agentPath: String {
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
