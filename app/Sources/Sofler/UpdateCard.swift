import AppKit
import SwiftUI

/// La version installée, et de quoi passer à la suivante.
///
/// Toute la mécanique — interrogation de l'API GitHub, vérification que la
/// nouvelle image porte la **même signature** que la copie en cours, mise en
/// place atomique, levée de la quarantaine, relance — reste dans
/// `UpdateChecker` et `UpdateInstaller`. Ce composant ne fait que la présenter.
///
/// ## La vérification automatique reste désactivée par défaut
///
/// C'est la seule requête réseau que l'application sache faire. Tant qu'elle
/// n'est pas activée, « rien ne sort de votre Mac » n'a aucune exception à
/// énoncer — et une exception, même bénigne, oblige à la mentionner partout et
/// fait douter du reste. Le bouton « Vérifier maintenant », lui, marche
/// toujours : il est déclenché par quelqu'un qui sait ce qu'il demande.
struct UpdateCard: View {
    @State private var prefs = Preferences.shared
    @State private var checker = UpdateChecker.shared
    @State private var installer = UpdateInstaller.shared

    var body: some View {
        Card(title: "Mises à jour") {
            header

            if !UpdateChecker.isReleaseBuild {
                Note("Compilé depuis les sources : `\(UpdateChecker.gitDescribe)`. "
                     + "Les vérifications automatiques sont suspendues sur un "
                     + "build de développement, qui est presque toujours en "
                     + "avance sur la dernière release.")
            }

            if let update = checker.newer {
                available(update)
            }

            Divider().opacity(0.25)

            SettingsToggleRow(
                title: "Rechercher automatiquement, une fois par jour",
                description: "Demande à GitHub le numéro de la dernière version.",
                note: "Désactivé par défaut : tant que vous ne l'activez pas, "
                    + "Sofler ne contacte rien ni personne. Une fois activé, la "
                    + "requête envoie une adresse IP et rien d'autre — aucun "
                    + "identifiant, aucun compteur, jamais ce que vous avez dicté.",
                isOn: $prefs.checksForUpdates,
                isCard: false)
        }
    }

    // MARK: - En-tête

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Text(UpdateChecker.buildLabel)
                .font(.system(size: 13, weight: .medium))

            if checker.newer != nil {
                badge("Mise à jour disponible", color: Style.warning)
            } else if checker.lastCheckedAt != nil, !checker.checking {
                badge("À jour", color: Style.accent)
            }

            Spacer(minLength: 8)

            if checker.checking {
                ProgressView().controlSize(.small)
            } else {
                Button("Vérifier maintenant") {
                    Task { await checker.check() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        if let error = checker.lastError {
            Note(error, warning: true)
        } else if let date = checker.lastCheckedAt, checker.newer == nil {
            Text("Vérifié \(date.formatted(.relative(presentation: .named))).")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: - Une version est disponible

    @ViewBuilder
    private func available(_ update: UpdateChecker.Release) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Version \(update.version)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Style.accent)

            action(update)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
                .fill(Style.accent.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: Style.innerRadius,
                                          style: .continuous)
                    .strokeBorder(Style.accentBorder, lineWidth: 1)))
    }

    /// Chaque étape est nommée pendant qu'elle dure.
    ///
    /// Une barre muette, sur une opération qui remplace l'application qu'on est
    /// en train d'utiliser, invite surtout à cliquer ailleurs pour voir si elle
    /// répond encore.
    @ViewBuilder
    private func action(_ update: UpdateChecker.Release) -> some View {
        switch installer.phase {
        case .idle:
            ready(update)
        case .downloading(let fraction):
            step("Téléchargement… \(Int(fraction * 100)) %") {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Style.accent)
            }
        case .verifying:
            step("Vérification de la signature…")
        case .installing:
            step("Installation…")
        case .relaunching:
            step("Mise à jour posée. Sofler redémarre…")
        case .failed(let message):
            Note(message, warning: true)
            ButtonRow {
                Button("Réessayer") { installer.reset() }
                Button("Ouvrir la page de téléchargement") {
                    NSWorkspace.shared.open(update.page)
                }
            }
        }
    }

    @ViewBuilder
    private func ready(_ update: UpdateChecker.Release) -> some View {
        // L'obstacle est consulté **avant** d'offrir le bouton, jamais après le
        // clic : un dossier non inscriptible ou une copie signée ad hoc ne
        // s'arrangeront pas d'un second essai.
        if let obstacle = UpdateInstaller.obstacle {
            ButtonRow {
                Button("Ouvrir la page de téléchargement") {
                    NSWorkspace.shared.open(update.page)
                }
            }
            Note(obstacle, warning: true)
        } else if update.asset == nil {
            ButtonRow {
                Button("Ouvrir la page de téléchargement") {
                    NSWorkspace.shared.open(update.page)
                }
            }
            Note("Cette release n'attache pas d'image disque : l'installation "
                 + "depuis l'application n'est pas possible pour celle-ci.",
                 warning: true)
        } else {
            HStack(spacing: 8) {
                Button("Mettre à jour vers \(update.version)") {
                    Task { await installer.install(update) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Style.accent)
                .controlSize(.small)

                Button("Voir ce qui change") {
                    NSWorkspace.shared.open(update.page)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Note("Tout se passe ici : le téléchargement, la vérification que la "
                 + "nouvelle version porte bien la même signature que celle-ci, "
                 + "le remplacement et le redémarrage. Vos réglages, votre "
                 + "corpus, le modèle et les autorisations restent en place.")
        }
    }

    @ViewBuilder
    private func step<Extra: View>(
        _ label: String, @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(label).font(.system(size: 12))
            }
            extra()
        }
    }
}

#Preview("Mises à jour") {
    ScrollView {
        UpdateCard()
            .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: 420)
    .background(Color(hex: 0x141821))
}
