import AppKit
import Foundation
import ServiceManagement

/// Ce que Sofler a déposé sur la machine, et comment le retirer.
///
/// Une application qui demande le micro, l'accessibilité et le droit de
/// démarrer toute seule doit savoir partir. Sans ça, désinstaller veut dire
/// glisser un bundle à la corbeille et laisser derrière soi un service
/// lancé au démarrage, un modèle d'un giga et demi, et des autorisations
/// accordées à quelque chose qui n'existe plus.
///
/// **Rien n'est effacé définitivement : tout part à la corbeille.** C'est la
/// convention de macOS, et surtout c'est ce qui sépare une erreur d'un
/// désastre — le corpus représente des centaines de dictées réelles que rien
/// ne permet de reconstituer. Un `rm -rf` mal coché serait irréversible ;
/// une corbeille se rouvre.
/// `@MainActor` parce que tout ce que ce type interroge l'est — le corpus,
/// les autorisations, l'historique — et qu'il n'est appelé que par une
/// fenêtre. Les lectures de disque qu'il fait sont courtes et ponctuelles :
/// les sortir du fil principal compliquerait sans rien gagner.
@MainActor
enum Uninstall {

    // MARK: - Ce qui peut être retiré

    enum Item: String, CaseIterable, Identifiable {
        case settings
        case permissions
        case service
        case logs
        case corpus
        case model

        var id: String { rawValue }

        var label: String {
            switch self {
            case .settings: "Réglages et historique"
            case .permissions: "Autorisations micro et accessibilité"
            case .service: "Service moteur CrisperWhisper"
            case .logs: "Journaux et fichiers temporaires"
            case .corpus: "Dictées archivées"
            case .model: "Modèle CrisperWhisper"
            }
        }

        var explanation: String {
            switch self {
            case .settings:
                "Votre lexique, votre raccourci, vos préférences et les "
                    + "transcriptions récentes."
            case .permissions:
                "Retire Sofler des Réglages Système. Sans ça, il y reste "
                    + "listé alors qu'il n'existe plus."
            case .service:
                "Le service qui charge le modèle à l'ouverture de session. "
                    + "Il ne sert à rien sans l'application."
            case .logs:
                "Sans valeur une fois l'application partie."
            case .corpus:
                "Vos dictées et leur audio. **Rien ne permet de les "
                    + "reconstituer.** Décochez si vous comptez réinstaller, "
                    + "ou si vous voulez les garder pour vous."
            case .model:
                "Les poids téléchargés depuis Hugging Face. Les retirer "
                    + "impose de les retélécharger en cas de réinstallation."
            }
        }

        /// Coché d'avance ?
        ///
        /// Tout ce qui est petit et se reconstruit, oui. Le corpus et le
        /// modèle, non : l'un est irremplaçable, l'autre coûte un long
        /// téléchargement. Un désinstalleur qui coche par défaut la seule
        /// chose qu'on ne peut pas récupérer est un piège.
        var checkedByDefault: Bool {
            switch self {
            case .settings, .permissions, .service, .logs: true
            case .corpus, .model: false
            }
        }

        /// Les avertit-on plus fort ?
        var irreversible: Bool { self == .corpus }
    }

    // MARK: - Emplacements

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static let bundleIdentifier = "fr.lyriastudio.sofler"
    private static let serviceLabel = "fr.lyriastudio.sofler.engine"

    /// Le bundle, trouvé par lui-même et non à un chemin écrit en dur : il
    /// peut avoir été installé dans ~/Applications, ce qui est justement le
    /// cas quand on éprouve l'installation depuis une autre session.
    static var appBundle: URL { Bundle.main.bundleURL }

    private static var preferencesFile: URL {
        home.appending(path: "Library/Preferences/\(bundleIdentifier).plist")
    }
    /// Contient le corpus *et* les sauvegardes de réglages : c'est tout ce que
    /// Sofler garde à long terme.
    private static var supportDirectory: URL {
        home.appending(path: "Library/Application Support/Sofler")
    }
    private static var logsDirectory: URL {
        home.appending(path: "Library/Logs/Sofler")
    }
    private static var cachesDirectory: URL {
        home.appending(path: "Library/Caches/sofler")
    }
    private static var launchAgent: URL {
        home.appending(path: "Library/LaunchAgents/\(serviceLabel).plist")
    }
    /// Uniquement le modèle de Sofler. Le cache Hugging Face est partagé avec
    /// tout autre projet qui utilise la bibliothèque : l'effacer en entier
    /// ferait retélécharger des gigaoctets qui ne nous appartiennent pas.
    private static var modelDirectory: URL {
        home.appending(path: ".cache/huggingface/hub/models--nyralabs--CrisperWhisper2.0_turbo")
    }

