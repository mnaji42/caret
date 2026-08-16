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
    @State private var model = EngineInstall.selectedModel
    @State private var step: EngineInstall.Step = .engineMissing
    @State private var working = false
    /// Le service met une dizaine de secondes à charger le modèle. Sans un
    /// mot pendant ce temps, le bouton paraît sans effet et on le reclique.
    @State private var progress: String?

    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            models
            state
            licence
        }
        .onAppear { refresh() }
        .onReceive(ticker) { _ in if !working { refresh() } }
    }

    private func refresh() {
        model = EngineInstall.selectedModel
        step = EngineInstall.step(for: model)
    }

    // MARK: Choix du modèle

    private var models: some View {
        Card(title: "modèle") {
            ForEach(CrisperWhisperModel.allCases, id: \.self) { candidate in
                ModelRow(model: candidate, selected: candidate == model) {
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
                }
                if candidate != CrisperWhisperModel.allCases.last {
                    Divider().opacity(0.2)
                }
            }
        }
    }

    // MARK: L'étape suivante, et elle seule

    @ViewBuilder
    private var state: some View {
        Card(title: "mise en marche") {
            switch step {
            case .engineMissing:
                StatusRow(ok: false, label: "Moteur Python", detail: "pas installé",
                          warningOnly: true)
                Note("CrisperWhisper a besoin de Python, torch et transformers "
                     + "— environ 1,2 Go de bibliothèques. C'est trop pour "
                     + "être embarqué dans l'application, et c'est la seule "
                     + "étape qui demande le Terminal. **Une seule fois** : "
                     + "ensuite tout se pilote d'ici.")
                Note("La commande récupère le code du projet et installe les "
                     + "dépendances. Elle vous demandera d'accepter la licence "
                     + "du modèle avant de télécharger quoi que ce soit.")
                CommandBox(command: EngineInstall.bootstrapCommand)
                Button("Vérifier à nouveau") { refresh() }

            case .modelMissing(let missing):
                StatusRow(ok: false, label: "Poids de \(missing.label)",
                          detail: "à télécharger — \(missing.downloadSize)",
                          warningOnly: true)
                // Le chemin vient du descripteur, jamais d'une supposition :
                // cf. EngineInstall.setupScript.
                if let command = EngineInstall.modelCommand(for: missing) {
                    Note("Le moteur est installé, mais pas ces poids-là. "
                         + "Relancez son script d'installation avec ce "
                         + "modèle :")
                    CommandBox(command: command)
                } else {
                    Note("Le moteur est déclaré installé, mais son script "
                         + "d'installation est introuvable — le dossier a été "
                         + "déplacé ou vidé depuis. Reprenez l'installation "
                         + "depuis le début :", warning: true)
                    CommandBox(command: EngineInstall.bootstrapCommand)
                }
                Button("Vérifier à nouveau") { refresh() }

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

    // MARK: Licence

    private var licence: some View {
        Card(title: "licence") {
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

// MARK: - Pièces

/// Un modèle, ce qu'il coûte, et s'il est déjà là.
private struct ModelRow: View {
    let model: CrisperWhisperModel
    let selected: Bool
    let select: () -> Void

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
                    }
                    Text(model.explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
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
