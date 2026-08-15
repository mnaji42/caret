import Foundation
import Observation
import SoflerCore

/// Regarde s'il existe une version plus récente, sur les releases GitHub.
///
/// Sofler n'est pas notarisé et ne passe par aucun magasin d'applications : il
/// s'installe en glissant un bundle depuis une image disque. Rien ne le mettra
/// donc à jour tout seul, et une correction de bug ne parviendrait jamais à
/// quelqu'un qui a installé une fois et n'y pense plus. Cette vérification est
/// le seul canal qui reste.
///
/// Elle compare des **releases**, pas des commits. Une branche `main` bouge
/// plusieurs fois par jour, souvent pour des travaux en cours ; prévenir à
/// chaque commit reviendrait à ne jamais être cru. Un tag est une déclaration
/// explicite : « cette version-ci est bonne à installer ».
///
/// Aucune erreur n'est présentée à l'utilisateur. Un réseau coupé, une API
/// injoignable ou un quota GitHub épuisé ne sont pas des évènements qui
/// justifient d'interrompre quelqu'un dans son travail — la vérification
/// réessaiera demain.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
        let page: URL
        let notes: String
    }

    /// Renseigné seulement si la version distante est **strictement**
    /// supérieure à celle qui tourne.
    private(set) var newer: Release?
    private(set) var checking = false
    /// Pour le bouton « vérifier maintenant » des Réglages, qui lui a le droit
    /// de dire que ça n'a pas marché : l'utilisateur vient de le demander.
    private(set) var lastError: String?

    /// Quand la dernière vérification a abouti. Persistée, donc survit au
    /// redémarrage — sans quoi les Réglages afficheraient « à jour » au premier
    /// lancement, alors que rien n'a encore été demandé à personne.
    var lastCheckedAt: Date? {
        UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    private let endpoint = URL(string:
        "https://api.github.com/repos/mnaji42/sofler/releases/latest")!
    private let lastCheckKey = "sofler.update.lastCheck"

    // MARK: - Identité du build

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Ce bundle correspond-il exactement à un tag, arbre propre ?
    ///
    /// Écrit par scripts/install.sh depuis git. Une machine de développement
    /// est presque toujours en avance sur la dernière release : lui proposer
    /// de « mettre à jour » vers du code plus ancien que le sien serait absurde.
    static var isReleaseBuild: Bool {
        Bundle.main.infoDictionary?["SoflerIsRelease"] as? Bool ?? false
    }

    static var gitDescribe: String {
        Bundle.main.infoDictionary?["SoflerGitDescribe"] as? String ?? "inconnu"
    }

    /// Ce que les Réglages affichent sous la version.
    static var buildLabel: String {
        isReleaseBuild ? currentVersion : "\(currentVersion) · build de développement"
    }

    // MARK: - Déclenchement

    /// Appelé au lancement. Ne fait rien la plupart du temps.
    func checkIfDue() async {
        guard Preferences.shared.checksForUpdates else { return }
        guard Self.isReleaseBuild else { return }
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        // Une fois par jour. L'API publique de GitHub tolère soixante appels
        // par heure et par adresse ; le vrai motif est ailleurs : une app qui
        // interroge un serveur à chaque lancement est une app qui traque.
        if let last, Date().timeIntervalSince(last) < 24 * 3600 { return }
        await check()
    }

    /// Vérification explicite, depuis les Réglages. Ignore la temporisation et
    /// le garde-fou du build de développement — c'est le seul moyen de tester
    /// la fonction sans publier une release.
    func check() async {
        guard !checking else { return }
        checking = true
        lastError = nil
        defer { checking = false }

        do {
            var request = URLRequest(url: endpoint)
            // L'API de GitHub rejette les requêtes sans User-Agent.
            request.setValue("Sofler/\(Self.currentVersion)",
                             forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json",
                             forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            // Ne pas servir une réponse de cache : la question posée est
            // précisément « qu'y a-t-il de neuf ».
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                // 404 tant qu'aucune release n'est publiée : ce n'est pas une
                // panne, c'est l'état normal d'un dépôt encore vierge.
                throw Failure.http(code)
            }

            let payload = try JSONDecoder().decode(Payload.self, from: data)
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            let remote = payload.tagName.hasPrefix("v")
                ? String(payload.tagName.dropFirst())
                : payload.tagName
            guard Version.isNewer(remote, than: Self.currentVersion),
                  let page = URL(string: payload.htmlUrl) else {
                newer = nil
                return
            }
            newer = Release(version: remote, page: page,
                            notes: payload.body ?? "")
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Réponse

    private struct Payload: Decodable {
        let tagName: String
        let htmlUrl: String
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body
        }
    }

    private enum Failure: LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(404): "Aucune release publiée pour l'instant."
            case .http(let code): "GitHub a répondu \(code)."
            }
        }
    }
}