    /// Ce que l'élément occupe, prêt à afficher. Vide s'il n'y a rien.
    static func detail(for item: Item) -> String {
        switch item {
        case .settings:
            let entries = TranscriptionHistory.storedCount
            return entries > 0 ? "\(entries) transcription(s) récente(s)" : "réglages seuls"
        case .permissions:
            return Permissions.allGranted ? "accordées" : "partiellement accordées"
        case .service:
            return FileManager.default.fileExists(atPath: launchAgent.path)
                ? "installé" : "non installé"
        case .logs:
            return size(of: [logsDirectory, cachesDirectory])
        case .corpus:
            let stats = Corpus.shared.statistics()
            guard stats.count > 0 else { return "aucune dictée" }
            return "\(stats.count) dictées · \(size(of: [supportDirectory]))"
        case .model:
            let s = size(of: [modelDirectory])
            return s.isEmpty ? "non téléchargé" : s
        }
    }

    /// L'élément a-t-il quelque chose à retirer ? Sinon on le grise plutôt que
    /// de le masquer : savoir qu'un modèle n'a jamais été téléchargé est une
    /// information, une ligne absente n'en est pas une.
    static func isPresent(_ item: Item) -> Bool {
        let fm = FileManager.default
        switch item {
        case .settings: return fm.fileExists(atPath: preferencesFile.path)
        case .permissions: return true
        case .service: return fm.fileExists(atPath: launchAgent.path)
        case .logs:
            return fm.fileExists(atPath: logsDirectory.path)
                || fm.fileExists(atPath: cachesDirectory.path)
        case .corpus: return Corpus.shared.statistics().count > 0
        case .model: return fm.fileExists(atPath: modelDirectory.path)
        }
    }

    // MARK: - Exécution

    /// Retire ce qui est demandé, puis l'application elle-même.
    ///
    /// - Returns: le compte rendu, ligne par ligne. Affiché avant de quitter :
    ///   quelqu'un qui désinstalle veut la preuve que c'est fait, pas une
    ///   fenêtre qui disparaît.
    static func perform(_ items: Set<Item>) -> [String] {
        var report: [String] = []

        // Le service tient le socket et se relancerait tout seul : il part en
        // premier, avant les fichiers dont il dépend.
        if items.contains(.service) {
            runTool("/bin/launchctl",
                    ["bootout", "gui/\(getuid())/\(serviceLabel)"])
            report.append(trash(launchAgent, "service moteur"))
        }

        if items.contains(.logs) {
            report.append(trash(logsDirectory, "journaux"))
            report.append(trash(cachesDirectory, "fichiers temporaires"))
        }

        if items.contains(.corpus) {
            report.append(trash(supportDirectory, "dictées archivées"))
        }

        if items.contains(.model) {
            report.append(trash(modelDirectory, "modèle CrisperWhisper"))
        }

        // Après le corpus : les réglages disent où il se trouvait.
        if items.contains(.settings) {
            report.append(trash(preferencesFile, "réglages et historique"))
            // Le démon de préférences en garde une copie en mémoire et
            // réécrirait le fichier qu'on vient de retirer.
            runTool("/usr/bin/killall", ["cfprefsd"])
        }

        if items.contains(.permissions) {
            for service in ["Microphone", "Accessibility"] {
                runTool("/usr/bin/tccutil", ["reset", service, bundleIdentifier])
            }
            report.append("✓ autorisations révoquées")
        }

        // Jamais optionnel. Laissé en place, macOS tenterait de lancer une
        // application supprimée à chaque ouverture de session, et se
        // plaindrait de ne pas la trouver.
        do {
            try SMAppService.mainApp.unregister()
            report.append("✓ retiré des ouvertures de session")
        } catch {
            // Pas inscrit : il n'y a rien à défaire, ce n'est pas un échec.
        }

        // En dernier : le code qui s'exécute vit dedans. Il reste chargé en
        // mémoire, donc la fenêtre survit assez pour afficher ce compte rendu.
        report.append(trash(appBundle, "application"))
        return report
    }

    // MARK: - Outils

    /// Corbeille, jamais suppression. Voir l'en-tête du fichier.
    private static func trash(_ url: URL, _ label: String) -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "· \(label) — rien à retirer"
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return "✓ \(label) — mis à la corbeille"
        } catch {
            return "✗ \(label) — \(error.localizedDescription)"
        }
    }

    private static func runTool(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private static func size(of urls: [URL]) -> String {
        var total: Int64 = 0
        for url in urls {
            guard let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
            else { continue }
            for case let file as URL in walker {
                let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        guard total > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
