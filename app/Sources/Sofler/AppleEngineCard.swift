import SwiftUI

/// Le moteur de macOS : quelle version, et les modèles qu'elle réclame.
///
/// ## Une seule technologie, pas deux réglages
///
/// Les documents décrivent un paramètre `target: 'live' | 'final'` permettant
/// de régler séparément la version employée par l'aperçu en direct et celle du
/// texte final. Ce composant ne l'expose pas, délibérément : quand macOS écrit,
/// l'aperçu doit employer **exactement** la version qui écrira, sinon il montre
/// pendant qu'on parle un texte qu'aucun moteur ne produira. Deux réglages
/// libres auraient permis de configurer précisément cette incohérence.
/// Cf. `Preferences.liveEngineTechnology`.
///
/// ## Ce qui bloque, et ce qui n'a pas à bloquer
///
/// Le doc 02 se contredit sur ce point : §1 exige que **toutes** les langues
/// retenues aient leur modèle, §0.quater dit que seule la langue active
/// détermine si le moteur est prêt. C'est §0.quater qui a raison, et l'autre
/// lecture serait pénible : quelqu'un qui a déclaré cinq langues et téléchargé
/// celle dans laquelle il dicte peut dicter — l'en empêcher pour un modèle
/// espagnol dont il se servira dans trois semaines n'a aucune contrepartie.
///
/// Les langues secondaires manquantes sont donc **proposées, jamais exigées**.
struct AppleEngineCard: View, ValidatingComponent {
    /// Imbriqué sous une ligne de choix : la carte perd son cadre et son
    /// en-tête, qui feraient une carte dans une carte.
    var isSubCard = false

    @State private var prefs = Preferences.shared
    @State private var assets = SpeechAssets.shared
    @State private var monitor = PermissionsMonitor.shared
    @State private var installing: Set<String> = []

    // MARK: - Validité

    /// Prêt quand la **langue active** peut être transcrite.
    ///
    /// Deux conditions selon la version, et elles n'ont rien à voir : Apple
    /// Intelligence veut son modèle sur le disque, la Dictée veut le droit de
    /// reconnaissance vocale — elle se sert des actifs que macOS a déjà.
    static func validate() -> ComponentValidationError? {
        let prefs = Preferences.shared
        let language = prefs.primaryLanguage

        switch prefs.appleTechnology {
        case .apple:
            guard EngineChoice.apple.isAvailable(for: language) else {
                return .noSystemEngine(
                    LegacySpeechEngine.unavailabilityReason(for: language)
                        ?? "Le moteur Apple Intelligence n'est pas disponible ici.")
            }
            return SpeechAssets.shared.state(of: language).isReady
                ? nil : .missingLanguageModels([language])
        case .appleLegacy:
            guard EngineChoice.appleLegacy.isAvailable(for: language) else {
                return .noSystemEngine(
                    LegacySpeechEngine.unavailabilityReason(for: language)
                        ?? "La Dictée de macOS n'est pas utilisable ici.")
            }
            return PermissionsMonitor.shared.speechGranted
                ? nil : .speechRecognitionPermissionRequired
        case .crisperWhisper:
            // Impossible par construction : `appleTechnology` ne prend que les
            // deux versions de macOS. On ne bloque pas sur un état qui ne peut
            // pas exister.
            return nil
        }
    }

