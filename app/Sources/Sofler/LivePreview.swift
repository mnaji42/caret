import AVFoundation
import Foundation
import Speech

/// Ce que la barre affiche pendant qu'on parle.
///
/// Volontairement derrière un protocole : la reconnaissance en flux n'existe
/// qu'à partir de macOS 26, et l'application vise macOS 14. Le contrôleur
/// manipule donc un `SpeechPreviewing?` qui reste simplement `nil` ailleurs,
/// plutôt que de disséminer des `#available` dans la logique de dictée.
protocol SpeechPreviewing: AnyObject, Sendable {
    /// Prépare la reconnaissance. Peut être long au premier appel : le modèle
    /// de dictée du système se télécharge à la demande.
    func start(language: String) async

    /// Tampon micro brut, tel que délivré par le matériel. Appelé depuis le
    /// thread audio.
    func append(_ buffer: AVAudioPCMBuffer)

    func stop()
}

/// Aperçu en direct de la dictée, par le moteur de reconnaissance de macOS.
///
/// **Ce n'est pas une préversion du texte qui sera inséré.** C'est un autre
/// moteur que CrisperWhisper : il ne reçoit pas le lexique et n'a pas le même
/// entraînement, donc il écrira « use effect » là où le moteur final écrira
/// `useEffect`. Il répond à « est-ce qu'on m'entend, où j'en suis dans ma
/// phrase », pas à « la transcription finale sera-t-elle juste ». L'interface
/// doit le dire, sans quoi l'utilisateur corrigera des erreurs qui n'existent
/// pas dans le texte réellement inséré.
///
/// Faire l'aperçu avec CrisperWhisper lui-même n'est pas envisageable : son
/// encodeur travaille sur une fenêtre d'au moins 15 s (`MIN_WINDOW_S`), donc
/// une passe sur deux secondes de parole coûte déjà une passe complète, et
/// comme chaque passe ré-encode tout depuis le début, le coût d'une dictée
/// longue croît en carré de sa durée. Ce serait payer la latence finale — la
/// seule qui compte — pour un affichage.
@available(macOS 26.0, *)
final class LivePreview: SpeechPreviewing, @unchecked Sendable {
    /// Texte reconnu jusqu'ici, publié sur le main actor.
    private let onText: @MainActor @Sendable (String) -> Void
    /// Raison d'un aperçu indisponible, à afficher telle quelle.
    private let onFailure: @MainActor @Sendable (String) -> Void

    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?

    /// Créé au premier tampon : le format matériel n'est connu qu'à ce
    /// moment-là, et il change si l'utilisateur change de micro.
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?

    init(onText: @escaping @MainActor @Sendable (String) -> Void,
         onFailure: @escaping @MainActor @Sendable (String) -> Void) {
        self.onText = onText
        self.onFailure = onFailure
    }

    /// Réserve la locale auprès du système, une fois pour toutes.
    ///
    /// Le framework l'exige, et le dit dans son journal quand on l'omet :
    /// « Cannot use modules with unallocated locales […] This will be an error
    /// in a future release ».
    ///
    /// Correction d'une attribution erronée : plusieurs entrées du corpus au
    /// texte système très court avaient été mises sur le compte de cette
    /// omission. Vérification faite, ces textes n'étaient pas tronqués mais
    /// **étrangers** — des fragments d'autres dictées, dus à une course sur
    /// `applePreviewText`, corrigée ailleurs. La réservation reste nécessaire
    /// parce que le framework la réclame, pas parce qu'on lui a mesuré cet
    /// effet-là.
    ///
    /// Le nombre de réservations est plafonné par le système
    /// (`maximumReservedLocales`) : on libère les autres avant de prendre
    /// celle qu'on veut.
    static func reserve(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        guard !reserved.contains(where: { $0.identifier == locale.identifier }) else { return }
        for previous in reserved {
            _ = await AssetInventory.release(reservedLocale: previous)
        }
        let granted = try await AssetInventory.reserve(locale: locale)
        NSLog("sofler: locale %@ réservée : %@", locale.identifier, granted ? "oui" : "non")
    }

