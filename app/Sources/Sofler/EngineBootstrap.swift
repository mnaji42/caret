import AppKit
import CryptoKit
import Foundation
import Observation

/// Installe CrisperWhisper depuis l'application, sans Terminal.
///
/// L'accueil demandait de coller une commande. Ça marchait, et c'était quand
/// même la mauvaise réponse : la commande échouait au deuxième essai, elle
/// affichait un chemin différent selon la machine, elle posait la question de
/// la licence dans une invite où appuyer sur Entrée veut dire non, et surtout
/// elle sortait les gens de l'application au moment précis où il fallait les
/// tenir par la main. Tout ce qu'elle faisait, du code peut le faire — en le
/// montrant.
///
/// ## Ce qui est embarqué, et ce qui ne l'est pas
///
/// Le moteur Python **est** dans le bundle : son code source pèse 284 Ko,
/// soit trois dixièmes de pour cent de l'application. Il n'y a donc plus de
/// dépôt à cloner, plus de `~/.sofler`, plus rien à récupérer sur GitHub pour
/// obtenir le programme lui-même.
///
/// `uv` n'y est pas, et c'est un choix. Il pèse 18,5 Mo — vingt fois
/// l'application — et ne sert qu'à CrisperWhisper. L'embarquer ferait porter
/// ce poids à tous ceux qui dictent avec le moteur de macOS, qui n'a besoin
/// d'aucun Python ; et si une version future de macOS rend CrisperWhisper
/// superflu, ce serait vingt mégaoctets de lest à perpétuité. Il est donc
/// récupéré au moment de l'installation — celui où l'utilisateur vient
/// d'accepter 2,8 Go de téléchargement, et où 18,5 Mo de plus représentent
/// sept dixièmes de pour cent du total.
///
/// ## Ce que ça change pour la confiance
///
/// Récupérer et exécuter un binaire tiers mérite un examen. En le comparant à
/// ce qui existait, le compte est favorable : la commande d'installation
/// clonait un dépôt et exécutait un script shell, tous deux sans la moindre
/// vérification, avant de laisser `pip` chercher 1,2 Go de roues sur PyPI. Ici
/// le clone disparaît, le script disparaît, et le seul ajout est un binaire
/// dont on contrôle l'empreinte SHA-256 publiée à côté de lui. Ce qui reste
/// non vérifié — les roues PyPI, les poids du modèle — l'était déjà.
///
/// Rien n'est installé hors du dossier de Sofler. Ni `/usr/local`, ni
/// Homebrew, ni le Python du système ne sont touchés.
@MainActor
@Observable
final class EngineBootstrap {
    static let shared = EngineBootstrap()

    enum Phase: Equatable {
        case idle
        /// Récupération de `uv`, fraction téléchargée.
        case fetchingTool(Double)
        /// Copie du moteur, création de l'environnement.
        case preparing(String)
        /// Installation des bibliothèques. Porte la dernière ligne de `uv`,
        /// parce qu'un quart d'heure de silence sur 1,2 Go passe pour une
        /// panne.
        case installingDependencies(String)
        /// Téléchargement des poids, fraction déduite de ce qui est sur disque.
        case downloadingModel(Double)
        /// Service lancé, modèle en train d'être lu. Porte les secondes
        /// écoulées : l'étape dure jusqu'à une minute sans rien produire
        /// d'observable, et un compteur qui monte est la seule preuve que
        /// quelque chose se passe encore.
        case startingService(Int)
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var current: Process?

    var isBusy: Bool {
        switch phase {
        case .idle, .done, .failed: false
        default: true
        }
    }

    // MARK: - Emplacements

