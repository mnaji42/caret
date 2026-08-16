import AppKit
import SwiftUI

/// Comment Sofler transcrit : la langue, le moteur, et tout ce qui en dépend.
///
/// Une seule vue, utilisée par l'accueil **et** par les Réglages. Elles
/// posaient les mêmes questions avec deux implémentations distinctes, et elles
/// avaient divergé — silencieusement, comme toujours dans ce cas :
///
/// - le **mode** (mot à mot / texte nettoyé) et le **vocabulaire** n'existaient
///   que dans les Réglages, alors que ce sont précisément les deux choses
///   qu'on veut essayer en découvrant CrisperWhisper ;
/// - le choix du **modèle** et son installation n'existaient que dans
///   l'accueil, si bien qu'on ne pouvait pas changer de modèle depuis les
///   Réglages ;
/// - la **langue** n'était nulle part dans l'accueil, alors qu'elle vaut pour
///   tous les moteurs et conditionne le premier essai ;
/// - et les Réglages conseillaient encore de lancer `scripts/setup.sh`, un
///   script que personne installant depuis l'image disque ne possède.
///
/// Aucun de ces écarts n'était une décision. Ils sont la conséquence mécanique
/// de deux copies : on ajoute une fonctionnalité là où on travaille, et elle
/// manque ailleurs sans que rien ne le signale. D'où cette vue-ci.
///
/// L'organisation suit la façon dont on lit : une question par bloc, et ce qui
/// dépend d'un choix vit **à l'intérieur** de ce choix. Le modèle,
/// l'installation et la licence appartiennent à CrisperWhisper ; les afficher
/// en cartes séparées faisait lire quatre réglages indépendants là où il n'y
/// en a qu'un, et laissait le choix du modèle en évidence même quand le moteur
/// retenu était celui de macOS.
struct TranscriptionSettings: View {
    @State private var prefs = Preferences.shared

    var body: some View {
        Card(title: "Langue") {
            PillPicker(options: Preferences.languages.map { ($0.0, $0.1) },
                       selection: $prefs.language)
            Note("Vaut pour tous les moteurs. Un seul choix à la fois : les "
                 + "modèles imposent une langue par passage, et « automatique » "
                 + "se trompe précisément sur les phrases qui en mêlent deux.")

            // Changer de langue, c'est retomber dans le cas de la machine
            // neuve : le modèle de macOS est fourni par locale, et celui de la
            // langue qu'on vient de choisir n'est pas forcément là. La même
            // ligne que l'accueil le dit et propose de le récupérer, plutôt
            // que de laisser découvrir le manque à la première dictée.
            // Le modèle par langue ne concerne que la version Apple
            // Intelligence : celle de la Dictée s'appuie sur les actifs du
            // système, qui sont là dès que la dictée fonctionne.
            if EngineChoice.apple.isAvailable(for: prefs.language) {
                Divider().opacity(0.25)
                SpeechModelRow(language: prefs.language,
                               label: Preferences.languages
                                   .first { $0.0 == prefs.language }?.1
                                   ?? prefs.language)
                    .id(prefs.language)
            }
        }

        Card(title: "Moteur") {
            // Une seule ligne pour macOS, quel que soit le nombre de versions
            // qu'il fournit. Elles étaient présentées comme deux moteurs de
            // même rang à côté de CrisperWhisper, ce qui faisait lire trois
            // décisions indépendantes : en réalité on choisit un fournisseur,
            // puis éventuellement une version — exactement comme on choisit
            // CrisperWhisper, puis son modèle.
            ChoiceRow(title: systemTitle,
                      subtitle: EngineChoice.apple.explanation,
                      selected: prefs.engine.isSystem,
                      hasDetail: showsSystemDetail,
                      action: selectSystem) {
                systemVersions
            }

            ChoiceRow(title: crisperTitle,
                      subtitle: EngineChoice.crisperWhisper.explanation,
                      selected: prefs.engine == .crisperWhisper,
                      hasDetail: showsCrisperDetail,
                      action: { prefs.engine = .crisperWhisper }) {
                crisperWhisper
            }

            Note("Rien de tout ça n'est définitif : le moteur se change à tout "
                 + "moment, ici ou depuis les Réglages, et Sofler arrête le "
                 + "service dès que vous repassez à macOS.")
        }
    }

    // MARK: - Les versions de macOS

    /// Ce que cette machine sait faire, à cet instant et dans cette langue.
    ///
    /// Mesuré, jamais déduit d'un numéro de version : une machine sans Apple
    /// Intelligence dicte très bien avec la Dictée, et un Mac Intel n'a que
    /// celle-là. Proposer une version incapable d'écrire une ligne était le
    /// plus sûr moyen de faire croire l'application cassée.
    private var availableSystemEngines: [EngineChoice] {
        EngineChoice.availableSystemEngines(for: prefs.language)
    }

    /// La version en vigueur : celle qui est réglée si elle marche ici, sinon
    /// celle que cette machine emploierait.
    private var systemVersion: EngineChoice? {
        EngineChoice.systemEngine(preferring: prefs.engine, for: prefs.language)
    }

