import AppKit
import SwiftUI

/// Fenêtre de réglages.
///
/// Sofler est une app d'arrière-plan sans Dock : ouvrir une fenêtre demande de
/// l'activer explicitement, sinon elle apparaît derrière tout le reste.
@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?

    /// L'historique appartient au contrôleur de dictée : on le passe plutôt
    /// que d'en faire un singleton de plus, pour qu'il n'existe qu'un seul
    /// propriétaire de ces données.
    func show(history: TranscriptionHistory) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow.sofler(title: "Réglages de Sofler") {
            PreferencesView(history: history)
        }
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Fenêtre

private struct PreferencesView: View {
    let history: TranscriptionHistory
    @State private var tab: Tab = .general

    /// Six onglets, dans l'ordre où l'on se pose les questions : *ce qui vaut
    /// pour toute l'application*, *comment on déclenche*, *avec quoi ça
    /// transcrit*, puis les trois réserves — mots, historique, corpus.
    enum Tab: String, CaseIterable {
        case general, recording, engine, lexicon, history, collection

        var label: String {
            switch self {
            case .general: "Général"
            case .recording: "Dictée"
            case .engine: "Moteur IA"
            case .lexicon: "Lexique"
            case .history: "Historique"
            case .collection: "Collecte"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case .general: GeneralTab()
                    case .recording: RecordingTab()
                    case .engine: TranscriptionSettings()
                    case .lexicon: VocabularySettings()
                    case .history: HistoryTab(history: history)
                    case .collection: CollectionTab()
                    }
                }
                .padding(.horizontal, Style.windowPadding)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(WindowBackground().ignoresSafeArea())
        .tint(Style.accent)
    }

    /// Les onglets reprennent la forme des pastilles de la barre plutôt que le
    /// `TabView` système, dont la barre d'outils grise casse la continuité.
    ///
    /// **Sans icônes, et c'est mesuré.** Les six libellés font environ 55
    /// caractères ; à 12 pt semi-gras (~6,5 pt par caractère) plus six fois
    /// 24 pt de marges, la barre occupe ~502 pt sur les 520 pt utiles. Ajouter
    /// un symbole par onglet coûte 16 pt chacun et porte le total à ~598 pt :
    /// la barre déborderait de la fenêtre. Les documents de conception
    /// demandaient les deux ; il fallait choisir, et un libellé se lit sans
    /// avoir rien appris là où une icône se devine.
    ///
    /// « Dictée » plutôt qu'« Enregistrement » pour la même raison : c'est le
    /// libellé le plus long, et le raccourcir rend la marge confortable.
    private var tabBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { item in
                    let active = item == tab
                    Text(item.label)
                        .font(.system(size: 12, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Style.accent : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(active ? Style.accent.opacity(0.20) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { tab = item }
                }
            }
            .padding(4)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.06),
                                                    lineWidth: 1)))
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
    }
}

// MARK: - Général

private struct GeneralTab: View {
    var body: some View {
        // La langue d'abord : c'est elle qui décide de ce que les moteurs
        // peuvent faire, et elle vaut pour toute l'application.
        PrimaryLanguageSelector()

        DestinationCard()

        UpdateCard()

        LoginItemCard()
    }
}

// MARK: - Dictée

/// Comment on déclenche, ce qu'on entend pendant, et ce qu'on voit.
///
/// Tout ce qui touche à l'acte de dicter, par opposition à l'onglet Général,
/// qui porte ce qui vaut pour l'application entière.
private struct RecordingTab: View {
    @State private var prefs = Preferences.shared
    @State private var soundsEnabled = Feedback.soundsEnabled

    var body: some View {
        // La même vue que l'accueil, sans la zone d'essai : on ne découvre pas
        // la dictée depuis les Réglages. Les deux écrans posaient la même
        // question avec deux implémentations, et elles avaient déjà divergé.
        TriggerCard(showTrialSandbox: false)

        Card(title: "Aperçu en direct") {
            SettingsToggleRow(
                title: "Afficher le texte reconnu pendant que vous parlez",
                description: "Sous la barre flottante, en italique.",
                note: "Indicatif : le moteur d'aperçu n'a pas votre vocabulaire "
                    + "technique, donc le texte finalement inséré peut différer.",
                isOn: $prefs.livePreviewEnabled,
                isCard: false)

            // Le moteur de l'aperçu n'a de sens à régler que si l'aperçu
            // tourne. L'afficher éteint donnerait un réglage sans effet.
            if prefs.livePreviewEnabled {
                Divider().opacity(0.25)
                AppleEngineCard(isSubCard: true)
            }
        }

        Card(title: "Retours sonores") {
            SettingsToggleRow(
                title: "Sons de début et de fin",
                description: "Deux clics discrets, pour savoir que l'écoute a "
                    + "démarré sans regarder l'écran.",
                isOn: $soundsEnabled,
                isCard: false)
                .onChange(of: soundsEnabled) { _, new in Feedback.soundsEnabled = new }
        }

        MicrophoneModeCard()
    }
}