    /// Tout vit sous le dossier de Sofler, jamais dans le bundle.
    ///
    /// L'environnement Python ne peut pas habiter `Sofler.app` : la mise à
    /// jour remplace le bundle en entier, ce qui emporterait 1,2 Go de
    /// bibliothèques à chaque version, et un `.venv` glissé dans `Resources`
    /// romprait le sceau de la signature.
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Sofler")
    }
    static var engineDirectory: URL { supportDirectory.appending(path: "engine") }
    private static var toolsDirectory: URL { supportDirectory.appending(path: "tools") }
    private static var ownTool: URL { toolsDirectory.appending(path: "uv") }

    /// Le code du moteur, tel qu'il voyage dans le bundle.
    static var bundledSource: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let source = resources.appending(path: "engine")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    // MARK: - Préalables

    /// Ce qui empêche l'installation intégrée, ou `nil`.
    static var obstacle: String? {
        guard isAppleSilicon else {
            return "CrisperWhisper exige un Mac Apple Silicon. Le moteur de "
                + "macOS, lui, fonctionne sans rien installer."
        }
        guard bundledSource != nil else {
            return "Cette copie de Sofler ne contient pas le code du moteur. "
                + "Réinstallez-la depuis l'image disque officielle."
        }
        return nil
    }

    /// Le processeur, demandé au système plutôt que déduit de l'architecture
    /// du binaire : sous Rosetta, un exécutable Intel tourne très bien sur une
    /// puce Apple, et refuser l'installation dans ce cas serait faux.
    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0
        else { return false }
        return value == 1
    }

    /// `uv` déjà présent sur la machine, s'il y est.
    ///
    /// Les emplacements sont énumérés en clair plutôt que cherchés dans le
    /// `PATH` : une application lancée depuis le Finder n'hérite pas du `PATH`
    /// d'un terminal — c'est exactement pourquoi le descripteur note un chemin
    /// absolu. Celui de Sofler passe en premier, les deux de Homebrew ensuite,
    /// pour ne pas faire télécharger 18,5 Mo à quelqu'un qui a déjà l'outil.
    static func locateTool() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            ownTool,
            URL(fileURLWithPath: "/opt/homebrew/bin/uv"),
            URL(fileURLWithPath: "/usr/local/bin/uv"),
            home.appending(path: ".local/bin/uv"),
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Installation

    /// Le chemin complet, du néant au service qui tourne.
    ///
    /// - Parameter licenceAccepted: la licence des poids est affichée et
    ///   acceptée **avant** l'appel, dans la fenêtre. Le script posait la
    ///   question dans une invite `[o/N]` où la touche Entrée refusait, ce qui
    ///   interrompait l'installation par inadvertance une fois sur deux.
    func install(model: CrisperWhisperModel, licenceAccepted: Bool) async {
        guard !isBusy else { return }
        guard licenceAccepted else {
            phase = .failed("La licence des poids n'a pas été acceptée.")
            return
        }
        if let obstacle = Self.obstacle {
            phase = .failed(obstacle)
            return
        }

        // Le choix est retenu ici, et pas plus tôt : c'est l'instant où l'on
        // engage un téléchargement de plusieurs gigaoctets. Parcourir la
        // grille avant n'a rien décidé.
        Preferences.shared.chosenCrisperModel = model

        do {
            let uv = try await resolveTool()
            try await prepareSource()
            try await createEnvironment(uv: uv)
            try await installDependencies(uv: uv)
            try await downloadModel(uv: uv, model: model)

            phase = .startingService(0)
            // Le descripteur d'abord : `installService` le lit pour écrire
            // l'agent de lancement.
            EngineInstall.write(project: Self.engineDirectory.path,
                                uv: uv.path, model: model)
            guard EngineInstall.installService(model: model) else {
                throw Failure.service
            }
            try await waitUntilAnswering()
            phase = .done
            Log.info("engine: installé (\(model.rawValue))")
        } catch is CancellationError {
            phase = .idle
        } catch {
            Log.error("engine: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Redémarre le service, sans rien réinstaller.
    ///
    /// Tout est déjà sur le disque — les poids, l'environnement, le
    /// descripteur — et il ne reste qu'à charger le modèle en mémoire.
    ///
    /// La carte appelait `EngineInstall.installService` directement. Ça
    /// marchait : le service démarrait vraiment, journal à l'appui. Mais rien
    /// ne touchait `phase`, donc l'interface restait sur « au repos » et le
    /// bouton paraissait mort — on cliquait, le modèle se chargeait en mémoire
    /// pendant une minute, et l'écran n'en disait rien. Passer par ici donne
    /// les deux choses qui manquaient : l'état pendant le chargement, et
    /// l'attente que le socket réponde avant d'annoncer « Prêt ».
    func startService(model: CrisperWhisperModel) async {
        guard !isBusy else { return }
        Preferences.shared.chosenCrisperModel = model
        phase = .startingService(0)
        guard EngineInstall.installService(model: model) else {
            phase = .failed("Le service n'a pas pu être lancé. "
                            + "Le journal du moteur en dit la raison : "
                            + "~/Library/Logs/Sofler/engine.log")
            return
        }
        do {
            try await waitUntilAnswering()
            phase = .done
            Log.info("engine: service démarré (\(model.rawValue))")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Attend que le service réponde, pas seulement qu'il soit lancé.
    ///
    /// `installService` rend la main dès que launchd a accepté l'agent —
    /// c'est-à-dire avant que le modèle soit en mémoire. Annoncer
    /// l'installation terminée à cet instant produisait exactement le défaut
    /// observé : une fenêtre disant « Prêt · Turbo chargé », et une première
    /// dictée qui ne rendait rien parce que le socket n'existait pas encore.
    ///
    /// Trois minutes de patience. Au-delà, ce n'est plus un chargement, c'est
    /// une panne, et le journal du service est le seul endroit où elle est
    /// écrite.
    private func waitUntilAnswering() async throws {
        for elapsed in 0..<180 {
            if EngineService.isAnswering { return }
            phase = .startingService(elapsed)
            try await Task.sleep(for: .seconds(1))
        }
        throw Failure.slowStart
    }

    /// Interrompt une installation en cours.
    ///
    /// Ce qui est déjà sur disque reste : les roues installées et les poids
    /// téléchargés sont repris tels quels au prochain essai. Effacer par
    /// principe ferait recommencer 2,8 Go pour une hésitation.
    func cancel() {
        current?.terminate()
        current = nil
        phase = .idle
    }

    /// Ramène au repos après un échec ou une réussite, pour que la vue
    /// reprenne la main et affiche l'état réel plutôt que le souvenir de la
    /// dernière opération.
    func reset() {
        switch phase {
        case .failed, .done: phase = .idle
        default: break
        }
    }

    // MARK: - 1. L'outil

    private func resolveTool() async throws -> URL {
        // Avant tout appel à uv, y compris quand l'outil est déjà là : c'est
        // `uv python install` qui déclenche l'amorce Xcode, pas le
        // téléchargement de uv lui-même.
        try Self.prepareShims()
        if let existing = Self.locateTool() { return existing }

        phase = .fetchingTool(0)
        let release = try await Self.latestToolRelease()
        let archive = FileManager.default.temporaryDirectory
            .appending(path: "uv-\(UUID().uuidString).tar.gz")
        defer { try? FileManager.default.removeItem(at: archive) }

        try await Self.download(release.archive, to: archive) { [weak self] f in
            guard case .fetchingTool = self?.phase else { return }
            self?.phase = .fetchingTool(f)
        }

        // L'empreinte est publiée par Astral à côté de l'archive. La vérifier
        // est le seul moment de toute la chaîne où l'on sait exactement ce
        // qu'on s'apprête à exécuter — s'en passer viderait de son sens le
        // fait de ne plus cloner un dépôt à l'aveugle.
        let digest = SHA256.hash(data: try Data(contentsOf: archive))
            .map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256 else {
            throw Failure.checksum(expected: release.sha256, got: digest)
        }

        phase = .preparing("installation de uv")
        return try await Self.unpackTool(archive, to: Self.ownTool)
    }

    // MARK: - 2. Le code du moteur

    /// Recopie le moteur du bundle vers le dossier de Sofler.
    ///
    /// Refaite à chaque installation, pour qu'une mise à jour de Sofler porte
    /// aussi le moteur. `.venv` n'est jamais touché : c'est 1,2 Go, il est
    /// reconstruit par `uv` si besoin, et l'écraser à chaque fois rendrait
    /// toute mise à jour insupportable.
    private func prepareSource() async throws {
        guard let source = Self.bundledSource else { throw Failure.missingSource }
        phase = .preparing("préparation du moteur")
        try await Self.syncSource(from: source, to: Self.engineDirectory)
    }

    // MARK: - 3. L'environnement

    private func createEnvironment(uv: URL) async throws {
        let venv = Self.engineDirectory.appending(path: ".venv")
        guard !FileManager.default.fileExists(atPath: venv.path) else { return }
        phase = .preparing("création de l'environnement Python")
        // uv récupère au besoin un CPython autonome (~25 Mo) dans son propre
        // cache. Il n'installe rien dans le système et ne touche pas au Python
        // que la machine possède éventuellement déjà.
        try await run(uv, ["venv", "--python", "3.12"],
                      in: Self.engineDirectory) { [weak self] line in
            self?.phase = .preparing(line)
        }
    }

    private func installDependencies(uv: URL) async throws {
        phase = .installingDependencies("résolution des dépendances…")
        for arguments in [["pip", "install", "-e", "."],
                          ["pip", "install", "soundfile"]] {
            try await run(uv, arguments, in: Self.engineDirectory) { [weak self] line in
                self?.phase = .installingDependencies(line)
            }
        }
    }

    // MARK: - 4. Les poids

    private func downloadModel(uv: URL, model: CrisperWhisperModel) async throws {
        guard !model.isDownloaded else { return }
        phase = .downloadingModel(0)
        reportedBytes = 0

        // ## Pourquoi deux mesures
        //
        // La première version ne regardait que la taille du dossier de cache.
        // Elle mentait, et de façon spectaculaire : 0 % pendant quinze
        // secondes, 16 % pendant trente, 21 % pendant trente encore, puis 63 %
        // et fini. Ce n'était pas une question de fréquence de sondage — c'est
        // que les octets n'atterrissaient pas là où on les cherchait.
        //
        // `huggingface_hub` 1.x utilise le stockage Xet : les morceaux
        // descendent dans `~/.cache/huggingface/xet`, puis les fichiers sont
        // matérialisés d'un coup dans `hub/models--…`. Le dossier surveillé ne
        // bougeait donc que par à-coups, à chaque fichier terminé.
        //
        // La bibliothèque sait, elle, combien d'octets sont arrivés : elle les
        // compte pour dessiner ses barres. `tqdm_class` permet de lui greffer
        // un compteur qui les annonce sur une ligne lisible par un programme.
        // Le sondage disque est conservé comme plancher — les deux sont des
        // minorants honnêtes, et si la greffe cessait de fonctionner sur une
        // version future, l'avancement redeviendrait saccadé au lieu de
        // s'arrêter.
        let watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { continue }
                let total = Double(model.downloadBytes)
                guard total > 0 else { continue }
                let done = max(Double(model.downloadedBytes), Double(self.reportedBytes))
                if case .downloadingModel = self.phase {
                    self.phase = .downloadingModel(min(done / total, 0.99))
                }
            }
        }
        defer { watcher.cancel() }

        let script = """
            import sys
            from huggingface_hub import snapshot_download

            # Greffé sur les barres de progression de la bibliothèque. Seules
            # celles qui comptent des octets nous intéressent : snapshot_download
            # en ouvre aussi une qui compte des fichiers, et l'additionner
            # fausserait tout.
            options = {}
            try:
                from tqdm.auto import tqdm as _tqdm

                class Progress(_tqdm):
                    done = 0

                    def __init__(self, *args, **kwargs):
                        super().__init__(*args, **kwargs)
                        self._bytes = kwargs.get("unit") == "B"

                    def update(self, n=1):
                        super().update(n)
                        if self._bytes and n:
                            Progress.done += n
                            print("SOFLER_PROGRESS %d" % Progress.done,
                                  file=sys.stderr, flush=True)

                options["tqdm_class"] = Progress
            except Exception:
                pass

            snapshot_download("\(model.identifier)", **options)
            """
        try await run(uv, ["run", "--project", Self.engineDirectory.path,
                           "python", "-c", script],
                      in: Self.engineDirectory) { [weak self] line in
            guard line.hasPrefix(Self.progressMarker),
                  let done = Int64(line.dropFirst(Self.progressMarker.count))
            else { return }
            self?.reportedBytes = done
        }
    }

    private static let progressMarker = "SOFLER_PROGRESS "
    /// Octets annoncés par la bibliothèque. Lu par le surveillant, qui en fait
    /// le maximum avec ce qu'il voit sur le disque.
    private var reportedBytes: Int64 = 0

    // MARK: - Exécution d'un outil, avec sa sortie

    /// Lance un programme et rapporte ses lignes au fur et à mesure.
    ///
    /// La sortie d'erreur est fondue dans la sortie standard : `uv` et `pip`
    /// écrivent leur avancement sur la seconde, et les séparer ferait perdre
    /// précisément ce qu'on veut montrer.
    /// L'environnement de toute invocation de `uv`.
    ///
    /// Une seule variable, et elle évite un téléchargement de **19 Go**.
    ///
    /// `uv venv --python 3.12` cherche un interpréteur qui convienne, et pour
    /// connaître la version d'un candidat il l'exécute. `/usr/bin/python3` est
    /// sur le chemin de toute machine, mais sur un Mac neuf ce n'est pas Python :
    /// c'est une amorce qui ouvre « Des outils de ligne de commande sont
    /// nécessaires pour la commande python3 ». Soit près de 19 Go d'outils de
    /// développement Xcode, réclamés à quelqu'un qui voulait dicter — et la
    /// fenêtre s'ouvre **derrière** l'accueil, donc sans rien pour l'expliquer.
    ///
    /// `UV_MANAGED_PYTHON` restreint la recherche aux interpréteurs que `uv`
    /// gère lui-même : il en récupère un de 25 Mo dans son propre cache et ne
    /// touche jamais à celui du système. C'est aussi ce que Sofler voulait
    /// depuis le début — cf. `createEnvironment` : « il n'installe rien dans le
    /// système et ne touche pas au Python que la machine possède éventuellement
    /// déjà ». La règle était écrite, elle n'était pas appliquée.
    ///
    /// Une variable et non un drapeau : `uv` est téléchargé à sa dernière
    /// version, donc une variable qu'il ne connaîtrait pas serait ignorée, là
    /// où un drapeau inconnu ferait échouer l'installation entière.
    private static var toolEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["UV_MANAGED_PYTHON"] = "1"
        // Le dossier des leurres passe **devant** : c'est ce qui fait que
        // `/usr/bin/install_name_tool` n'est jamais exécuté. Cf. `prepareShims`.
        let chemin = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(shimDirectory.path):\(chemin)"
        return environment
    }

    /// Dossier des leurres, à côté de `uv` — donc retiré avec lui.
    static var shimDirectory: URL {
        toolsDirectory.appending(path: "shims")
    }

    /// Pose un `install_name_tool` qui échoue en silence.
    ///
    /// Deuxième fenêtre « Des outils de ligne de commande sont nécessaires »,
    /// après celle de `python3` : `uv python install` exécute
    /// `install_name_tool -id …/libpython3.12.dylib` pour corriger le nom
    /// d'installation de la bibliothèque. Sur un Mac neuf ce chemin n'est pas
    /// l'outil, c'est l'amorce qui propose 19 Go d'outils Xcode — et elle
    /// s'ouvre **derrière** l'accueil, sans rien pour l'expliquer.
    ///
    /// Mesuré sur une machine sans ces outils : quand l'appel échoue, `uv`
    /// écrit « Failed to patch the install name of the dynamic library » et
    /// **poursuit**. L'installation aboutit, l'environnement fonctionne, le
    /// moteur transcrit. C'est exactement ce que produit un clic sur
    /// « Annuler », que quelqu'un a fait avant d'y penser.
    ///
    /// Le leurre sort donc en **échec**, pas en succès. La nuance compte : uv
    /// sait déjà composer avec le refus — c'est le chemin éprouvé — alors
    /// qu'un faux succès lui ferait croire la bibliothèque corrigée et
    /// déplacerait la panne ailleurs, sans trace.
    ///
    /// Mesuré aussi : sur une installation complète — environnement, torch,
    /// transformers — c'est le **seul** outil Xcode sollicité. Onze leurres
    /// posés en observation, un seul appel.
    private static func prepareShims() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: shimDirectory, withIntermediateDirectories: true)
        let leurre = shimDirectory.appending(path: "install_name_tool")
        let script = """
        #!/bin/sh
        # Posé par Sofler — cf. EngineBootstrap.prepareShims.
        # Échoue comme le ferait un clic sur « Annuler », sans la fenêtre.
        exit 1

        """
        try script.write(to: leurre, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: leurre.path)
    }

    private func run(_ tool: URL, _ arguments: [String], in directory: URL,
                     onLine: @escaping @MainActor (String) -> Void) async throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = Self.toolEnvironment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        current = process

        let collector = LineCollector { line in
            Task { @MainActor in onLine(line) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            collector.feed(handle.availableData)
        }

        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            current = nil
            throw Failure.launch(tool.lastPathComponent, error.localizedDescription)
        }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in c.resume() }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        current = nil

        guard process.terminationStatus == 0 else {
            // Un arrêt par signal est une annulation, pas une panne : c'est
            // `cancel()` qui vient de le tuer.
            if process.terminationReason == .uncaughtSignal { throw CancellationError() }
            throw Failure.tool(tool.lastPathComponent,
                               Int(process.terminationStatus),
                               collector.lastLine)
        }
    }

    // MARK: - Échecs

    private enum Failure: LocalizedError {
        case missingSource
        case releaseUnreadable
        case checksum(expected: String, got: String)
        case unpack
        case launch(String, String)
        case tool(String, Int, String)
        case service
        case slowStart

        var errorDescription: String? {
            switch self {
            case .missingSource:
                "Le code du moteur est absent de cette copie de Sofler."
            case .releaseUnreadable:
                "La dernière version de uv n'a pas pu être identifiée. "
                    + "Vérifiez votre connexion."
            case .checksum(let expected, let got):
                "L'empreinte de uv ne correspond pas à celle publiée "
                    + "(attendue \(expected.prefix(12))…, obtenue "
                    + "\(got.prefix(12))…). Rien n'a été exécuté."
            case .unpack:
                "L'archive de uv n'a pas pu être ouverte."
            case .launch(let tool, let detail):
                "\(tool) n'a pas pu être lancé : \(detail)"
            case .tool(let tool, let code, let last):
                last.isEmpty
                    ? "\(tool) s'est arrêté (code \(code))."
                    : "\(tool) s'est arrêté (code \(code)) : \(last)"
            case .service:
                "Le moteur est installé mais son service n'a pas démarré. "
                    + "Réessayez depuis les Réglages."
            case .slowStart:
                "Le service a démarré mais n'a pas fini de charger le modèle "
                    + "au bout de trois minutes. Tout est installé — voir "
                    + "~/Library/Logs/Sofler/engine.log pour savoir sur quoi "
                    + "il bute."
            }
        }
    }
}

