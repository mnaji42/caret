import Foundation
import Speech

/// Une langue de dictée, telle qu'on la choisit.
///
/// ## Deux codes, et ils ne sont pas interchangeables
///
/// Une langue porte ici **deux** identifiants, parce que deux mondes les
/// réclament dans des formats différents et qu'en confondre un seul dégrade la
/// transcription sans rien dire :
///
/// - `code` est la locale complète (`fr-FR`). C'est ce que réclament
///   `SpeechTranscriber` et `SFSpeechRecognizer` : les modèles de macOS sont
///   fournis *par région*, et `fr-CA` n'est pas `fr-FR`.
/// - `base` est le code ISO-639-1 (`fr`). C'est ce que réclame Whisper, qui
///   compose le jeton `<|fr|>` pour forcer la langue au décodeur.
///
/// Envoyer `fr-FR` à Whisper ne provoque **aucune erreur** : `<|fr-FR|>`
/// n'existe pas dans son vocabulaire, `convert_tokens_to_ids` rend le jeton
/// inconnu, et le préfixe de décodage forcé part corrompu. La transcription
/// continue, simplement moins bonne — le pire mode de panne pour ce projet.
/// D'où la conversion, faite une seule fois, à la frontière du socket
/// (cf. `SocketSpeechEngine`).
///
/// `base` est aussi ce qu'archive le corpus, pour que les dictées d'avant le
/// multi-langues restent comparables à celles d'après. Cf. `CorpusEntry`.
struct Language: Identifiable, Hashable, Sendable {
    /// Locale complète — `fr-FR`. Sert d'identité et de clé de persistance.
    let code: String
    /// Nom dans sa propre langue — « Français », « 日本語 ».
    let name: String
    /// Région, dans sa propre langue — « France », « 日本 ».
    let region: String
    let flag: String
    /// Poids **estimé** du modèle Apple Intelligence, en octets.
    ///
    /// Estimé, et il faut le dire à l'écran. Apple n'expose le poids d'un actif
    /// ni avant ni pendant son installation : `AssetInventory` ne rend qu'une
    /// requête opaque. Ces valeurs viennent de mesures ponctuelles et servent à
    /// donner un ordre de grandeur — « environ 123 Mo » — jamais à annoncer un
    /// chiffre exact qu'on serait incapable de tenir.
    let estimatedModelBytes: Int64

    var id: String { code }

    /// Le code ISO-639-1 — `fr` pour `fr-FR`.
    ///
    /// Dérivé, jamais stocké : une seule vérité par langue, et `Locale` sait
    /// déjà faire cette extraction. Le repli sur `code` ne sert que si l'on
    /// nous confie un identifiant que `Locale` ne sait pas lire.
    var base: String {
        Locale(identifier: code).language.languageCode?.identifier ?? code
    }

    /// « Français » quand la langue n'a qu'une région au catalogue,
    /// « Français (Canada) » quand elle en a plusieurs.
    ///
    /// Afficher la région partout alourdit une liste où l'immense majorité des
    /// gens ne choisit qu'une variante ; ne l'afficher nulle part rend `fr-FR`
    /// et `fr-CA` indistinguables. On ne la montre donc que là où elle tranche.
    var displayName: String {
        Self.catalog.filter { $0.base == base }.count > 1
            ? "\(name) (\(region))"
            : name
    }

    /// « 🇫🇷 Français » — pour les pastilles et les puces.
    var badge: String { "\(flag) \(name)" }

    /// Poids arrondi, présenté comme l'approximation qu'il est.
    var estimatedSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: estimatedModelBytes, countStyle: .file)
    }
}

// MARK: - Catalogue

extension Language {
    /// Le français de France, et rien d'autre, quand il faut bien commencer
    /// quelque part.
    ///
    /// C'est le seul défaut écrit en dur du fichier. Il vaut pour la valeur
    /// initiale de `selectedLanguages` et pour le repli quand une liste
    /// deviendrait vide — jamais pour décider de ce que la machine sait faire,
    /// qui se mesure (cf. `installed(among:)`).
    static let fallback = "fr-FR"

