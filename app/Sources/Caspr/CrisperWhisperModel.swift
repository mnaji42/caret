import Foundation

/// Les poids CrisperWhisper que Caspr sait faire charger au moteur.
///
/// Seules les variantes ouvertes figurent ici. Nyra publie aussi des versions
/// `_pro`, meilleures au classement (96,0 de F1 de disfluence contre 89,9),
/// mais elles sont sous licence commerciale : les proposer reviendrait à
/// pousser vers une porte fermée.
///
/// Le modèle se choisit au **démarrage du serveur**, pas par requête : en
/// changer suppose de réécrire l'agent de lancement et de redémarrer le
/// service. C'est pour ça que le choix vit ici et non dans un en-tête de
/// protocole.
enum CrisperWhisperModel: String, CaseIterable, Codable, Sendable {
    case small, medium, turbo, large

    /// Ce que le serveur reçoit en `--model`.
    var identifier: String { "nyralabs/CrisperWhisper2.0_\(rawValue)" }

    /// Nom du dossier dans le cache Hugging Face.
    var cacheDirectoryName: String { "models--nyralabs--CrisperWhisper2.0_\(rawValue)" }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .turbo: "Turbo"
        case .large: "Large"
        }
    }

    /// Octets des poids, relevés sur Hugging Face. Affichés avant de lancer un
    /// téléchargement : personne ne devrait découvrir qu'il en a pour trois
    /// gigaoctets une fois qu'ils sont partis.
    /// Ce que pèsent uv, Python et les bibliothèques, une fois pour toutes.
    static let environmentBytes: Int64 = 1_200_000_000

    var downloadBytes: Int64 {
        switch self {
        case .small: 480_000_000
        case .medium: 1_530_000_000
        case .turbo: 1_620_000_000
        case .large: 3_090_000_000
        }
    }

    var downloadSize: String { Self.frenchSize(downloadBytes) }

    /// « 480 Mo », « 1,62 Go ». En français, parce que l'interface l'est.
    ///
    /// `ByteCountFormatter` suit la langue du **système**, pas celle de
    /// l'application : sur un Mac en anglais, la grille annonçait « 1,53 GB »
    /// au milieu de phrases françaises.
    static func frenchSize(_ bytes: Int64) -> String {
        let mo = Double(bytes) / 1_000_000
        if mo < 1000 { return "\(Int(mo.rounded())) Mo" }
        return String(format: "%.2f Go", mo / 1000)
            .replacingOccurrences(of: ".", with: ",")
    }

    /// Mémoire vive occupée par le service une fois le modèle chargé, en ordre
    /// de grandeur. Le service reste résident : c'est ce qui fait sa vitesse,
    /// et c'est ce qu'on paie tant qu'il tourne.
    var residentMemory: String {
        switch self {
        case .small: "~1 Go"
        case .medium: "~3 Go"
        case .turbo: "~3 Go"
        case .large: "~6 Go"
        }
    }

    var isRecommended: Bool { self == .turbo }

    /// Le nom tel qu'il apparaît dans la grille du catalogue, avec ce qui le
    /// caractérise en un mot. Repris du prototype.
    var catalogueName: String {
        switch self {
        case .turbo: "Turbo ★ (Recommandé)"
        case .small: "Small (Léger)"
        case .medium: "Medium (Équilibré)"
        case .large: "Large (Précision Max)"
        }
    }

    /// La latence **mesurée sur de vraies dictées de ce projet**, ou `nil`.
    ///
    /// `nil` pour trois modèles sur quatre, et c'est la réponse honnête : le
    /// prototype annonce 210, 410, 690 et 1200 ms, mais un seul de ces chiffres
    /// a été relevé ici. Afficher les trois autres fabriquerait un classement
    /// que personne n'a vérifié — et sur lequel quelqu'un choisirait un
    /// téléchargement de plusieurs gigaoctets.
    var measuredLatency: String? {
        self == .turbo ? "763 ms mesurés" : nil
    }

    /// Ce que coûte une installation complète depuis rien : l'environnement
    /// Python **plus** les poids.
    ///
    /// Annoncé d'un bloc parce que c'est ce qui part réellement sur le réseau.
    /// Ne montrer que le poids du modèle ferait découvrir 1,2 Go de plus une
    /// fois le téléchargement lancé.
    var totalDownload: String {
        "\(totalDownloadShort) (uv/python 1,2 Go + modèle \(downloadSize))"
    }

    /// Le même total, sans le détail — pour un **bouton**.
    ///
    /// « Installer CrisperWhisper (2,82 Go (uv/python 1,2 Go + modèle
    /// 1,62 Go)) » : deux niveaux de parenthèses dans un libellé de bouton,
    /// assez long pour s'étaler sur toute la largeur de la carte et se lire
    /// comme un message d'erreur. Le détail n'est pas perdu — la phrase juste
    /// au-dessus l'énonce déjà, et c'est sa place : un bouton dit ce qu'il
    /// fait et ce que ça coûte, pas comment le coût se décompose.
    var totalDownloadShort: String {
        Self.frenchSize(downloadBytes + Self.environmentBytes)
    }

    /// Ce qu'on sait, et ce qu'on ne sait pas.
    ///
    /// Seul `turbo` a été mesuré sur de vraies dictées de ce projet. Prêter
    /// aux autres des qualités non vérifiées serait inventer un classement.
    var explanation: String {
        switch self {
        case .turbo:
            "Le seul mesuré sur de vraies dictées ici : 29 termes techniques "
                + "sur 29 conservés, 763 ms de latence médiane. C'est le bon "
                + "point de départ."
        case .large:
            "Le plus gros modèle ouvert. Plus lent et deux fois plus lourd en "
                + "mémoire que turbo, sans gain mesuré sur ce projet — à "
                + "essayer si turbo vous déçoit sur votre voix."
        case .medium:
            "Entre small et turbo, non mesuré ici. Peu de raisons de le "
                + "préférer à turbo, qui pèse à peine plus."
        case .small:
            "Le plus léger et le plus rapide, et de loin le moins gourmand en "
                + "mémoire. Non mesuré ici : attendez-vous à ce qu'il "
                + "reconnaisse moins bien votre vocabulaire."
        }
    }

    /// Les poids sont-ils déjà sur cette machine ?
    ///
    /// On vérifie le poids réel du dossier, pas sa seule existence : un
    /// téléchargement interrompu laisse une arborescence en place, et
    /// l'annoncer « installé » enverrait l'utilisateur vers un service qui
    /// échouerait au chargement sans qu'il comprenne pourquoi.
    var isDownloaded: Bool {
        guard let walker = FileManager.default.enumerator(
            at: cacheDirectory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        else { return false }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? 0)
            // Assez pour trancher sans parcourir des milliers de fichiers.
            if total > downloadBytes / 2 { return true }
        }
        return false
    }

    var cacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub/\(cacheDirectoryName)")
    }

    /// Ce qui est déjà descendu, en octets.
    ///
    /// Distinct de `isDownloaded`, qui s'arrête à la moitié dès qu'il a de
    /// quoi trancher. Ici il faut le total exact : c'est ce qui fait avancer
    /// la barre pendant le téléchargement. Le compte inclut les fichiers
    /// partiels que `huggingface_hub` laisse dans `blobs` en cours de route,
    /// donc la progression ne reste pas à zéro pendant qu'un gros fichier
    /// descend.
    var downloadedBytes: Int64 {
        guard let walker = FileManager.default.enumerator(
            at: cacheDirectory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    static var downloaded: [CrisperWhisperModel] { allCases.filter(\.isDownloaded) }
}
