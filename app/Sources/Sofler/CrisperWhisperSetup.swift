import AppKit
import SwiftUI

/// Mettre CrisperWhisper en marche, sans quitter l'application plus d'une fois.
///
/// L'accueil disait « l'installation passe par le Terminal », et s'arrêtait
/// là. C'est vrai d'une étape sur quatre — Python et ses bibliothèques ne
/// peuvent ni s'embarquer ni se télécharger depuis un bundle de deux
/// mégaoctets — mais faux des trois autres, qui ne demandent qu'un bouton.
/// Résultat : quelqu'un dont le modèle était déjà téléchargé se voyait dire de
/// tout réinstaller.
///
/// Cette vue interroge l'état réel et ne montre que l'action suivante. Elle
/// vit dans l'accueil, à côté du champ d'essai, pour qu'on puisse dicter dans
/// la foulée et entendre la différence — proposer un moteur sans permettre de
/// l'essayer ne sert à rien.
struct CrisperWhisperSetup: View {
    /// Combien montrer.
    ///
    /// Tout n'a d'intérêt qu'au moment de l'installation. Une fois un modèle
    /// en place, la liste des quatre modèles, la licence et le bloc de retrait
    /// occupent la moitié de la fenêtre pour répondre à une question qu'on ne
    /// se pose plus — et repoussent le champ d'essai hors de l'écran.
    enum Presentation { case full, compact }

    var presentation: Presentation = .full