/// Mode micro de macOS.
///
/// Il n'apparaissait que sur la barre d'enregistrement, ce qui donnait
/// l'impression d'un réglage de Sofler rangé au mauvais endroit. En réalité
/// **aucune application ne peut le changer** : c'est un réglage système,
/// commun à toutes les apps. Le dire ici évite de le chercher.
private struct MicrophoneModeCard: View {
    @State private var mode = AudioRecorder.microphoneModeLabel

    var body: some View {
        Card(title: "Micro") {
            Row(label: "Mode") {
                Text(mode).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Note("**L'isolement de la voix** retire le bruit autour de vous et "
                 + "améliore nettement la transcription en environnement "
                 + "bruyant.")
            Note("macOS ne laisse aucune application imposer ce mode : il vaut "
                 + "pour toutes à la fois, et c'est vous qui le choisissez.")
            // Pas de bouton ici, et c'est mesuré : `showSystemUserInterface`
            // n'ouvre rien tant qu'aucune capture n'est en cours. macOS ne
            // propose ce choix que pendant qu'une application utilise le
            // micro. Le bouton existait, ne faisait rien depuis les réglages,
            // et laissait croire à une panne.
            Note("Le choix ne s'offre que **pendant** qu'une application "
                 + "utilise le micro. Depuis la barre de Sofler, en pleine "
                 + "dictée, un clic sur le mode l'ouvre ; sinon, il est dans "
                 + "le Centre de contrôle, sous « Micro ».")
        }
        // Il change depuis le Centre de contrôle, sans nous prévenir.
        .onAppear { mode = AudioRecorder.microphoneModeLabel }
    }
}

/// Démarrage à l'ouverture de session.
///
/// L'état est relu à chaque affichage plutôt que mémorisé : ce réglage existe
/// aussi dans Réglages Système › Général › Ouverture, et l'utilisateur peut
/// l'y couper sans nous prévenir. Un interrupteur qui afficherait l'inverse de
/// la réalité serait pire que pas d'interrupteur du tout.
private struct LoginItemCard: View {
    @State private var enabled = LoginItem.isEnabled
    @State private var refused = false

    var body: some View {
        Card(title: "Démarrage") {
            SettingsToggleRow(
                title: "Lancer Sofler à l'ouverture de session",
                description: "Disponible dans la barre de menus dès le "
                    + "démarrage de votre Mac.",
                isOn: $enabled, isCard: false)
                .onChange(of: enabled) { _, wanted in
                    let actual = LoginItem.set(wanted)
                    refused = actual != wanted
                    // Recaler l'interrupteur sur ce que le système a vraiment
                    // fait, pas sur ce qu'on lui a demandé.
                    if actual != enabled { enabled = actual }
                }

            if refused, LoginItem.requiresApproval {
                Note("macOS a gardé le refus enregistré dans Réglages Système "
                     + "› Général › Ouverture : c'est là qu'il faut "
                     + "réautoriser Sofler.", warning: true)
                Button("Ouvrir Réglages Système › Ouverture") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
            } else {
                Note("Sofler vit dans la barre de menus : s'il ne tourne pas, "
                     + "la touche de dictée ne fait rien, et rien n'indique "
                     + "que c'est la raison.")
            }
        }
        .onAppear { enabled = LoginItem.isEnabled }
    }
}

// MARK: - Transcription

// MARK: - Collecte

private struct CollectionTab: View {
    @State private var prefs = Preferences.shared
    @State private var stats = Corpus.Statistics()

    /// Le nom du moteur, et son état quand il ne peut rien produire ici.
    private func label(for choice: EngineChoice) -> String {
        choice.isAvailable(for: prefs.language)
            ? choice.fullLabel
            : "\(choice.fullLabel) — indisponible ici"
    }