    /// Ce que Sofler sait nommer.
    ///
    /// **Ce n'est pas la liste de ce qui marche ici.** C'est un dictionnaire de
    /// libellés : drapeaux, noms, régions, ordres de grandeur. Ce que cette
    /// machine sait réellement transcrire se demande au système, langue par
    /// langue, et se mesure à l'exécution — un Mac Intel, une machine virtuelle
    /// et un Mac Apple Silicon à jour ne répondent pas la même chose, et aucun
    /// numéro de version ne permet de le deviner.
    ///
    /// Une langue absente d'ici reste utilisable : `named(_:)` fabrique une
    /// entrée depuis `Locale` plutôt que de la faire disparaître de l'interface.
    static let catalog: [Language] = [
        Language(code: "fr-FR", name: "Français", region: "France", flag: "🇫🇷", estimatedModelBytes: 65_000_000),
        Language(code: "fr-CA", name: "Français", region: "Canada", flag: "🇨🇦", estimatedModelBytes: 64_000_000),
        Language(code: "fr-CH", name: "Français", region: "Suisse", flag: "🇨🇭", estimatedModelBytes: 62_000_000),
        Language(code: "fr-BE", name: "Français", region: "Belgique", flag: "🇧🇪", estimatedModelBytes: 62_000_000),
        Language(code: "en-US", name: "English", region: "United States", flag: "🇺🇸", estimatedModelBytes: 58_000_000),
        Language(code: "en-GB", name: "English", region: "United Kingdom", flag: "🇬🇧", estimatedModelBytes: 57_000_000),
        Language(code: "en-CA", name: "English", region: "Canada", flag: "🇨🇦", estimatedModelBytes: 56_000_000),
        Language(code: "en-AU", name: "English", region: "Australia", flag: "🇦🇺", estimatedModelBytes: 56_000_000),
        Language(code: "en-IN", name: "English", region: "India", flag: "🇮🇳", estimatedModelBytes: 55_000_000),
        Language(code: "es-ES", name: "Español", region: "España", flag: "🇪🇸", estimatedModelBytes: 62_000_000),
        Language(code: "es-MX", name: "Español", region: "México", flag: "🇲🇽", estimatedModelBytes: 61_000_000),
        Language(code: "es-US", name: "Español", region: "Estados Unidos", flag: "🇺🇸", estimatedModelBytes: 60_000_000),
        Language(code: "de-DE", name: "Deutsch", region: "Deutschland", flag: "🇩🇪", estimatedModelBytes: 68_000_000),
        Language(code: "de-AT", name: "Deutsch", region: "Österreich", flag: "🇦🇹", estimatedModelBytes: 66_000_000),
        Language(code: "de-CH", name: "Deutsch", region: "Schweiz", flag: "🇨🇭", estimatedModelBytes: 65_000_000),
        Language(code: "it-IT", name: "Italiano", region: "Italia", flag: "🇮🇹", estimatedModelBytes: 59_000_000),
        Language(code: "pt-BR", name: "Português", region: "Brasil", flag: "🇧🇷", estimatedModelBytes: 63_000_000),
        Language(code: "pt-PT", name: "Português", region: "Portugal", flag: "🇵🇹", estimatedModelBytes: 61_000_000),
        Language(code: "nl-NL", name: "Nederlands", region: "Nederland", flag: "🇳🇱", estimatedModelBytes: 58_000_000),
        Language(code: "nl-BE", name: "Vlaams", region: "België", flag: "🇧🇪", estimatedModelBytes: 57_000_000),
        Language(code: "sv-SE", name: "Svenska", region: "Sverige", flag: "🇸🇪", estimatedModelBytes: 56_000_000),
        Language(code: "nb-NO", name: "Norsk", region: "Norge", flag: "🇳🇴", estimatedModelBytes: 55_000_000),
        Language(code: "da-DK", name: "Dansk", region: "Danmark", flag: "🇩🇰", estimatedModelBytes: 55_000_000),
        Language(code: "fi-FI", name: "Suomi", region: "Suomi", flag: "🇫🇮", estimatedModelBytes: 58_000_000),
        Language(code: "pl-PL", name: "Polski", region: "Polska", flag: "🇵🇱", estimatedModelBytes: 62_000_000),
        Language(code: "tr-TR", name: "Türkçe", region: "Türkiye", flag: "🇹🇷", estimatedModelBytes: 61_000_000),
        Language(code: "uk-UA", name: "Українська", region: "Україна", flag: "🇺🇦", estimatedModelBytes: 65_000_000),
        Language(code: "ru-RU", name: "Русский", region: "Россия", flag: "🇷🇺", estimatedModelBytes: 74_000_000),
        Language(code: "ja-JP", name: "日本語", region: "日本", flag: "🇯🇵", estimatedModelBytes: 72_000_000),
        Language(code: "ko-KR", name: "한국어", region: "대한민국", flag: "🇰🇷", estimatedModelBytes: 70_000_000),
        Language(code: "zh-CN", name: "简体中文", region: "中国大陆", flag: "🇨🇳", estimatedModelBytes: 80_000_000),
        Language(code: "zh-TW", name: "繁體中文", region: "台灣", flag: "🇹🇼", estimatedModelBytes: 78_000_000),
        Language(code: "zh-HK", name: "廣東話", region: "香港", flag: "🇭🇰", estimatedModelBytes: 76_000_000),
        Language(code: "ar-SA", name: "العربية", region: "المملكة العربية السعودية", flag: "🇸🇦", estimatedModelBytes: 67_000_000),
        Language(code: "he-IL", name: "עברית", region: "ישראל", flag: "🇮🇱", estimatedModelBytes: 60_000_000),
        Language(code: "hi-IN", name: "हिन्दी", region: "भारत", flag: "🇮🇳", estimatedModelBytes: 69_000_000),
        Language(code: "th-TH", name: "ไทย", region: "ประเทศไทย", flag: "🇹🇭", estimatedModelBytes: 66_000_000),
        Language(code: "vi-VN", name: "Tiếng Việt", region: "Việt Nam", flag: "🇻🇳", estimatedModelBytes: 63_000_000),
        Language(code: "id-ID", name: "Bahasa Indonesia", region: "Indonesia", flag: "🇮🇩", estimatedModelBytes: 56_000_000),
    ]

