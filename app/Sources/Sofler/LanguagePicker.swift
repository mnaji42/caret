import SwiftUI

/// Le catalogue des langues, avec recherche et puces de sélection.
///
/// La même vue dans l'accueil (écran 2, déployée) et dans les Réglages (repliée
/// dans un tiroir, cf. `PrimaryLanguageSelector`).
///
/// ## Ce qui est montré, et ce qui est grisé
///
/// Le prototype liste les langues sans distinction. Sur une machine réelle,
/// c'est trompeur : un Mac Intel n'a pas Apple Intelligence, une machine
/// virtuelle n'a aucun modèle système, et la Dictée ne couvre que les langues
/// que macOS a installées. Laisser choisir une langue qu'aucun moteur ne sait
/// transcrire ici, c'est laisser quelqu'un configurer une dictée qui ne dira
/// rien — et le lui apprendre à la première phrase.
///
/// Les langues sont donc **listées toutes**, mais celles qu'aucun moteur ne
/// peut honorer sur cette machine sont grisées et le disent. Les masquer aurait
/// été pire : une liste où l'espagnol n'apparaît pas ne se distingue pas d'une
/// liste où on ne l'a pas trouvé.
///
/// La disponibilité est **mesurée** — `SpeechTranscriber.supportedLocales`,
/// `SFSpeechRecognizer`, la couverture des poids Whisper — jamais déduite d'un
/// numéro de version. Cf. `03_REGLES_SYSTEME_MACOS`.
struct LanguagePicker: View, ValidatingComponent {
    @State private var prefs = Preferences.shared
    @State private var search = ""
    /// Les locales qu'`SpeechTranscriber` propose ici. Vide tant que la mesure
    /// n'est pas revenue, et vide aussi quand ce moteur n'existe pas.
    @State private var systemLocales: Set<String> = []
    @State private var measured = false

    static func validate() -> ComponentValidationError? {
        Preferences.shared.selectedLanguages.isEmpty ? .noLanguageSelected : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            selectedTags
            searchField
            catalog
        }
        // Une seule mesure par affichage : interroger le système à chaque
        // frappe dans la recherche ferait un aller-retour par caractère.
        .task {
            guard !measured else { return }
            systemLocales = Set(await Language.systemSupportedLocales())
            measured = true
        }
    }

    // MARK: - Les langues retenues

    private var selectedTags: some View {
        FlowLayout(spacing: 6) {
            ForEach(prefs.activeLanguages) { language in
                tag(for: language)
            }
        }
    }

    private func tag(for language: Language) -> some View {
        let isPrimary = language.code == prefs.primaryLanguage
        // La dernière langue ne se retire pas : sans langue, aucun moteur ne
        // sait quoi charger. La croix disparaît plutôt que d'échouer au clic.
        let canRemove = prefs.selectedLanguages.count > 1

        return HStack(spacing: 5) {
            Text(language.badge).font(.system(size: 11.5, weight: .medium))
            if isPrimary {
                Text("Principale")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.85)
            }
            if canRemove {
                Button {
                    prefs.selectedLanguages.removeAll { $0 == language.code }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Retirer \(language.displayName)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(isPrimary ? Style.accent : Color.secondary)
        .background(
            Capsule()
                .fill(isPrimary ? Style.accentDim : Color.white.opacity(0.05))
                .overlay(Capsule().strokeBorder(
                    isPrimary ? Style.accentBorder : Color.white.opacity(0.08),
                    lineWidth: 1)))
    }

    // MARK: - Recherche

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Rechercher une langue, un pays, un code…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Style.fieldRadius, style: .continuous)
                .fill(Style.innerBoxFill)
                .overlay(RoundedRectangle(cornerRadius: Style.fieldRadius,
                                          style: .continuous)
                    .strokeBorder(Style.cardStroke, lineWidth: 1)))
    }

    // MARK: - Catalogue

    private var results: [Language] { Language.matching(search) }

    @ViewBuilder
    private var catalog: some View {
        if results.isEmpty {
            Note("Aucune langue ne correspond à « \(search) ».")
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(results) { language in
                        row(for: language)
                        if language.code != results.last?.code {
                            Divider().opacity(0.15)
                        }
                    }
                }
            }
            .frame(height: 190)
            .background(
                RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: Style.innerRadius,
                                              style: .continuous)
                        .strokeBorder(Style.cardStroke, lineWidth: 1)))
        }
    }

    private func row(for language: Language) -> some View {
        let selected = prefs.selectedLanguages.contains(language.code)
        let usable = isUsable(language)

        return HStack(spacing: 8) {
            Text(language.flag).font(.system(size: 13))
            Text(language.name).font(.system(size: 12, weight: .medium))
            if !language.region.isEmpty {
                Text(language.region)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if !usable {
                Text("indisponible ici")
                    .font(.system(size: 10))
                    .foregroundStyle(Style.warning)
            } else if !selected, systemLocales.contains(language.code) {
                // Le poids ne concerne que la version Apple Intelligence, et
                // il est approximatif — Apple n'expose pas la taille d'un
                // actif avant son installation. « environ » n'est pas une
                // précaution de style, c'est la vérité de la mesure.
                Text("~\(language.estimatedSizeLabel)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 13))
                .foregroundStyle(selected ? Style.accent : Color.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .opacity(usable ? 1 : 0.45)
        .background(selected ? Style.accent.opacity(0.06) : .clear)
        .onTapGesture { toggle(language) }
        .help(usable ? "" : indisponibilityReason(language))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(language.displayName)\(selected ? ", retenue" : "")")
    }

    private func toggle(_ language: Language) {
        if prefs.selectedLanguages.contains(language.code) {
            // Refusé plutôt qu'échoué : `Preferences` remettrait le français
            // par défaut, ce qui changerait la langue sous les yeux de
            // quelqu'un qui essayait juste de retirer une entrée.
            guard prefs.selectedLanguages.count > 1 else { return }
            prefs.selectedLanguages.removeAll { $0 == language.code }
        } else {
            prefs.selectedLanguages.append(language.code)
        }
    }

    // MARK: - Ce que cette machine sait faire

    /// Un moteur, au moins un, sait-il transcrire cette langue ici ?
    ///
    /// Trois chances, et il en suffit d'une : le moteur de macOS 26 propose la
    /// locale, la Dictée sait la traiter hors ligne, ou les poids de
    /// CrisperWhisper la couvrent — ces derniers ne dépendant ni de la machine
    /// ni d'un téléchargement par langue.
    private func isUsable(_ language: Language) -> Bool {
        if !measured { return true }
        if systemLocales.contains(language.code) { return true }
        if language.isCoveredByCrisperWhisper { return true }
        return LegacySpeechEngine.isAvailable(for: language.code)
    }

    private func indisponibilityReason(_ language: Language) -> String {
        "Aucun moteur ne transcrit le \(language.displayName) sur cette "
            + "machine : macOS ne propose pas cette locale, la Dictée n'a pas "
            + "ses modèles, et les poids de CrisperWhisper ne la couvrent pas."
    }
}

#Preview("Catalogue de langues") {
    ScrollView {
        Card(title: "Langues de dictée") {
            LanguagePicker()
        }
        .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: Style.windowHeight)
    .background(Color(hex: 0x141821))
}
