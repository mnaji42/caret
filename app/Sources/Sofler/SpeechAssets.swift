import Foundation
import Observation
import Speech

/// Les modèles de reconnaissance de macOS, langue par langue.
///
/// Ce n'est pas une option. Le moteur de macOS écrit l'aperçu en direct sous
/// la barre d'enregistrement quel que soit le moteur retenu, et il est le
/// moteur par défaut : sans son modèle, Sofler ne montre rien pendant qu'on
/// parle et n'écrit rien à la fin. Il n'y a donc pas de choix à proposer, mais
/// un prérequis à satisfaire — et à satisfaire **avant** le premier essai,
/// pas pendant.
///
/// ## Par langue, et pas globalement
///
/// La première version ne connaissait qu'un état d'ensemble, ce qui ne tenait
/// pas : les actifs sont fournis par locale. Quelqu'un qui a le français
/// installé et bascule sur l'anglais retombe exactement dans le cas de la
/// machine vierge, sans que rien ne le prépare. L'état est donc suivi langue
/// par langue, et la bascule sait ce qu'elle coûte.
///
/// ## Réserver avant de demander
///
/// L'inventaire refuse de répondre sur une langue à laquelle l'application n'a
/// pas souscrit — « is not subscribed to transcription.fr ». Souscrire, c'est
/// `AssetInventory.reserve`. Toute question sur les actifs passe donc après
/// elle ; l'ordre inverse produit une erreur qu'aucun « Réessayer » ne lève,
/// puisque le second essai repose la même question mal posée.
@MainActor
@Observable
final class SpeechAssets {
    static let shared = SpeechAssets()

    enum State: Equatable {
        case unknown
        case checking
        /// Absent, et récupérable.
        case missing
        /// Fraction téléchargée, quand le système la rapporte.
        case installing(Double)
        case ready
        /// Le système ne propose pas cette langue ici.
        case unsupported(String)
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    /// Un état par code de langue — « fr », « en ».
    private(set) var states: [String: State] = [:]

    func state(of language: String) -> State { states[language] ?? .unknown }

    /// Rien ne bloque : la langue est prête, ou le système ne la propose pas
    /// et rien ne la rendra disponible.
    func isSettled(_ language: String) -> Bool {
        switch state(of: language) {
        case .ready, .unsupported: true
        default: false
        }
    }

    // MARK: - Vérifier

    /// Où en est cette langue, sans rien télécharger.
    func check(_ language: String) async {
        guard #available(macOS 26.0, *) else {
            states[language] = .unsupported("Le moteur intégré demande macOS 26.")
            return
        }
        if case .installing = state(of: language) { return }
        states[language] = .checking

        guard let locale = await Self.locale(for: language) else {
            states[language] = .unsupported("macOS ne reconnaît pas cette langue.")
            return
        }
        let installed = await SpeechTranscriber.installedLocales
        states[language] = installed.contains { $0.identifier == locale.identifier }
            ? .ready : .missing
    }

    /// Récupère le modèle de cette langue.
    func install(_ language: String) async {
        guard #available(macOS 26.0, *) else { return }
        if case .installing = state(of: language) { return }

        guard let locale = await Self.locale(for: language) else {
            states[language] = .unsupported("macOS ne reconnaît pas cette langue.")
            return
        }
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [])
        states[language] = .installing(0)
        do {
            // Réserver d'abord. Cf. l'en-tête.
            try await LivePreview.reserve(locale)

            guard let request = try await AssetInventory
                .assetInstallationRequest(supporting: [transcriber]) else {
                states[language] = .ready
                return
            }

            // L'avancement est publié sur un `Progress` : relu à intervalle
            // plutôt qu'observé, la valeur suffit et un observateur KVO pour
            // une minute de téléchargement coûterait plus qu'il ne rapporte.
            let progress = request.progress
            let watcher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard let self,
                          case .installing = self.state(of: language) else { continue }
                    self.states[language] = .installing(progress.fractionCompleted)
                }
            }
            defer { watcher.cancel() }

            Log.info("assets macOS : téléchargement \(locale.identifier)")
            try await request.downloadAndInstall()
            states[language] = .ready
            Log.info("assets macOS : \(locale.identifier) installé")
        } catch {
            Log.error("assets macOS \(language) : \(error.localizedDescription)")
            states[language] = .failed(error.localizedDescription)
        }
    }

    /// Vérifie, puis télécharge si besoin. Ce que fait l'accueil.
    func ensure(_ language: String) async {
        await check(language)
        if case .missing = state(of: language) { await install(language) }
    }

    private static func locale(for language: String) async -> Locale? {
        guard #available(macOS 26.0, *) else { return nil }
        return await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: language))
    }
}
