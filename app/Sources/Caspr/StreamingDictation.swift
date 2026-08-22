import AppKit
import Observation
import SwiftUI

/// La dictée au fil de la parole, sur ⌥ **gauche**.
///
/// ## Pourquoi un contrôleur séparé plutôt qu'un mode de l'existant
///
/// `DictationController` enregistre, arrête, envoie, insère — quatre temps
/// nettement séparés, et tout ce qui l'entoure suppose cet ordre : l'aperçu en
/// direct vient d'un autre moteur, la collecte rejoue plusieurs moteurs sur
/// l'audio conservé, le repli choisit qui écrit au moment d'envoyer. La dictée
/// au fil n'a pas ces temps-là : elle envoie **pendant**, et le texte qu'elle
/// affiche est déjà le texte final.
///
/// Y ajouter un drapeau aurait obligé chaque branche de l'existant à se
/// demander dans quel monde elle vit. Deux chemins parallèles, aucun n'a à
/// connaître l'autre — et celui qui marche aujourd'hui ne risque rien.
///
/// ## Ce que ce chemin ne sait pas faire
///
/// La session de flux de mlx-audio ne prend **aucune langue** :
/// `create_streaming_session(max_tokens:temperature:transcription_delay_ms:)`,
/// il n'y a rien d'autre. Le modèle devine, et sur une ouverture courte ou
/// ambiguë il se trompe — relevé au premier essai réel, vingt-deux mots de
/// français rendus en allemand, là où cent quarante-six mots sortent justes.
/// Le réglage de langue de Caspr n'a donc aucun effet ici, et c'est une raison
/// de plus de garder ce chemin séparé plutôt que de le fondre dans l'existant.
///
/// ## Ce qu'on éprouve ici
///
/// Une seule chose : est-ce que 0,84 s d'attente au lieu de 34 s change
/// l'usage ? Le chiffre est mesuré sur banc, à travers le vrai protocole. Il
/// reste à savoir s'il tient une fois passé par le micro, la conversion et
/// l'insertion — et surtout si le résultat vaut d'ouvrir le chantier.
@MainActor
@Observable
final class StreamingDictation {

    enum Phase: Equatable {
        case idle
        case connecting
        case listening
        case finishing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Le texte tel qu'il arrive, morceau par morceau.
    private(set) var text = ""
    private(set) var startedAt: Date?
    private(set) var lastTailMs: Double?

    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private var client: VoxtralStreamClient?
    private var overlay: NSPanel?
    /// Les morceaux arrivent sur le fil audio ; le réseau ne doit pas s'y
    /// faire. Une file à part, sérielle, garde l'ordre sans bloquer la capture.
    private let pump = DispatchQueue(label: "fr.lyriastudio.caspr.voxtral.pump")

    /// Les échantillons en attente d'être versés.
    ///
    /// Dans une boîte à part, et pas par goût : ce contrôleur est
    /// `@MainActor`, alors que le robinet audio livre ses morceaux sur son
    /// propre fil. Une propriété du contrôleur serait donc inaccessible depuis
    /// la capture — le compilateur le refuse, à raison. La boîte n'appartient à
    /// aucun acteur et se garde elle-même.
    private let buffer = SampleBuffer()

    /// Une seconde d'audio avant d'appeler le moteur.
    ///
    /// Le robinet audio livre ~85 ms à la fois, et les verser tels quels était
    /// ma première version. Mesuré sur 39,7 s de dictée : **41,4 s de calcul en
    /// morceaux de 85 ms contre 26,5 s en morceaux d'une seconde**. Le texte
    /// produit est le même — ce n'est pas une question de qualité — mais à
    /// ×1,04 du temps réel le modèle ne suit plus la parole, prend du retard
    /// pendant qu'on parle, et le rattrapage à la fin grandit avec la durée.
    /// C'est ce qui faisait « des fois c'est rapide, des fois c'est lent ».
    ///
    /// À une seconde on est à ×0,67 : le modèle garde de l'avance quoi qu'il
    /// arrive. Le prix est un aperçu qui avance par paliers d'une seconde au
    /// lieu de couler, ce qui est le bon échange — l'aperçu rassure, le
    /// rattrapage fait attendre.
    private static let chunkSamples = 16_000

    var isRunning: Bool { phase == .listening || phase == .connecting }