    var body: some View {
        Card(title: "Collecte") {
            SettingsToggleRow(
                title: "Archiver mes dictées",
                description: "Chaque dictée est conservée localement avec le "
                    + "texte de chaque moteur, produit à partir du même audio.",
                isOn: $prefs.corpusEnabled, isCard: false)
            Note("À chaque dictée, Sofler garde le texte produit par chaque "
                 + "moteur à partir du **même** audio. Ça sert à une seule "
                 + "chose : vous permettre de comparer les moteurs sur votre "
                 + "voix, votre vocabulaire et votre micro, au lieu de vous fier "
                 + "à des mesures faites sur celle de quelqu'un d'autre.\n\n"
                 + "**Tout reste sur votre Mac.** Rien n'est envoyé nulle part, "
                 + "ni à l'auteur de l'application ni à personne — il n'existe "
                 + "aucun serveur pour le recevoir. Vous pouvez ouvrir le "
                 + "dossier, le lire, et l'effacer quand vous voulez.")
        }

        if prefs.corpusEnabled {
            Card(title: "Ce qui est gardé") {
                OptionCheck(title: "Conserver aussi l'audio",
                            isOn: $prefs.corpusKeepsAudio)
                Note("Environ 2 Mo la minute, contre quelques kilo-octets de "
                     + "texte. Sans lui, impossible de réécouter une dictée pour "
                     + "arbitrer un désaccord entre deux moteurs.")

                Divider().opacity(0.25)
                Text("Transcrire aussi avec")
                    .font(.system(size: 12, weight: .medium))
                // `fullLabel`, pas `label` : celui-ci nomme la famille, donc
                // les deux versions de macOS afficheraient ici deux cases
                // rigoureusement identiques. C'est le seul écran où l'on
                // désigne un moteur précis plutôt qu'un fournisseur — on
                // coche « macOS · Dictée » pour comparer les deux versions
                // entre elles.
                ForEach(EngineChoice.allCases, id: \.self) { choice in
                    OptionCheck(title: label(for: choice), isOn: Binding(
                        get: { prefs.corpusEngines.contains(choice) },
                        set: { on in
                            if on { prefs.corpusEngines.insert(choice) }
                            else { prefs.corpusEngines.remove(choice) }
                        }))
                    .disabled(choice == prefs.engine)
                }
                Note("En plus du moteur qui écrit, et **après** insertion : la "
                     + "latence de dictée n'est jamais échangée contre de la "
                     + "collecte. Un moteur non coché n'est jamais chargé.")
                // Listé et non masqué : savoir qu'une version n'existe pas sur
                // cette machine est une information, une ligne absente n'en est
                // pas une. La case reste cochable — elle vaudra le jour où le
                // moteur sera là, et d'ici là rien ne tourne.
                if EngineChoice.allCases.contains(where: {
                    !$0.isAvailable(for: prefs.language)
                }) {
                    Note("Les moteurs marqués indisponibles ne sont pas "
                         + "exécutés et n'apparaissent pas dans le corpus : "
                         + "cochés d'avance, ils reprendront le jour où cette "
                         + "machine saura les faire tourner.")
                }
                if prefs.needsLocalEngine {
                    Label("Le service CrisperWhisper tourne — environ 3 Go en mémoire.",
                          systemImage: "memorychip")
                        .font(.system(size: 11))
                        .foregroundStyle(Style.collecting)
                }
            }

            Card(title: "Corpus") {
                Row(label: "État") {
                    Text(stats.summary).font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                // `stats` partait d'une structure vide que rien ne remplissait
                // : l'onglet annonçait « Corpus vide » quel qu'en soit le
                // contenu — le pire mensonge possible sur un écran dont le
                // seul rôle est de dire ce qui est gardé.
                .onAppear { stats = Corpus.shared.statistics() }
                ButtonRow {
                    Button("Afficher dans le Finder") { Corpus.shared.reveal() }
                    Button("Tout effacer") {
                        Corpus.shared.clear()
                        stats = Corpus.shared.statistics()
                    }
                    .disabled(stats.count == 0)
                }
            }
        }
    }
}

// MARK: - Historique

private struct HistoryTab: View {
    let history: TranscriptionHistory
    @State private var entries: [TranscriptionHistory.Entry] = []
    @State private var justCopied: UUID?

    var body: some View {
        Card(title: "Transcriptions récentes") {
            SettingsToggleRow(
                title: "Conserver l'historique",
                description: "Les dernières transcriptions restent copiables "
                    + "depuis le menu. Le texte seul, jamais l'audio.",
                isOn: Binding(
                    get: { history.isEnabled },
                    set: { history.isEnabled = $0; entries = history.entries }),
                isCard: false)

            if !history.isEnabled {
                Note("Rien n'est écrit. Les transcriptions passées ne sont pas "
                     + "conservées, même localement.")
            } else if entries.isEmpty {
                Note("Aucune pour l'instant")
            } else {
                ForEach(entries) { entry in
                    Divider().opacity(0.25)
                    HStack(spacing: 10) {
                        // Tronqué à une ligne : la fenêtre doit rester lisible
                        // d'un coup d'œil, pas devenir une liste qu'on fait
                        // défiler.
                        Text(entry.preview)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(entry.text)
                        Spacer(minLength: 8)
                        Text(entry.relativeAge)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                            justCopied = entry.id
                        } label: {
                            Image(systemName: justCopied == entry.id
                                  ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(justCopied == entry.id
                                                 ? Style.accent : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Copier le texte entier")
                    }
                }
                Divider().opacity(0.25)
                ButtonRow {
                    Button("Effacer l'historique") {
                        history.clear()
                        entries = []
                    }
                }
            }
            Note("Le texte complet est copié, pas la version tronquée. "
                 + "L'historique reste aussi dans le menu de la barre.")
        }
        .onAppear { entries = history.entries }
    }
}