    /// Ouvert à la demande, depuis « Changer de modèle ». L'état vit ici et
    /// non chez l'appelant : c'est cette vue qui sait ce qu'elle replie.
    @State private var expanded = false
    @State private var model = EngineInstall.selectedModel
    @State private var step: EngineInstall.Step = .engineMissing
    @State private var working = false
    /// Le service met une dizaine de secondes à charger le modèle. Sans un
    /// mot pendant ce temps, le bouton paraît sans effet et on le reclique.
    @State private var progress: String?
    /// Le modèle dont on vient de demander le retrait. Une confirmation
    /// s'impose : c'est un giga et demi, et si c'est le modèle actif la
    /// dictée bascule sur macOS — deux conséquences qu'un clic ne devrait pas
    /// déclencher sans le dire.
    @State private var pendingRemoval: CrisperWhisperModel?

    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// Rendu sans carte, pour tenir à l'intérieur du bloc CrisperWhisper.
    ///
    /// La vue posait trois `Card` empilées — modèle, mise en marche, licence —
    /// ce qui les détachait du moteur auquel elles appartiennent : on lisait
    /// quatre réglages indépendants là où il n'y en a qu'un, et le choix du
    /// modèle restait visible en gros même quand le moteur retenu était celui
    /// de macOS.
    private var showsEverything: Bool { presentation == .full || expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsEverything {
                Subsection("Modèle")
                models
                Subsection("Mise en marche")
                state
                Subsection("Licence")
                licence
                Subsection("Retirer")
                removal
            } else {
                // Replié, mais jamais muet sur un problème : si le service
                // n'est pas prêt, le cacher laisserait quelqu'un dicter dans
                // le vide sans rien pour comprendre. Prêt, l'état n'apprend
                // rien que le titre ne dise déjà.
                if step != .ready { state }
                ButtonRow {
                    Button("Changer de modèle") { expanded = true }
                }
            }
        }
        .onAppear { refresh() }
        // Pas pendant une installation : l'état bascule d'étape en étape au
        // fur et à mesure — l'environnement apparaît, puis les poids — et
        // rafraîchir remplacerait la vue qui affiche l'avancement par celle de
        // l'étape suivante, à mi-parcours.
        .onReceive(ticker) { _ in
            if !working, !EngineBootstrap.shared.isBusy { refresh() }
        }
    }

    private func refresh() {
        model = EngineInstall.selectedModel
        step = EngineInstall.step(for: model)
    }

    // MARK: Choix du modèle

    private var models: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(CrisperWhisperModel.allCases, id: \.self) { candidate in
                ModelRow(model: candidate, selected: candidate == model, select: {
                    model = candidate
                    // Écrit tout de suite, et redémarre le service s'il
                    // tourne : le choix doit pouvoir s'essayer dans la
                    // seconde, pas à la prochaine ouverture.
                    working = true
                    progress = "changement de modèle…"
                    Task {
                        EngineInstall.select(model: candidate)
                        working = false
                        progress = nil
                        refresh()
                    }
                }, remove: { pendingRemoval = candidate })
                if candidate != CrisperWhisperModel.allCases.last {
                    Divider().opacity(0.2)
                }
            }
        }
    }

    // MARK: L'étape suivante, et elle seule

    @ViewBuilder
    private var state: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch step {
            case .engineMissing:
                StatusRow(ok: false, label: "Moteur Python", detail: "pas installé",
                          warningOnly: true)
                Installer(model: model, weightsOnly: false, onFinish: refresh)

            case .modelMissing(let missing):
                StatusRow(ok: false, label: "Poids de \(missing.label)",
                          detail: "à télécharger — \(missing.downloadSize)",
                          warningOnly: true)
                Installer(model: missing, weightsOnly: true, onFinish: refresh)

            case .serviceMissing:
                StatusRow(ok: false, label: "Service", detail: "pas encore en place",
                          warningOnly: true)
                Note("Tout est téléchargé. Il reste à lancer le service qui "
                     + "garde le modèle en mémoire — c'est ce qui rend la "
                     + "transcription rapide, et ça occupe "
                     + "\(model.residentMemory) tant qu'il tourne.")
                action("Installer et démarrer le service") {
                    EngineInstall.installService(model: model)
                }

            case .serviceStopped:
                StatusRow(ok: false, label: "Service", detail: "arrêté",
                          warningOnly: true)
                action("Démarrer le service") {
                    EngineInstall.installService(model: model)
                }

            // Lancé, mais pas encore utilisable. Sans cet état, la carte
            // affichait « Prêt » pendant que le service lisait ses 1,6 Go, et
            // la dictée tentée à ce moment-là ne rendait rien.
            case .serviceStarting:
                StatusRow(ok: false, label: "Chargement",
                          detail: "modèle en cours de lecture",
                          warningOnly: true)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Le service lit les \(model.downloadSize) du modèle.")
                        .font(.system(size: 12))
                }
                Note("Jusqu'à une minute au premier démarrage, quelques "
                     + "secondes ensuite. **Dicter avec CrisperWhisper avant "
                     + "la fin de cette étape ne rendra rien** — le moteur de "
                     + "macOS, lui, reste disponible tout de suite.")

            case .ready:
                StatusRow(ok: true, label: "Prêt",
                          detail: "\(model.label) chargé · \(model.residentMemory)")
                Note("Essayez dans le cadre ci-dessous : dictez la même phrase "
                     + "avec chaque moteur et comparez ce qui s'écrit.")
            }

            if let progress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Un bouton qui travaille, et qui le dit. Le chargement du modèle prend
    /// une dizaine de secondes ; un bouton muet pendant ce temps se reclique.
    private func action(_ title: String, _ work: @escaping () -> Void) -> some View {
        Button(title) {
            working = true
            progress = "démarrage du service, chargement du modèle…"
            Task {
                work()
                // Le service répond dès que le socket existe, pas dès que
                // launchctl rend la main.
                for _ in 0..<30 {
                    try? await Task.sleep(for: .seconds(1))
                    if EngineService.isRunning { break }
                }
                working = false
                progress = nil
                refresh()
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Style.accent)
        .disabled(working)
    }

    // MARK: Retrait

    @ViewBuilder
    private var removal: some View {
        if let doomed = pendingRemoval {
            Note("Retirer les poids de **\(doomed.label)** libère "
                 + "\(doomed.downloadSize)."
                 + (doomed == model && Preferences.shared.engine == .crisperWhisper
                    ? " C'est le modèle en cours : le service s'arrête et la "
                      + "dictée repasse au moteur de macOS."
                    : "")
                 + " Les poids partent à la corbeille.", warning: true)
            ButtonRow {
                Button("Retirer \(doomed.label)") {
                    EngineInstall.remove(model: doomed)
                    pendingRemoval = nil
                    refresh()
                }
                Button("Annuler") { pendingRemoval = nil }
            }
        } else {
            Note("Chaque modèle se retire séparément, avec le bouton de sa "
                 + "ligne. Pour retirer CrisperWhisper en entier — les poids, "
                 + "le service et l'environnement Python — passez par la "
                 + "fenêtre dédiée : elle ne propose que ce qui le concerne, "
                 + "et laisse Sofler installé.")
            ButtonRow {
                Button("Retirer CrisperWhisper…") {
                    UninstallWindowController.shared.show(scope: .crisperWhisper)
                }
            }
        }
    }

    // MARK: Licence

    private var licence: some View {
        VStack(alignment: .leading, spacing: 10) {
            Note("Les poids sont distribués par Nyra Health sous une licence "
                 + "de **recherche non commerciale** — sous une lecture "
                 + "stricte, dicter un courriel professionnel peut déjà en "
                 + "relever. Le code de Sofler, lui, est libre.")
            Button("Lire la licence") {
                NSWorkspace.shared.open(URL(string:
                    "https://huggingface.co/\(model.identifier)/blob/main/LICENSE.md")!)
            }
        }
    }
}