    func start(language: String) async {
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: language)) else {
            await report("aperçu indisponible en \(language)")
            return
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // Les deux options sont nécessaires, et c'est mesuré. Sans
            // `volatileResults`, rien ne sort avant la fin d'une phrase
            // entière. Sans `fastResults`, le moteur attend d'avoir accumulé
            // beaucoup d'audio : sur une dictée de 17 s, premier texte à
            // 12,2 s puis tout d'un coup, contre 1,1 s et 17 mises à jour
            // étalées avec. `fastResults` échange un peu d'exactitude contre
            // la réactivité — exactement le bon compromis pour un affichage
            // qui ne sert qu'à se relire en parlant.
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [])

        do {
            // Réserver d'abord, interroger ensuite. L'inventaire refuse de
            // répondre sur une langue à laquelle l'application n'a pas
            // souscrit — « is not subscribed to transcription.fr » — et la
            // séquence inverse produisait cette erreur avant même d'avoir pu
            // constater ce qui manquait.
            try await Self.reserve(locale)

            // On se fie à `installedLocales`, pas à l'existence d'une requête
            // d'installation : mesuré ici, `assetInstallationRequest` renvoie
            // une requête pour `fr_FR` alors que le modèle est déjà installé
            // et que l'analyseur démarre très bien sans. Télécharger sur ce
            // seul signal ferait payer un aller-retour réseau à chaque
            // première dictée.
            let installed = await SpeechTranscriber.installedLocales
            if !installed.contains(where: { $0.identifier == locale.identifier }) {
                await report("aperçu : téléchargement du modèle \(locale.identifier)…")
                NSLog("sofler: téléchargement du modèle d'aperçu (%@)…", locale.identifier)
                try await AppleSpeechEngine.installAssets(for: transcriber)
            }

            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]) else {
                await report("aperçu : format audio incompatible")
                return
            }
            analyzerFormat = format

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.continuation = continuation

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            results = Task { [weak self] in
                await self?.consume(transcriber.results)
            }
            try await analyzer.start(inputSequence: stream)
        } catch {
            await report("aperçu indisponible — \(error.localizedDescription)")
            NSLog("sofler: aperçu en direct impossible — %@", String(describing: error))
            stop()
        }
    }

    /// Assemble les résultats en un texte courant.
    ///
    /// Le moteur émet deux sortes de résultats : des volatils, qu'il remplace
    /// au fur et à mesure qu'il entend la suite, et des définitifs, qui ne
    /// bougeront plus. On accumule les seconds et on ne réaffiche que le
    /// dernier volatil, sinon la fin de phrase se dédouble à l'écran.
    private func consume<Results: AsyncSequence & Sendable>(_ stream: Results) async
    where Results.Element == SpeechTranscriber.Result {
        var settled = ""
        do {
            for try await result in stream {
                let fragment = String(result.text.characters)
                if result.isFinal {
                    settled += fragment
                    await publish(settled)
                } else {
                    await publish(settled + fragment)
                }
            }
        } catch {
            NSLog("sofler: flux d'aperçu interrompu — %@", String(describing: error))
        }
    }

    @MainActor
    private func publish(_ text: String) {
        onText(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @MainActor
    private func report(_ message: String) {
        onFailure(message)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let continuation, let analyzerFormat else { return }

        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
        }
        guard let converter else { return }

        // Le ré-échantillonnage change le nombre de trames : on dimensionne la
        // sortie au ratio des fréquences, avec une trame de marge.
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat,
                                         frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: out))
    }

    func stop() {
        continuation?.finish()
        continuation = nil
        converter = nil
        analyzerFormat = nil

        let analyzer = self.analyzer
        let results = self.results
        self.analyzer = nil
        self.results = nil
        // Laisser l'analyseur se terminer proprement avant d'abandonner la
        // boucle : la tuer net laisse le moteur système en cours d'analyse.
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            results?.cancel()
        }
    }
}

/// Fabrique l'aperçu si le système sait le faire.
///
/// Un seul endroit teste la version : le reste du code ne voit qu'un
/// `SpeechPreviewing?`.
enum SpeechPreview {
    /// Choisit l'implémentation selon ce que la machine sait faire.
    ///
    /// L'aperçu n'était branché que sur `SpeechTranscriber`, donc il
    /// s'annonçait indisponible là où la Dictée de macOS affiche pourtant
    /// chaque mot en direct. Deux implémentations du même protocole règlent
    /// ça sans que le contrôleur de dictée en sache quoi que ce soit : il
    /// demande un aperçu, il en reçoit un.
    ///
    /// L'ordre suit la finesse attendue : le moteur de macOS 26 quand il est
    /// réellement disponible — mesuré, pas déduit de la version — celui de la
    /// Dictée sinon.
    @MainActor
    static func make(for language: String,
                     onText: @escaping @MainActor @Sendable (String) -> Void,
                     onFailure: @escaping @MainActor @Sendable (String) -> Void)
    -> (any SpeechPreviewing)? {
        if EngineChoice.apple.isAvailable(for: language), #available(macOS 26.0, *) {
            return LivePreview(onText: onText, onFailure: onFailure)
        }
        if EngineChoice.appleLegacy.isAvailable(for: language) {
            return LegacyLivePreview(onText: onText, onFailure: onFailure)
        }
        return nil
    }
}