    // MARK: - Le cycle

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard phase == .idle || isFailed else { return }
        guard VoxtralStreamClient.isAvailable else {
            fail("Le service Voxtral ne tourne pas. Lancez ./scripts/voxtral-stream.sh")
            return
        }
        text = ""
        lastTailMs = nil
        phase = .connecting
        showOverlay()

        let client = VoxtralStreamClient()
        self.client = client
        do {
            try client.start()
        } catch {
            fail(error.localizedDescription)
            return
        }

        // Le micro seulement après que le moteur a répondu : découvrir qu'il
        // n'y a personne au bout après une minute de parole, c'est perdre la
        // minute.
        recorder.onSamples = { [weak self] samples in
            guard let self else { return }
            let ready = self.buffer.append(samples, releasingAt: Self.chunkSamples)
            guard !ready.isEmpty else { return }
            self.pump.async {
                guard let delta = try? client.feed(ready), !delta.isEmpty else { return }
                Task { @MainActor [weak self] in self?.text += delta }
            }
        }
        do {
            try recorder.start()
            startedAt = Date()
            phase = .listening
        } catch {
            client.cancel()
            fail(error.localizedDescription)
        }
    }

    func stop() {
        guard isRunning, let client else { return }
        phase = .finishing
        recorder.onSamples = nil
        _ = recorder.stop()

        // Le reste du tampon part avant la fermeture : sans ça, jusqu'à une
        // seconde de parole — la fin de la dernière phrase — n'atteindrait
        // jamais le moteur.
        let tail = buffer.drain()

        let began = Date()
        pump.async { [weak self] in
            if !tail.isEmpty { _ = try? client.feed(tail) }
            let final = (try? client.finish()) ?? ""
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastTailMs = Date().timeIntervalSince(began) * 1000
                self.client = nil
                if final.isEmpty {
                    self.fail("Rien n'a été transcrit.")
                    return
                }
                self.text = final
                await self.insert(final)
                self.phase = .idle
                self.hideOverlay(after: 0.35)
            }
        }
    }

    func cancel() {
        recorder.onSamples = nil
        _ = buffer.drain()
        recorder.cancel()
        client?.cancel()
        client = nil
        phase = .idle
        hideOverlay(after: 0)
    }

    private var isFailed: Bool { if case .failed = phase { return true }; return false }

    private func fail(_ message: String) {
        recorder.onSamples = nil
        _ = buffer.drain()
        recorder.cancel()
        client?.cancel()
        client = nil
        phase = .failed(message)
        hideOverlay(after: 3)
    }

    private func insert(_ final: String) async {
        do {
            try await injector.inject(final)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - La barre

    private func showOverlay() {
        guard overlay == nil else { return }
        let view = NSHostingView(rootView: StreamingOverlayView(controller: self))
        // Non activant, comme la barre principale : le texte doit atterrir au
        // curseur qui a déjà le focus, pas dans la fenêtre qui l'annonce.
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 620, height: 96),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = view
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(.init(x: f.midX - 310, y: f.minY + 120))
        }
        panel.orderFrontRegardless()
        overlay = panel
    }

    private func hideOverlay(after delay: TimeInterval) {
        let panel = overlay
        overlay = nil
        guard let panel else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { panel.close() }
    }
}

/// Le tampon d'échantillons, partagé entre le fil audio et la file d'envoi.
///
/// Une classe minuscule plutôt qu'un `actor` : la capture audio appelle depuis
/// un fil temps réel, où attendre l'ordonnancement d'un acteur est exactement
/// ce qu'il ne faut pas faire. Un verrou tenu le temps d'un `append` coûte
/// quelques nanosecondes et ne cède jamais le fil.
final class SampleBuffer: @unchecked Sendable {
    private var samples: [Float] = []
    private let lock = NSLock()

    /// Ajoute, et rend le lot complet dès qu'il atteint le seuil — sinon rien.
    func append(_ new: [Float], releasingAt threshold: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: new)
        guard samples.count >= threshold else { return [] }
        let ready = samples
        samples.removeAll(keepingCapacity: true)
        return ready
    }

    /// Vide et rend ce qui restait — la fin de la dernière phrase.
    @discardableResult
    func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let rest = samples
        samples.removeAll(keepingCapacity: true)
        return rest
    }
}