    /// Le titre ne nomme la version que lorsqu'il n'y a pas de sélecteur pour
    /// le faire — sinon les deux diraient la même chose à dix pixels d'écart.
    private var systemTitle: String {
        guard availableSystemEngines.count == 1,
              let only = availableSystemEngines.first else {
            return EngineChoice.apple.label
        }
        return only.fullLabel
    }

    /// Deux versions : un sélecteur. Une seule : rien, la ligne se suffit et
    /// n'a pas à suggérer un choix qui n'existe pas sur cette machine. Aucune :
    /// la raison mesurée et le bouton qui y mène — c'est le seul cas où la
    /// ligne s'ouvre sans qu'on ait rien à y régler.
    private var showsSystemDetail: Bool { availableSystemEngines.count != 1 }

    /// Choisir « macOS », c'est retenir la version qui marche ici.
    ///
    /// Sans version utilisable, le clic ne fait rien : la ligne reste lisible
    /// et porte son explication, mais sélectionner un moteur incapable
    /// d'écrire ne rendrait service à personne.
    private func selectSystem() {
        guard let systemVersion else { return }
        prefs.engine = systemVersion
    }

    /// Les deux cas que `showsSystemDetail` laisse passer, et rien d'autre :
    /// plusieurs versions — il y a un choix à offrir — ou aucune — il y a une
    /// raison à donner. Avec exactement une version, ce bloc reste vide, et
    /// c'est tout l'objet du regroupement : rien n'y suggère un choix que cette
    /// machine ne peut pas honorer.
    @ViewBuilder
    private var systemVersions: some View {
        let versions = availableSystemEngines
        if versions.count > 1, let current = systemVersion {
            Subsection("Version")
            PillPicker(options: versions.map { ($0, $0.versionLabel ?? $0.label) },
                       selection: Binding(get: { current },
                                          set: { prefs.engine = $0 }))
            if let explanation = current.versionExplanation {
                Note(explanation)
            }
            Note("Les deux transcrivent sur votre Mac et n'ont qu'un seul "
                 + "rendu. Vous pouvez les comparer sur la même phrase, et "
                 + "archiver les deux depuis l'onglet Collecte.")
        } else if versions.isEmpty {
            Note(LegacySpeechEngine.unavailabilityReason(for: prefs.language)
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

    // MARK: - Ce qui n'existe que sous CrisperWhisper

    /// Le modèle qui servirait si l'on dictait maintenant, ou `nil` si rien
    /// n'est téléchargé. Plusieurs modèles peuvent coexister : c'est celui que
    /// le descripteur désigne qui compte, pas le premier trouvé.
    private var installedModel: CrisperWhisperModel? {
        let active = EngineInstall.selectedModel
        return active.isDownloaded ? active : CrisperWhisperModel.downloaded.first
    }

    /// Le nom du moteur porte celui du modèle dès qu'il y en a un.
    ///
    /// C'est l'information qu'on cherche une fois installé — « lequel tourne
    /// en ce moment » — et la mettre dans le titre permet de replier tout le
    /// reste sans rien perdre.
    private var crisperTitle: String {
        guard let installed = installedModel else {
            return EngineChoice.crisperWhisper.label
        }
        return "\(EngineChoice.crisperWhisper.label) · \(installed.label)"
    }

    /// Trois situations, et elles suffisent.
    ///
    /// Rien d'installé et le moteur n'est pas retenu : la ligne se lit seule,
    /// il n'y a rien à régler sur quelque chose qu'on n'a pas choisi. Rien
    /// d'installé mais le moteur vient d'être retenu : tout s'ouvre, c'est une
    /// installation. Un modèle en place : le rendu reste visible, le reste se
    /// replie derrière « Changer de modèle » — la liste des quatre modèles, la
    /// licence et le bloc de retrait répondaient à une question qu'on ne se
    /// pose plus, en occupant la moitié de la fenêtre.
    private var showsCrisperDetail: Bool {
        installedModel != nil || prefs.engine == .crisperWhisper
    }

    @ViewBuilder
    private var crisperWhisper: some View {
        Subsection("Rendu")
        Row(label: "Mode par défaut") {
            PillPicker(options: [(TranscriptionMode.intended, "Texte nettoyé"),
                                 (TranscriptionMode.verbatim, "Mot à mot")],
                       selection: $prefs.defaultMode)
        }
        Note("« Nettoyé » retire les hésitations et les répétitions ; « mot à "
             + "mot » garde tout, y compris les « euh ». Le choix se change "
             + "aussi en cours de dictée, depuis la barre flottante — essayez "
             + "les deux sur la même phrase.")

        // Modèle, installation et licence : la vue qui interroge l'état réel.
        // Repliée dès qu'un modèle est là — elle rouvre sur demande.
        CrisperWhisperSetup(
            presentation: installedModel == nil ? .full : .compact,
            isActiveEngine: prefs.engine == .crisperWhisper)

        Note("Le mode n'apparaît que sous CrisperWhisper parce qu'il "
             + "n'existe que là : le moteur de macOS n'a qu'un rendu. Votre "
             + "vocabulaire, lui, a son propre onglet — il ne dépend d'aucun "
             + "moteur.")
    }
}
