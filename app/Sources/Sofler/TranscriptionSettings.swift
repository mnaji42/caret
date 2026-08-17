import SwiftUI

/// Comment Sofler transcrit : la langue, puis le moteur.
///
/// Cette vue ne contient plus rien d'elle-même, et c'est l'aboutissement de ce
/// qu'elle poursuivait déjà. Elle est née de la fusion de deux implémentations
/// — l'accueil et les Réglages posaient les mêmes questions dans deux fichiers
/// distincts, et avaient divergé en silence : le mode et le vocabulaire
/// n'existaient que dans les Réglages, le choix du modèle que dans l'accueil,
/// la langue nulle part dans l'accueil.
///
/// Aucun de ces écarts n'était une décision. Ils sont la conséquence mécanique
/// de deux copies : on ajoute une fonctionnalité là où on travaille, et elle
/// manque ailleurs sans que rien ne le signale.
///
/// Le découpage en composants va au bout de la même idée. Chaque question vit
/// dans une vue autonome qui porte sa propre logique système et sa propre
/// validité, et cette vue-ci n'est plus qu'un ordre de lecture : la langue
/// décide de ce que les moteurs peuvent faire, donc elle vient d'abord.
struct TranscriptionSettings: View {
    var body: some View {
        PrimaryLanguageSelector()
        FinalEngineCard()
    }
}
