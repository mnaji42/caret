import Foundation
import Observation
import Speech

/// Le modèle de reconnaissance de macOS : présent, ou à faire venir.
///
/// Ce n'est pas une option. Le moteur de macOS écrit l'aperçu en direct sous
/// la barre d'enregistrement quel que soit le moteur retenu, et il est le
/// moteur par défaut : sans son modèle, Sofler ne montre rien pendant qu'on
/// parle et n'écrit rien à la fin. Il n'y a donc pas de choix à proposer, mais
/// un prérequis à satisfaire.
///
/// Sur un Mac qui a servi, il est déjà là — la dictée du système l'a fait
/// descendre un jour. Sur un macOS fraîchement installé, il n'y a rien, et
/// c'est ce cas-là qu'on n'avait jamais vu : `isAvailable` répond faux et
/// l'application annonce une indisponibilité qui ressemble à un verdict sur la
/// machine, alors qu'il manque un fichier que le système sait aller chercher.
///
/// Le téléchargement a donc lieu **pendant l'accueil**, à l'étape des
/// autorisations — avant la page où l'on essaie sa voix pour la première fois.
/// Le faire à la première dictée reviendrait à faire attendre quelqu'un qui
/// vient d'appuyer sur une touche pour voir si ça marche, ce qui est
/// exactement le moment où il ne faut pas hésiter.
@MainActor
@Observable
final class SpeechAssets {
    static let shared = SpeechAssets()

    enum State: Equatable {
        case unknown
        case checking
        /// Fraction téléchargée, quand le système la rapporte.
        case installing(Double)
        case ready
        /// Le système ne propose pas ce modèle ici — trop vieux macOS, ou
        /// langue non couverte.
        case unsupported(String)
        case failed(String)
    }

    private(set) var state: State = .unknown

    var isSettled: Bool {
        switch state {
        case .ready, .unsupported, .failed: true
        default: false
        }
    }

    /// Vérifie, et télécharge si nécessaire.
    ///
    /// Sans effet si le modèle est déjà là : la requête d'installation rend
    /// `nil` dans ce cas, ce qui rend l'appel gratuit à chaque ouverture de
    /// l'accueil.
    func ensure(language: String) async {
        guard case .unknown = state else { return }
        guard #available(macOS 26.0, *) else {
            state = .unsupported("Le moteur intégré demande macOS 26.")
            return
        }
        state = .checking

        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: language)) else {
            state = .unsupported("macOS ne reconnaît pas « \(language) ».")
            return
        }

        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [])
        do {
            // Réserver la langue **avant** de demander quoi que ce soit sur
            // ses actifs. C'est l'étape qui manquait, et le système le disait
            // en toutes lettres sans qu'on l'entende :
            //
            //     Cannot check the download status, fr.lyriastudio.sofler
            //     is not subscribed to transcription.fr
            //
            // « Souscrire » à une langue, c'est `AssetInventory.reserve`. Sans
            // elle, l'inventaire refuse même de dire si le modèle est présent
            // — d'où une erreur que « Réessayer » ne pouvait pas lever, puisque
            // le second essai reposait la même question mal posée.
            //
            // `AppleSpeechEngine.transcribe` réservait déjà, ce qui explique
            // que le défaut soit resté invisible sur une machine où les actifs
            // étaient là : la réservation y était sans objet.
            try await LivePreview.reserve(locale)

            guard let request = try await AssetInventory
                .assetInstallationRequest(supporting: [transcriber]) else {
                state = .ready
                return
            }

            // L'avancement est publié par le système sur un `Progress`. On le
            // relit à intervalle plutôt que de s'y abonner : la valeur suffit,
            // et un observateur KVO pour un téléchargement qui dure une minute
            // coûterait plus de code qu'il n'en vaut.
            state = .installing(0)
            let progress = request.progress
            let watcher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard let self, case .installing = self.state else { continue }
                    self.state = .installing(progress.fractionCompleted)
                }
            }
            defer { watcher.cancel() }

            Log.info("assets macOS : téléchargement pour \(locale.identifier)")
            try await request.downloadAndInstall()
            state = .ready
            Log.info("assets macOS : installés")
        } catch {
            Log.error("assets macOS : \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Après un échec, pour rejouer la vérification.
    func retry(language: String) async {
        state = .unknown
        await ensure(language: language)
    }
}
