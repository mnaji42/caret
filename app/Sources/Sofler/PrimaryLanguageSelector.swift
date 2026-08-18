import SwiftUI

/// La bascule de langue principale, dans les Réglages.
///
/// ## Pourquoi la forme change avec le nombre de langues
///
/// Les pastilles sont le meilleur contrôle pour deux options : la bascule coûte
/// un clic et les deux choix restent lisibles côte à côte. À partir de trois,
/// elles débordent des 520 pt utiles ou s'écrasent — et un contrôle qui change
/// de taille selon son contenu fait sauter la hauteur de la carte à chaque
/// ajout de langue.
///
/// Au-delà de deux, on passe donc à un menu déroulant : hauteur constante,
/// aucun débordement possible, et c'est le contrôle que macOS emploie lui-même
/// pour ce genre de choix.
///
/// Le catalogue complet, lui, reste replié. Quelqu'un vient ici pour **changer
/// de langue**, pas pour reconfigurer sa liste : déplier 39 entrées par défaut
/// pousserait tout le reste de l'onglet hors de l'écran.
struct PrimaryLanguageSelector: View {
    @State private var prefs = Preferences.shared
    @State private var coordinator = LanguageSwitchCoordinator.shared
    @State private var showsCatalog = false
    @State private var installing = false

    /// Le seuil au-delà duquel les pastilles ne tiennent plus.
    private static let pillLimit = 2

    var body: some View {
        Card(title: "Langue de dictée") {
            if prefs.selectedLanguages.count <= Self.pillLimit {
                PillPicker(options: prefs.activeLanguages.map { ($0.code, $0.badge) },
                           selection: $prefs.primaryLanguage)
            } else {
                Row(label: "Langue active") {
                    Picker("", selection: $prefs.primaryLanguage) {
                        ForEach(prefs.activeLanguages) { language in
                            Text(language.badge).tag(language.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            }

            // Ce qui a été replié d'autorité, dit à l'endroit où on vient de
            // changer de langue — pas dans un journal, et pas silencieusement.
            if let notice = coordinator.notice {
                fallbackBanner(notice)
            }
            if let confirmation = coordinator.confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Style.accent)
                    .transition(.opacity)
            }

            // La note d'abord, le bouton ensuite : elle explique l'état, il
            // propose l'action. Les intervertir ferait lire la conséquence
            // avant la cause.
            if !showsCatalog {
                Note(prefs.selectedLanguages.count > 1
                     ? "\(prefs.selectedLanguages.count) langues configurées. La "
                       + "première est celle avec laquelle Sofler dicte ; les "
                       + "autres attendent d'être activées ici."
                     : "La langue principale pilote la reconnaissance vocale.")
            }

            Divider().opacity(0.25)

            catalogueToggle

            if showsCatalog {
                LanguagePicker()
            }
        }
        .animation(.easeOut(duration: 0.2), value: coordinator.confirmation)
        .onAppear { coordinator.audit() }
    }

    /// Le bouton qui déplie le catalogue — **toute la ligne**, pas le chevron.
    ///
    /// C'était un `DisclosureGroup`, et c'était un piège : sous macOS, seul le
    /// petit triangle réagit au clic. On vise « Gérer / ajouter des langues… »,
    /// il ne se passe rien, et on en conclut que le bouton est cassé. Le
    /// prototype a la même faiblesse — son libellé est du texte à côté d'un
    /// bouton — mais l'avoir dans les deux ne la rend pas acceptable.
    ///
    /// Une seule cible, large de toute la carte : impossible de la manquer, et
    /// le survol montre où elle commence et où elle finit.
    private var catalogueToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { showsCatalog.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                Text(showsCatalog ? "Masquer le catalogue"
                                  : "Gérer / ajouter des langues…")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(showsCatalog ? 90 : 0))
            }
            .foregroundStyle(Style.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // Sans ça, seuls les pixels du texte et de l'icône seraient
            // cliquables, et le vide entre les deux ne le serait pas.
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .accessibilityLabel(showsCatalog ? "Masquer le catalogue de langues"
                                         : "Gérer ou ajouter des langues")
        .accessibilityAddTraits(showsCatalog ? [.isSelected, .isButton] : .isButton)
    }

    /// Le bandeau de repli, avec l'action qui le lève quand il y en a une.
    @ViewBuilder
    private func fallbackBanner(_ notice: LanguageSwitchCoordinator.Notice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(notice.message, systemImage: "info.circle.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(Style.warning)
                .fixedSize(horizontal: false, vertical: true)

            // Zéro saut de contexte : le modèle manquant se télécharge d'ici,
            // plutôt que d'envoyer chercher le bouton dans un autre onglet.
            if case .modelMissing(let language) = notice {
                if installing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        // Indéterminé, et c'est un correctif, pas un renoncement :
                        // observer `request.progress` fait échouer le
                        // téléchargement. Cf. SpeechAssets.
                        Text("Téléchargement de \(Language.named(language).displayName)…")
                            .font(.system(size: 11))
                    }
                } else if let action = notice.actionLabel {
                    Button(action) {
                        Task {
                            installing = true
                            await coordinator.installMissingModel(for: language)
                            installing = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Style.accent)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
                .fill(Style.warning.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: Style.innerRadius,
                                          style: .continuous)
                    .strokeBorder(Style.warning.opacity(0.30), lineWidth: 1)))
    }
}

#Preview("Langue principale") {
    ScrollView {
        PrimaryLanguageSelector()
            .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: Style.windowHeight)
    .background(Color(hex: 0x141821))
}
