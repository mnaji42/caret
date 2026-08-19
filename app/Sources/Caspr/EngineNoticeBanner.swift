import SwiftUI

/// Ce que la configuration a d'incohérent, dit là où l'on agit.
///
/// ## Un seul service, plusieurs endroits qui l'écoutent
///
/// `LanguageSwitchCoordinator` constate — il ne décide de rien et n'écrit
/// aucune préférence. Sa note se déduit de l'état courant, donc elle est juste
/// à chaque instant sans qu'on ait à penser à la recalculer.
///
/// Restait à la **montrer** partout où l'on peut rendre la configuration
/// incohérente. Elle n'apparaissait que sous le sélecteur de langue : changer
/// de moteur, arrêter le service ou retirer des poids ne produisait donc aucun
/// message, alors que ce sont exactement les gestes qui font basculer la dictée
/// sur autre chose que ce qui est coché.
struct EngineNoticeBanner: View {
    @State private var coordinator = LanguageSwitchCoordinator.shared
    @State private var bootstrap = EngineBootstrap.shared
    @Environment(\.selectSettingsTab) private var selectSettingsTab
    @State private var working = false

    var body: some View {
        if let notice = coordinator.notice {
            content(notice)
        }
        if let confirmation = coordinator.confirmation {
            // Le même cadre que l'avertissement, en turquoise : c'est une
            // bonne nouvelle, mais elle se lit de la même façon. Sans cadre ni
            // marges, elle flottait contre le texte voisin.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                Text(.init(confirmation))
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Style.accent)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
                    .fill(Style.accent.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: Style.innerRadius,
                                              style: .continuous)
                        .strokeBorder(Style.accentBorder, lineWidth: 1)))
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func content(_ notice: LanguageSwitchCoordinator.Notice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                Text(notice.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button { coordinator.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer cette notification")
                .help("Fermer cette notification")
            }
            .foregroundStyle(Style.warning)

            Text(.init(notice.message))
                .font(.system(size: 11.5))
                .foregroundStyle(Style.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            action(notice)
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

    /// Le bouton qui lève la note — quand il y en a un, et qu'il mène quelque
    /// part depuis ici.
    @ViewBuilder
    private func action(_ notice: LanguageSwitchCoordinator.Notice) -> some View {
        if working {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("En cours…").font(.system(size: 11))
            }
        } else if let label = notice.actionLabel {
            switch notice {
            case .modelMissing(let language):
                Button(label) {
                    Task {
                        working = true
                        await coordinator.installMissingModel(for: language)
                        working = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Style.accent)
                .controlSize(.small)

            case .crisperNotRunning(let model):
                Button(label) {
                    Task {
                        working = true
                        await bootstrap.startService(model: model)
                        working = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Style.accent)
                .controlSize(.small)

            // Ces deux-là se règlent dans l'onglet Moteur IA, où vivent le
            // catalogue et la licence. Le bouton se masque quand on y est déjà
            // ou qu'on est hors des Réglages : proposer d'aller là où l'on est
            // ne rendrait service à personne.
            case .crisperUncovered, .crisperWeightsMissing:
                if let goToTab = selectSettingsTab {
                    Button(label) { goToTab(.engine) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

            case .appleVersionSwitched, .noSystemEngine:
                EmptyView()
            }
        }
    }
}