/// Le bouton qui installe tout, et ce qu'il devient pendant qu'il travaille.
///
/// Il remplace une commande à coller dans un terminal. Ce n'était pas
/// seulement inélégant : la commande cassait au deuxième essai, elle nommait
/// un chemin différent sur chaque machine, et elle posait la question de la
/// licence dans une invite où la touche Entrée répondait non.
///
/// Chaque étape est nommée pendant qu'elle dure, et les longues portent une
/// barre. L'installation prend plusieurs minutes et descend près de trois
/// gigaoctets : un bouton muet pendant ce temps se reclique, puis se maudit.
private struct Installer: View {
    let model: CrisperWhisperModel
    /// Le moteur est déjà là et seuls les poids manquent. La phrase à dire
    /// n'est alors pas la même, et le volume annoncé non plus.
    let weightsOnly: Bool
    let onFinish: () -> Void

    @State private var bootstrap = EngineBootstrap.shared
    @State private var licenceAccepted = false

    var body: some View {
        switch bootstrap.phase {
        case .idle:
            ready

        case .fetchingTool(let fraction):
            step("Récupération de uv, le gestionnaire d'environnements Python",
                 fraction: fraction)

        case .preparing(let detail):
            step(detail)

        case .installingDependencies(let line):
            step("Installation des bibliothèques — environ 1,2 Go",
                 caption: line)

        case .downloadingModel(let fraction):
            step("Téléchargement des poids de \(model.label) — \(model.downloadSize)",
                 fraction: fraction)

        case .startingService(let seconds):
            step("Chargement du modèle en mémoire"
                 + (seconds > 2 ? " — \(seconds) s" : ""),
                 caption: "jusqu'à une minute au premier démarrage")

        case .done:
            StatusRow(ok: true, label: "Installé", detail: "\(model.label) prêt")
                .onAppear {
                    bootstrap.reset()
                    onFinish()
                }

        case .failed(let message):
            Note(message, warning: true)
            ButtonRow {
                Button("Réessayer") { bootstrap.reset() }
            }
            // L'échappatoire reste offerte. Si l'installation intégrée bute
            // sur quelque chose qu'on n'a pas prévu, il vaut mieux une
            // commande que rien du tout.
            Note("Si le problème persiste, l'installation manuelle reste "
                 + "possible depuis un terminal :")
            CommandBox(command: EngineInstall.bootstrap.command)
        }
    }