    var body: some View {
        if isSubCard {
            VStack(alignment: .leading, spacing: 12) { content }
        } else {
            Card(title: "") { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        // Hors sous-carte, la carte porte son propre en-tête : une pastille qui
        // dit si le moteur est opérationnel, le nom de la version active, et ce
        // qu'elle est. En sous-carte, la ligne de choix parente le dit déjà.
        if !isSubCard {
            HStack(alignment: .top, spacing: 12) {
                statusCircle
                VStack(alignment: .leading, spacing: 3) {
                    Text(headerTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(headerDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(Style.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        versionPicker

        switch prefs.appleTechnology {
        case .appleLegacy:
            SpeechAccessRow(explains: !isSubCard)
        default:
            models
        }
    }

    /// La pastille d'état : pleine et cochée quand le moteur peut écrire,
    /// cerclée sinon. `.status-circle` du prototype.
    @ViewBuilder
    private var statusCircle: some View {
        if Self.isValid {
            ZStack {
                Circle().fill(Style.accent).frame(width: 18, height: 18)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Style.onAccent)
            }
        } else {
            Circle()
                .strokeBorder(Style.textTertiary, lineWidth: 1.5)
                .frame(width: 18, height: 18)
        }
    }

    private var headerTitle: String {
        let version = prefs.appleTechnology
        return "macOS · \(version.versionLabel ?? version.label)"
    }

    private var headerDetail: String {
        prefs.appleTechnology == .apple
            ? "Fourni par macOS 26+ (SpeechTranscriber) : modèles neuronaux sur "
                + "puce Apple. Zéro donnée envoyée au cloud, 0 Mo de RAM résidente."
            : "Fourni par macOS (SFSpeechRecognizer) : prêt immédiatement, "
                + "aucune licence ni téléchargement requis."
    }

    // MARK: - La version

    /// Ce que cette machine sait faire, mesuré, dans la langue active.
    private var available: [EngineChoice] {
        EngineChoice.availableSystemEngines(for: prefs.primaryLanguage)
    }

    /// Deux versions : un sélecteur. Une seule : son nom, et rien qui suggère
    /// un choix que cette machine ne peut pas honorer. Aucune : la raison
    /// mesurée et le bouton qui y mène.
    @ViewBuilder
    private var versionPicker: some View {
        if available.count > 1 {
            if !isSubCard {
                Divider().opacity(0.25)
            }
            Text("VERSION DU MOTEUR")
                .font(.system(size: 10, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Style.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Row(label: "Technologie :") {
                PillPicker(options: available.map { ($0, $0.versionLabel ?? $0.label) },
                           selection: Binding(
                               get: { prefs.appleTechnology },
                               set: { prefs.appleTechnology = $0 }))
            }
            if let explanation = prefs.appleTechnology.versionExplanation {
                Note(explanation)
            }
        } else if let only = available.first {
            StatusRow(ok: true, label: only.fullLabel, detail: "seule version ici")
            if let explanation = only.versionExplanation {
                Note(explanation)
            }
        } else {
            Note(LegacySpeechEngine.unavailabilityReason(for: prefs.primaryLanguage)
                 ?? "Aucune version du moteur de macOS n'est utilisable ici.",
                 warning: true)
            ButtonRow {
                Button("Ouvrir Réglages › Clavier") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
            }
        }
    }

    // MARK: - Les modèles d'Apple Intelligence

    private var missing: [Language] {
        prefs.activeLanguages.filter { !assets.state(of: $0.code).isReady }
    }

    private var primaryIsReady: Bool {
        assets.state(of: prefs.primaryLanguage).isReady
    }

    private var models: some View {
        Group {
            if EngineChoice.apple.isAvailable(for: prefs.primaryLanguage) {
                if missing.isEmpty {
                    GrantedLine("Modèles installés (\(prefs.activeLanguages.map(\.name).joined(separator: ", ")))")
                } else if primaryIsReady {
                    // Non bloquant : la langue active est prête, on peut dicter.
                    secondaryOffer
                } else {
                    primaryNeeded
                }
            }
        }
        // Chaque langue vérifiée une fois à l'affichage, et de nouveau quand la
        // liste change. `check` ne télécharge rien : on regarde, on ne décide
        // pas à la place de quelqu'un qui n'a pas encore lu la question.
        .task(id: prefs.selectedLanguages) {
            for code in prefs.selectedLanguages {
                await assets.check(code)
            }
        }
    }

    /// La langue active manque : c'est le seul cas qui empêche de dicter.
    private var primaryNeeded: some View {
        actionBox {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modèle de \(prefs.primary.displayName)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("macOS fournit ce modèle mais ne l'embarque pas : il "
                         + "faut aller le chercher une fois. Environ "
                         + "\(prefs.primary.estimatedSizeLabel).")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                downloadButton(for: [prefs.primary], label: "Télécharger")
            }
            state(of: prefs.primaryLanguage)
        }
    }

    /// Des langues secondaires manquent. Proposé discrètement, sans encart
    /// d'alerte : rien n'est bloqué, et rien ne presse.
    private var secondaryOffer: some View {
        VStack(alignment: .leading, spacing: 6) {
            GrantedLine("Modèle de \(prefs.primary.displayName) prêt")
            HStack(alignment: .top, spacing: 8) {
                Text("\(missing.map(\.name).joined(separator: ", ")) — "
                     + "pas encore installé\(missing.count > 1 ? "s" : ""), "
                     + "environ \(totalLabel(missing)).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                downloadButton(for: missing, label: "Télécharger tout",
                               prominent: false)
            }
            ForEach(missing) { language in
                state(of: language.code)
            }
        }
    }

    /// Le poids cumulé, annoncé pour ce qu'il est : une estimation.
    ///
    /// Apple n'expose la taille d'un actif ni avant ni pendant l'installation.
    /// Afficher « 123 Mo » au point près serait un chiffre qu'on serait
    /// incapable de tenir, sur une opération que les gens surveillent.
    private func totalLabel(_ languages: [Language]) -> String {
        let total = languages.reduce(Int64(0)) { $0 + $1.estimatedModelBytes }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    private func downloadButton(for languages: [Language], label: String,
                                prominent: Bool = true) -> some View {
        let busy = languages.contains { installing.contains($0.code) }

        return Button(busy ? "Téléchargement…" : "\(label) (~\(totalLabel(languages)))") {
            Task {
                let codes = languages.map(\.code)
                installing.formUnion(codes)
                // En série, pas en parallèle : plusieurs installations d'actifs
                // simultanées se gênent, et l'ordre garantit que la langue
                // active — toujours en tête — arrive la première.
                for code in codes { await assets.install(code) }
                installing.subtract(codes)
                // Le repli éventuel se lève dès que le modèle est là.
                LanguageSwitchCoordinator.shared.audit()
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? Style.accent : Color.secondary.opacity(0.35))
        .controlSize(.small)
        .disabled(busy)
    }

    /// L'état d'une langue, quand il a quelque chose à dire.
    @ViewBuilder
    private func state(of code: String) -> some View {
        switch assets.state(of: code) {
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                // Indéterminé, et c'est un correctif : observer
                // `request.progress` fait échouer le téléchargement avec
                // « is not subscribed to transcription.fr ». L'étape est donc
                // nommée à défaut d'être mesurée. Cf. `SpeechAssets`.
                Text("Téléchargement de \(Language.named(code).displayName)…")
                    .font(.system(size: 11))
            }
        case .failed(let message):
            Note(message, warning: true)
            ButtonRow {
                Button("Réessayer") { Task { await assets.install(code) } }
            }
        case .unsupported(let why):
            Note(why, warning: true)
        // `.missing` n'affiche rien ici : l'encart qui englobe cette ligne
        // porte déjà le bouton de téléchargement, et répéter « absent » à côté
        // de « Télécharger » n'ajoute rien.
        case .unknown, .checking, .missing, .ready:
            EmptyView()
        }
    }

    private func actionBox<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
                    .fill(Style.innerBoxFill)
                    .overlay(RoundedRectangle(cornerRadius: Style.innerRadius,
                                              style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)))
    }
}

#Preview("Moteur macOS") {
    ScrollView {
        AppleEngineCard()
            .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: 500)
    .background(Color(hex: 0x141821))
}
