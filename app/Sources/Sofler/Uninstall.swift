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
        case engine
        case logs
        case corpus
        case model

        var id: String { rawValue }

        var label: String {
            switch self {
            case .settings: "Réglages et historique"
            case .permissions: "Autorisations micro et accessibilité"
            case .service: "Service moteur CrisperWhisper"
            case .engine: "Moteur Python et ses bibliothèques"
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
            case .engine:
                "Python, torch et transformers — les bibliothèques installées "
                    + "depuis le Terminal, et la déclaration qui dit à Sofler "
                    + "où elles sont. **Les garder permet de réinstaller sans "
                    + "retoucher au Terminal**, un bouton suffira ; les "
                    + "retirer libère plus d'un gigaoctet."
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
        /// Tout ce qui est petit et se reconstruit, oui. Le corpus, le modèle
        /// et le moteur, non : le premier est irremplaçable, le deuxième coûte
        /// un long téléchargement, et le troisième est le seul dont la
        /// reconstruction repasse par le Terminal. Un désinstalleur qui coche
        /// par défaut la seule chose qu'on ne peut pas récupérer est un piège ;
        /// un désinstalleur qui impose une ligne de commande à quiconque
        /// réinstalle en est un autre.
        var checkedByDefault: Bool {
            switch self {
            case .settings, .permissions, .service, .logs: true
            case .engine, .corpus, .model: false
            }
        }

        /// Les avertit-on plus fort ?
        var irreversible: Bool { self == .corpus }
    }

    // MARK: - Emplacements

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static let bundleIdentifier = "fr.lyriastudio.sofler"
    private static let serviceLabel = "fr.lyriastudio.sofler.engine"

    /// Le bundle à retirer : celui qui est installé, pas la copie fantôme.
    ///
    /// Trouvé par l'application elle-même et non à un chemin écrit en dur —
    /// elle peut vivre dans ~/Applications. Mais `Bundle.main.bundleURL` ne
    /// suffit pas : tant qu'une application est en quarantaine, macOS
    /// l'exécute depuis une copie temporaire montée en lecture seule, et
    /// c'est *elle* que cette propriété désigne.
    ///
    /// Le symptôme observé est sans ambiguïté :
    ///
    ///     « Sofler » couldn't be moved to the trash because the volume
    ///     « BBBD2386-… » doesn't have one.
    ///
    /// Ce volume-là n'a effectivement pas de corbeille. Et même s'il en avait
    /// eu une, on aurait jeté le fantôme : l'application réellement installée
    /// serait restée en place pendant que la fenêtre annonçait « Sofler est
    /// désinstallé ». Un désinstalleur qui ment est pire qu'absent.
    static var appBundle: URL {
        let running = Bundle.main.bundleURL
        guard running.path.contains("/AppTranslocation/") else { return running }
        return original(of: running) ?? running
    }

    /// Remonte d'une copie translocalisée vers l'application d'origine.
    private static func original(of translocated: URL) -> URL? {
        // `SecTranslocateCreateOriginalPathForURL` existe depuis macOS 10.12
        // mais n'apparaît pas dans la surcouche Swift du framework Security.
        // On va la chercher au chargement plutôt que de deviner : elle rend le
        // chemin exact, y compris pour une application lancée depuis les
        // Téléchargements ou une clé USB, là où une liste d'emplacements
        // probables se tromperait.
        typealias Resolve = @convention(c)
            (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                              "SecTranslocateCreateOriginalPathForURL") {
            let resolve = unsafeBitCast(symbol, to: Resolve.self)
            if let url = resolve(translocated as CFURL, nil)?
                .takeRetainedValue() as URL?,
               url.path != translocated.path,
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Repli, si le symbole venait à disparaître d'une version de macOS :
        // les deux seuls endroits où une application s'installe.
        let name = translocated.lastPathComponent
        return [URL(fileURLWithPath: "/Applications/\(name)"),
                home.appending(path: "Applications/\(name)")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static var preferencesFile: URL {
        home.appending(path: "Library/Preferences/\(bundleIdentifier).plist")
    }
    /// Contient le corpus, les sauvegardes de réglages et la déclaration du
    /// moteur : c'est tout ce que Sofler garde à long terme.
    ///
    /// Il n'est jamais retiré d'un bloc. Ce qu'il contient appartient à trois
    /// cases différentes, et les jeter ensemble a déjà eu une conséquence
    /// concrète : `engine.json` ne partait qu'avec les dictées archivées,
    /// c'est-à-dire seulement si l'on cochait la seule case que l'interface
    /// laisse décochée exprès. Le dossier lui-même s'en va à la fin, s'il ne
    /// reste rien dedans.
    private static var supportDirectory: URL {
        home.appending(path: "Library/Application Support/Sofler")
    }
    private static var corpusDirectory: URL {
        supportDirectory.appending(path: "corpus")
    }

    /// Ce que `setup-engine.sh` a laissé sur la machine.
    ///
    /// Déduit du descripteur, jamais d'un chemin écrit en dur — et la
    /// distinction n'est pas cosmétique ici. Se tromper d'emplacement dans un
    /// désinstalleur ne produit pas un message d'erreur : ça met à la
    /// corbeille le dossier de quelqu'un d'autre.
    ///
    /// D'où la règle sur le dépôt cloné : il ne part **que** s'il se trouve
    /// exactement là où la commande d'installation le met, `~/.sofler`. Sur
    /// une machine de développement, `project` désigne le dépôt de travail ;
    /// en remonter d'un cran et le jeter effacerait le code source et tout ce
    /// qui n'y est pas encore commité. Dans ce cas seul l'environnement
    /// Python s'en va — c'est lui qui pèse, et lui seul se régénère.
    private static var enginePaths: [(url: URL, label: String)] {
        let fm = FileManager.default
        var found: [(URL, String)] = []

        // L'outil, quand c'est Sofler qui l'a récupéré. Celui de Homebrew
        // n'est jamais touché : il n'appartient pas à cette application, et
        // d'autres projets s'en servent.
        let tool = supportDirectory.appending(path: "tools")
        if fm.fileExists(atPath: tool.path) { found.append((tool, "uv")) }

        guard let project = EngineInstall.descriptor?.project else { return found }
        let projectURL = URL(fileURLWithPath: project).standardizedFileURL

        // Installation faite depuis l'application : tout tient dans un dossier
        // qui n'appartient qu'à Sofler, code et environnement compris.
        let own = EngineBootstrap.engineDirectory.standardizedFileURL
        if projectURL.path == own.path, fm.fileExists(atPath: own.path) {
            found.append((own, "moteur Python"))
            return found
        }

        // Installation faite au Terminal, du temps où c'était la seule voie.
        // Le dépôt cloné ne part que s'il est exactement là où la commande le
        // mettait — comparé par `path`, jamais comme deux `URL` :
        // `deletingLastPathComponent()` rend « …/.sofler/ » quand
        // `appending(path:)` rend « …/.sofler », et l'égalité d'URL porte sur
        // la chaîne entière, barre oblique comprise. Le test échouait donc
        // toujours, et le dépôt d'un utilisateur survivait à la case qui
        // promettait de le retirer.
        let clone = projectURL.deletingLastPathComponent()
        let canonical = home.appending(path: ".sofler").standardizedFileURL
        if clone.path == canonical.path, fm.fileExists(atPath: clone.path) {
            found.append((clone, "moteur Python"))
            return found
        }

        // Dépôt de travail d'un développeur : seul l'environnement s'en va.
        // Remonter d'un cran et jeter le dossier parent effacerait le code
        // source et tout ce qui n'y est pas commité — et depuis que le moteur
        // peut s'installer dans « Application Support », ce parent-là serait
        // le dossier qui contient le corpus.
        let venv = projectURL.appending(path: ".venv")
        if fm.fileExists(atPath: venv.path) {
            found.append((venv, "bibliothèques Python du moteur"))
        }
        return found
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
        case .engine:
            let paths = enginePaths
            guard !paths.isEmpty else {
                return EngineInstall.descriptor == nil
                    ? "non installé" : "déclaration seule"
            }
            return size(of: paths.map(\.url))
        case .logs:
            return size(of: [logsDirectory, cachesDirectory])
        case .corpus:
            let stats = Corpus.shared.statistics()
            guard stats.count > 0 else { return "aucune dictée" }
            return "\(stats.count) dictées · \(size(of: [corpusDirectory]))"
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
        case .engine:
            return !enginePaths.isEmpty
                || fm.fileExists(atPath: EngineInstall.descriptorURL.path)
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

        // Après le service, qui s'exécutait depuis cet environnement Python :
        // le sortir d'abord évite de retirer le sol sous un processus vivant.
        if items.contains(.engine) {
            for path in enginePaths {
                report.append(trash(path.url, path.label))
            }
            // Le descripteur part avec le moteur qu'il décrit. Il était rangé
            // avec les dictées archivées, donc il survivait à toute
            // désinstallation raisonnable — et une réinstallation retrouvait
            // une déclaration pointant vers un moteur qui n'existait plus.
            report.append(trash(EngineInstall.descriptorURL,
                                "déclaration du moteur"))
        }

        if items.contains(.logs) {
            report.append(trash(logsDirectory, "journaux"))
            report.append(trash(cachesDirectory, "fichiers temporaires"))
        }

        if items.contains(.corpus) {
            report.append(trash(corpusDirectory, "dictées archivées"))
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

        // Le dossier de support lui-même, une fois ses trois occupants partis.
        // Sans ce balayage, une désinstallation complète laisserait une
        // coquille vide, un dossier `backups` que plus rien n'écrit et un
        // `.DS_Store` — c'est-à-dire l'impression tenace, en rouvrant le
        // Finder, que quelque chose n'est pas parti.
        if isEffectivelyEmpty(supportDirectory) {
            report.append(trash(supportDirectory, "dossier de Sofler"))
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

    /// Ne reste-t-il là-dedans que des miettes ?
    ///
    /// Un `.DS_Store` et des dossiers vides ne sont pas des données de
    /// l'utilisateur : les compter comme du contenu ferait survivre le dossier
    /// à sa propre vacuité. Récursif, parce que la vacuité l'est.
    private static func isEffectivelyEmpty(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return entries.allSatisfy { name in
            if name == ".DS_Store" { return true }
            let child = url.appending(path: name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            return isEffectivelyEmpty(child)
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