    @ViewBuilder
    private var ready: some View {
        if let obstacle = EngineBootstrap.obstacle {
            Note(obstacle, warning: true)
        } else {
            Note(weightsOnly
                 ? "Le moteur est en place, il manque les poids de "
                   + "\(model.label) — \(model.downloadSize) à télécharger."
                 : "CrisperWhisper a besoin de Python et de ses bibliothèques "
                   + "— environ 1,2 Go — puis des poids du modèle, "
                   + "\(model.downloadSize). **Tout s'installe d'ici**, dans "
                   + "le dossier de Sofler : ni Homebrew, ni le Python de "
                   + "votre système, ni quoi que ce soit hors de ce dossier "
                   + "n'est touché.")

            // La licence se coche, elle ne se devine pas. L'invite du script
            // demandait « [o/N] » : appuyer sur Entrée refusait, et
            // l'installation s'arrêtait sans que la raison soit claire.
            OptionCheck(title: "J'accepte la licence de recherche non "
                        + "commerciale des poids", isOn: $licenceAccepted)

            HStack(spacing: 8) {
                Button(weightsOnly ? "Télécharger les poids"
                                   : "Installer CrisperWhisper") {
                    Task {
                        await bootstrap.install(model: model,
                                                licenceAccepted: licenceAccepted)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Style.accent)
                .disabled(!licenceAccepted)

                Button("Lire la licence") {
                    NSWorkspace.shared.open(URL(string:
                        "https://huggingface.co/\(model.identifier)/blob/main/LICENSE.md")!)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }

    /// Une étape en cours : ce qu'elle fait, et où elle en est quand c'est
    /// mesurable.
    @ViewBuilder
    private func step(_ label: String, fraction: Double? = nil,
                      caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if fraction == nil { ProgressView().controlSize(.small) }
                Text(fraction.map { "\(label) — \(Int($0 * 100)) %" } ?? label)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Style.accent)
            }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Annuler") { bootstrap.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Pièces

/// Un modèle, ce qu'il coûte, et s'il est déjà là.
private struct ModelRow: View {
    let model: CrisperWhisperModel
    let selected: Bool
    let select: () -> Void
    /// `nil` quand le modèle n'est pas sur le disque : proposer de retirer ce
    /// qui n'existe pas est un bouton qui ne peut rien faire.
    var remove: (() -> Void)?

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Style.accent : Color.secondary)
                    .font(.system(size: 13))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.label).font(.system(size: 12, weight: .medium))
                        if model.isRecommended {
                            Text("recommandé")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Style.accent.opacity(0.22)))
                        }
                        // Ce qui décide vraiment : est-ce déjà sur le disque ?
                        Text(model.isDownloaded
                             ? "déjà téléchargé"
                             : "\(model.downloadSize) à télécharger")
                            .font(.system(size: 10))
                            .foregroundStyle(model.isDownloaded ? Style.accent : .secondary)
                        // La mémoire vive à côté du poids sur disque, avant le
                        // téléchargement et non après. C'est le coût le plus
                        // sensible des deux — un gigaoctet de disque ne se
                        // remarque pas, trois de mémoire si — et il
                        // n'apparaissait qu'une fois le modèle installé.
                        Text("· \(model.residentMemory) en mémoire")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text(model.explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let remove, model.isDownloaded {
                    Button("Retirer", action: remove)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Une commande à coller, lisible et copiable.
///
/// Affichée en clair plutôt que cachée derrière un bouton « installer » :
/// celle-ci récupère du code et installe plus d'un gigaoctet de dépendances,
/// et personne ne devrait exécuter ça sans pouvoir le lire.
private struct CommandBox: View {
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.22)))
            Button(copied ? "Copié" : "Copier la commande") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            }
        }
    }
}