// MARK: - Réseau et fichiers

extension EngineBootstrap {
    private struct ToolRelease {
        let archive: URL
        let sha256: String
    }

    /// Interroge les releases d'Astral pour l'archive arm64 et son empreinte.
    private nonisolated static func latestToolRelease() async throws -> ToolRelease {
        struct Payload: Decodable {
            struct Asset: Decodable { let name: String; let browserDownloadUrl: String
                enum CodingKeys: String, CodingKey {
                    case name, browserDownloadUrl = "browser_download_url"
                }
            }
            let assets: [Asset]
        }

        var request = URLRequest(url: URL(string:
            "https://api.github.com/repos/astral-sh/uv/releases/latest")!)
        request.setValue("Sofler", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let name = "uv-aarch64-apple-darwin.tar.gz"
        guard let asset = payload.assets.first(where: { $0.name == name }),
              let archive = URL(string: asset.browserDownloadUrl),
              let sums = payload.assets.first(where: { $0.name == name + ".sha256" }),
              let sumsURL = URL(string: sums.browserDownloadUrl)
        else { throw Failure.releaseUnreadable }

        // Le fichier d'empreinte fait quelques dizaines d'octets et suit la
        // forme « <hex>  <nom> ».
        let (sumData, _) = try await URLSession.shared.data(from: sumsURL)
        guard let text = String(data: sumData, encoding: .utf8),
              let hex = text.split(separator: " ").first.map(String.init),
              hex.count == 64
        else { throw Failure.releaseUnreadable }

        return ToolRelease(archive: archive, sha256: hex.lowercased())
    }

    private nonisolated static func download(
        _ url: URL, to destination: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("Sofler", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        try await AssetDownload(to: destination, progress: progress).run(request)
    }

    /// Déballe l'archive et place le binaire à l'emplacement voulu.
    /// `async` bien qu'elle n'attende rien : sans ça elle s'exécuterait sur le
    /// fil principal, et déballer dix-huit mégaoctets y fige la fenêtre.
    private nonisolated static func unpackTool(_ archive: URL, to destination: URL)
        async throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appending(path: "uv-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path, "-C", staging.path]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw Failure.unpack }

        // L'archive contient un dossier « uv-aarch64-apple-darwin » ; on ne
        // suppose pas son nom, on cherche l'exécutable.
        guard let walker = fm.enumerator(at: staging, includingPropertiesForKeys: nil),
              let binary = walker.compactMap({ $0 as? URL })
                  .first(where: { $0.lastPathComponent == "uv" })
        else { throw Failure.unpack }

        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: binary, to: destination)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    /// Recopie le code du moteur, sans jamais toucher à `.venv`.
    private nonisolated static func syncSource(from source: URL, to destination: URL) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in try fm.contentsOfDirectory(atPath: source.path) {
            let from = source.appending(path: entry)
            let to = destination.appending(path: entry)
            try? fm.removeItem(at: to)
            try fm.copyItem(at: from, to: to)
        }
    }
}

/// Découpe un flux d'octets en lignes affichables.
///
/// `pip` et `uv` avancent au retour chariot, pas au saut de ligne : leurs
/// barres réécrivent la même ligne. Traiter `\r` comme un séparateur donne un
/// affichage qui bouge ; ne traiter que `\n` donnerait une ligne figée pendant
/// des minutes.
private final class LineCollector {
    private let onLine: (String) -> Void
    private var buffer = Data()
    private let queue = DispatchQueue(label: "fr.lyriastudio.sofler.lines")
    private(set) var lastLine = ""

    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.sync {
            buffer.append(data)
            while let index = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let line = String(data: buffer[buffer.startIndex..<index], encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                buffer.removeSubrange(buffer.startIndex...index)
                guard !line.isEmpty else { continue }
                lastLine = line
                onLine(line)
            }
        }
    }
}
