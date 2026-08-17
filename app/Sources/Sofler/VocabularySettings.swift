import SwiftUI

/// Les mots que vous employez, et que les moteurs ne connaissent pas.
///
/// Cette liste vivait sous CrisperWhisper, ce qui était doublement faux. Elle
/// n'est pas un réglage de moteur : c'est **votre** vocabulaire. Il survit à un
/// changement de modèle, à un changement de moteur, et aux moteurs qui
/// n'existent pas encore. Et rangée là, elle restait invisible à quiconque
/// dicte avec macOS — donc personne ne la construisait avant d'en avoir
/// besoin, alors que c'est précisément un objet qui s'enrichit peu à peu, au
/// fil des mots qu'on voit mal transcrits.
///
/// Ce qui reste vrai, et qui est dit plutôt que tu : sur les enregistrements
/// de ce projet, fournir un lexique au moteur de macOS ne change pas sa sortie
/// d'un caractère. La liste est donc partagée mais pas universellement
/// utilisée, et l'interface l'annonce au lieu de le promettre.
struct VocabularySettings: View {
    @State private var prefs = Preferences.shared
    @State private var newTerm = ""

    /// Au-delà, on ne gagne plus rien : le lexique part dans le prompt du
    /// modèle, et un prompt long dilue le contexte au lieu de le préciser.
    /// C'est la règle que le code appliquait en silence — « retirer un terme
    /// pour en ajouter un » — et qu'aucune interface ne montrait.
    private var crowded: Bool { prefs.lexicon.count > Preferences.starterLexicon.count }

    var body: some View {
        Card(title: "Vocabulaire") {
            Note("Les mots que vous employez et qu'un modèle de français "
                 + "courant ne contient pas : noms propres, termes de votre "
                 + "métier, mots anglais. Sans eux, ils sont remplacés par "
                 + "ceux qui leur ressemblent.")
            Note("**Utilisé par CrisperWhisper. Ignoré par le moteur de "
                 + "macOS** — son interface accepte bien une liste, mais "
                 + "mesuré sur de vrais enregistrements, elle ne change pas sa "
                 + "sortie d'un caractère. La liste reste ici plutôt que sous "
                 + "un moteur : elle est à vous, pas à lui, et elle servira "
                 + "aux moteurs à venir.")

            Divider().opacity(0.25)

            OptionCheck(title: "Utiliser la liste intégrée",
                        isOn: $prefs.useDefaultLexicon)
            Note(prefs.useDefaultLexicon
                 ? "La liste fournie avec Sofler, orientée développement web. "
                   + "Décochez pour la remplacer par la vôtre."
                 : "Votre liste remplace celle de Sofler — elle ne s'y ajoute "
                   + "pas.")
        }

        if !prefs.useDefaultLexicon {
            Card(title: "Vos termes") {
                entry
                if prefs.lexicon.isEmpty {
                    Note("Aucun terme. Le moteur transcrira en français "
                         + "courant, sans conditionnement.")
                } else {
                    terms
                }

                Divider().opacity(0.25)
                Row(label: "\(prefs.lexicon.count) terme"
                    + (prefs.lexicon.count > 1 ? "s" : "")) {
                    if crowded {
                        Text("liste longue")
                            .font(.system(size: 11))
                            .foregroundStyle(Style.collecting)
                    }
                }
                Note(crowded
                     ? "**Retirez-en avant d'en ajouter.** Le lexique part "
                       + "dans le prompt du modèle : plus il est long, plus il "
                       + "dilue le contexte, et plus le modèle risque d'y "
                       + "piocher un mot sur un passage où vous n'avez rien "
                       + "dit."
                     : "Gardez la liste courte. Le lexique part dans le prompt "
                       + "du modèle, et un prompt long dilue le contexte au "
                       + "lieu de le préciser.",
                     warning: crowded)

                if prefs.lexicon != Preferences.starterLexicon {
                    ButtonRow {
                        Button("Repartir de la liste de Sofler") {
                            prefs.lexicon = Preferences.starterLexicon
                        }
                    }
                }
            }
        }
    }

    // MARK: - Ajouter

    /// Un terme à la fois, plutôt qu'une zone de texte à éditer.
    ///
    /// C'était un `TextEditor` où l'on tapait une ligne par mot. Un lexique ne
    /// s'édite pas comme un fichier : il s'enrichit d'un terme quand on voit
    /// passer une transcription fautive, et se dégarnit quand il devient trop
    /// long. Une liste de lignes rendait ces deux gestes malaisés, et surtout
    /// ne comptait rien.
    private var entry: some View {
        HStack(spacing: 8) {
            TextField("Ajouter un terme", text: $newTerm)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.2)))
                .onSubmit(add)
            Button("Ajouter", action: add)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(cleaned.isEmpty)
        }
    }

    private var cleaned: String {
        newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let term = cleaned
        guard !term.isEmpty else { return }
        // Sans doublon, et sans distinguer la casse : « React » et « react »
        // conditionnent le modèle de la même façon, les compter deux fois ne
        // ferait qu'allonger le prompt.
        guard !prefs.lexicon.contains(where: {
            $0.compare(term, options: .caseInsensitive) == .orderedSame
        }) else {
            newTerm = ""
            return
        }
        prefs.lexicon.append(term)
        newTerm = ""
    }

    // MARK: - Ce qu'il y a dedans

    private var terms: some View {
        FlowLayout(spacing: 6) {
            ForEach(prefs.lexicon, id: \.self) { term in
                HStack(spacing: 5) {
                    Text(term).font(.system(size: 11))
                    Button {
                        prefs.lexicon.removeAll { $0 == term }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Style.cardStroke, lineWidth: 1))
            }
        }
    }
}