    /// La langue de ce code, connue du catalogue ou déduite de `Locale`.
    ///
    /// Ne rend jamais `nil`, et c'est délibéré : un code inconnu du catalogue
    /// — parce que macOS en propose un que nous n'avons pas listé, ou parce
    /// qu'une préférence a été écrite par une version ultérieure — doit rester
    /// affichable. Le faire disparaître de l'interface donnerait une liste de
    /// langues d'où la langue active serait absente, et un sélecteur sans
    /// sélection.
    static func named(_ code: String) -> Language {
        if let known = catalog.first(where: { $0.code == code }) { return known }

        let locale = Locale(identifier: code)
        let display = locale.localizedString(forIdentifier: code)
            ?? locale.localizedString(forLanguageCode: code)
            ?? code
        return Language(code: code, name: display, region: "",
                        // Le globe plutôt qu'un drapeau deviné : une langue n'a
                        // pas de pays, et en choisir un est un tort qu'on fait
                        // à quelqu'un.
                        flag: "🌐", estimatedModelBytes: 60_000_000)
    }

    /// La locale complète à retenir pour un code, court ou déjà complet.
    ///
    /// Sert à la migration de l'ancien réglage à code court (`fr`) vers une
    /// locale (`fr-FR`), et à chaque fois qu'on reçoit un identifiant dont on
    /// ne sait pas s'il porte une région.
    ///
    /// La région de la machine passe en premier — quelqu'un qui dicte en
    /// français depuis Montréal veut `fr-CA`, et lui imposer `fr-FR` lui donne
    /// un modèle entraîné sur un autre accent. À défaut, la première entrée du
    /// catalogue pour cette langue, qui est aussi la plus répandue.
    static func preferred(for code: String) -> String {
        if catalog.contains(where: { $0.code == code }) { return code }

        let base = Locale(identifier: code).language.languageCode?.identifier ?? code
        let sameLanguage = catalog.filter { $0.base == base }
        guard !sameLanguage.isEmpty else { return code }

        if let here = Locale.current.region?.identifier,
           let local = sameLanguage.first(where: {
               Locale(identifier: $0.code).region?.identifier == here
           }) {
            return local.code
        }
        return sameLanguage[0].code
    }

    /// Filtre le catalogue sur une recherche libre.
    ///
    /// Cherche dans le nom, la région et le code : on tape « canada » aussi
    /// bien que « français » ou « fr-CA », et la casse comme les accents sont
    /// ignorés — `.caseInsensitive` seul laissait « francais » sans résultat.
    static func matching(_ query: String) -> [Language] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return catalog }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return catalog.filter {
            $0.name.range(of: needle, options: options) != nil
                || $0.region.range(of: needle, options: options) != nil
                || $0.code.range(of: needle, options: options) != nil
        }
    }
}

// MARK: - Ce que cette machine sait faire

extension Language {
    /// Les langues que CrisperWhisper couvre, en codes ISO-639-1.
    ///
    /// Les poids embarquent leurs langues : il n'y a rien à télécharger par
    /// langue, et la liste ne dépend pas de la machine. Restreinte à ce qui a
    /// été constaté utilisable — Whisper en annonce 99, mais la queue de
    /// distribution donne des résultats qu'on ne veut proposer à personne.
    static let crisperWhisperBases: Set<String> = [
        "fr", "en", "es", "de", "it", "pt", "nl", "ja", "zh", "ru",
        "ar", "ko", "pl", "sv", "tr", "uk", "hi",
    ]

    /// CrisperWhisper sait-il travailler dans cette langue ?
    var isCoveredByCrisperWhisper: Bool {
        Self.crisperWhisperBases.contains(base)
    }

    /// Les locales que la version **Apple Intelligence** propose ici.
    ///
    /// Demandé au système, jamais déduit d'un numéro de version : une machine
    /// virtuelle en macOS 26 rend une liste vide. Vide veut donc dire « ce
    /// moteur n'existe pas sur cette machine », pas « macOS est trop ancien ».
    static func systemSupportedLocales() async -> [String] {
        guard #available(macOS 26.0, *) else { return [] }
        return await SpeechTranscriber.supportedLocales.map(\.identifier)
    }

    /// Les locales dont le modèle est **déjà sur le disque**.
    ///
    /// Quelqu'un a pu les installer depuis Réglages Système ou Siri avant même
    /// de connaître Sofler : proposer un téléchargement dans ce cas ferait
    /// perdre du temps et de la confiance. Cf. `03_REGLES_SYSTEME_MACOS`.
    static func systemInstalledLocales() async -> [String] {
        guard #available(macOS 26.0, *) else { return [] }
        return await SpeechTranscriber.installedLocales.map(\.identifier)
    }
}
