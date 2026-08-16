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
    /// Le moteur système exige macOS 26. Sur une version antérieure, la ligne
    /// reste visible mais ne se choisit pas : la masquer laisserait croire que
    /// Sofler n'a qu'un moteur, et cacherait la raison.
    var systemEngineAvailable: Bool = true

    @State private var prefs = Preferences.shared
    @State private var lexiconText = ""

    var body: some View {
        Card(title: "Langue") {
            PillPicker(options: Preferences.languages.map { ($0.0, $0.1) },
                       selection: $prefs.language)
            Note("Vaut pour tous les moteurs. Un seul choix à la fois : les "
                 + "modèles imposent une langue par passage, et « automatique » "
                 + "se trompe précisément sur les phrases qui en mêlent deux.")
        }

        Card(title: "Moteur") {
            ChoiceRow(title: EngineChoice.apple.label,
                      subtitle: EngineChoice.apple.explanation,
                      selected: prefs.engine == .apple,
                      hasDetail: !systemEngineAvailable,
                      action: { if systemEngineAvailable { prefs.engine = .apple } }) {
                if !systemEngineAvailable {
                    Note("Indisponible sur cette version de macOS : le moteur "
                         + "intégré s'appuie sur une interface apparue avec "
                         + "macOS 26. CrisperWhisper, lui, fonctionne — c'est "
                         + "l'option ci-dessous.", warning: true)
                }
            }
            .opacity(systemEngineAvailable ? 1 : 0.75)

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
        .task { lexiconText = prefs.lexicon.joined(separator: "\n") }
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

        Subsection("Vocabulaire technique")
        OptionCheck(title: "Utiliser la liste intégrée",
                    isOn: $prefs.useDefaultLexicon)
        if !prefs.useDefaultLexicon {
            TextEditor(text: $lexiconText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.2)))
                .onChange(of: lexiconText) { _, new in
                    prefs.lexicon = new.split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            Note("Un terme par ligne. Gardez la liste courte : plus elle est "
                 + "longue, plus le modèle risque d'y piocher un mot sur un "
                 + "passage où vous n'avez rien dit.")
        }
        Note("Le mode et le vocabulaire n'apparaissent que sous CrisperWhisper "
             + "parce qu'ils n'existent que là : le moteur de macOS n'a qu'un "
             + "rendu, et mesuré sur de vrais enregistrements, lui fournir un "
             + "vocabulaire ne change pas sa sortie d'un caractère.")
    }
}
