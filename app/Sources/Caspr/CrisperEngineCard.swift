import SwiftUI

/// CrisperWhisper : son rendu, son modèle, et le cycle de vie de son service.
///
/// ## Deux présentations pour un même composant
///
/// **Vue compacte** — quand tout tourne, dans les Réglages. Deux colonnes : à
/// gauche l'état sur deux lignes, à droite le bouton de changement de modèle et
/// le retrait discret. C'est la vue de tous les jours, celle qui répond à « ça
/// marche, et avec quoi ».
///
/// **Catalogue déployé** — pendant l'accueil, quand un modèle manque, ou sur
/// demande explicite. La grille des quatre modèles, l'encart d'action de
/// l'étape courante, et la licence.
///
/// Le basculement est automatique : on ne montre pas quatre modèles et une
/// licence à quelqu'un dont le service tourne déjà — c'est la moitié de la
/// fenêtre occupée par une question qu'il ne se pose plus.
///
/// ## Le verrouillage pendant l'installation, et son relâchement
///
/// Pendant l'accueil, dès qu'un téléchargement démarre, les autres modèles sont
/// grisés : deux téléchargements de 1,6 Go simultanés se gêneraient, et rien
/// dans l'interface ne dirait lequel est en cours.
///
/// **Mais une erreur les déverrouille tous.** C'est le détail qui compte, et il
/// vient du prototype : coincé sur un modèle qui échoue — réseau coupé,
/// mémoire insuffisante, poids retirés de Hugging Face — il faut pouvoir en
/// choisir un autre. Un verrou qui survit à l'échec transforme une gêne en
/// impasse.
///
/// ## Ce qui vient du Swift plutôt que du prototype
///
/// Le prototype a quatre états ; `EngineInstall.Step` en a **six**, et les deux
/// de plus valent leur place. `serviceMissing` distingue « rien n'est
/// installé » de « installé mais arrêté ». `serviceStarting` couvre la minute
/// pendant laquelle le service tourne sans avoir fini de lire ses poids — son
/// absence faisait afficher « Prêt » à une dictée qui ne rendait rien.
///
/// Les descriptions de modèles sont aussi celles du Swift, qui dit ce qui a été
/// **mesuré** et reconnaît ce qui ne l'a pas été. Le prototype annonce des
/// latences pour les quatre modèles ; un seul a été éprouvé ici, et prêter aux
/// autres des chiffres inventés serait fabriquer un classement.
struct CrisperEngineCard: View, ValidatingComponent {
    /// Imbriqué sous une ligne de choix : la carte perd son cadre.
    var isSubCard = false
    /// Pendant l'accueil : catalogue toujours déployé, verrouillage actif, et
    /// aucun bouton de retrait — on ne propose pas de désinstaller ce qu'on
    /// vient d'installer.
    var isOnboarding = false
    /// Prévient la carte parente que le service vient d'être arrêté d'ici.
    var onStopped: () -> Void = {}

    @State private var prefs = Preferences.shared
    @State private var bootstrap = EngineBootstrap.shared
    @State private var monitor = EngineStateMonitor.shared
    @State private var catalogueExpanded = false
    /// Le modèle que l'utilisateur regarde, qui n'est pas forcément celui qui
    /// est installé — c'est tout l'intérêt du catalogue.
    @State private var draftModel = Preferences.shared.chosenCrisperModel
        ?? EngineInstall.selectedModel

    // MARK: - Validité

    static func validate() -> ComponentValidationError? {
        EngineSafetyManager.shared.isReady(.crisperWhisper,
                                           for: Preferences.shared.primaryLanguage)
            ? nil : .crisperEngineNotReady
    }

    /// L'étape, **pour le modèle affiché**.
    ///
    /// Calculée par modèle et non globalement : regarder un modèle non
    /// téléchargé doit montrer « poids manquants », même si un autre modèle
    /// tourne parfaitement à côté.
    ///
    /// Lue sur `EngineStateMonitor` et non sur `EngineInstall` : c'est une
    /// propriété calculée, donc un seul rendu la relit plusieurs fois, et la
    /// version d'origine lançait un `launchctl` à chaque lecture.
    private var step: EngineInstall.Step { monitor.step(for: draftModel) }

    private var installing: Bool {
        switch bootstrap.phase {
        case .idle, .done, .failed: false
        default: true
        }
    }

    private var failure: String? {
        if case .failed(let message) = bootstrap.phase { return message }
        return nil
    }

    /// Le modèle que l'utilisateur a retenu, s'il est encore utilisable.
    ///
    /// « Retenu » veut dire téléchargé ou démarré au moins une fois, pas
    /// simplement regardé. `nil` aussi quand ses poids ont été retirés depuis :
    /// il n'y a alors plus de décision à rappeler, et la grille reprend sa
    /// place.
    private var chosenModel: CrisperWhisperModel? {
        guard EngineInstall.isAvailable,
              let chosen = prefs.chosenCrisperModel,
              chosen.isDownloaded
        else { return nil }
        return chosen
    }

    /// La vue compacte, ou le catalogue.
    ///
    /// Se décidait sur `step == .ready` : arrêter le service redéployait les
    /// quatre modèles et la licence, comme au premier jour. C'est une erreur
    /// d'UX — elle pousse à retélécharger des gigaoctets déjà sur le disque
    /// pour une décision déjà prise. Ce qui compte n'est pas que le service
    /// tourne à cet instant, c'est qu'un modèle ait été choisi : le relancer
    /// est alors un bouton, pas un catalogue.
    ///
    /// Ne dépend pas non plus d'une opération en cours. Démarrer le service
    /// faisait réapparaître les quatre modèles sous les doigts de quelqu'un
    /// qui venait justement d'en choisir un — la question du *lequel* était
    /// tranchée, seule celle du *et maintenant* restait ouverte. La section du
    /// modèle ne bouge donc plus pendant qu'on agit ; c'est la suivante qui
    /// rend compte.
    private var showsCompact: Bool {
        !catalogueExpanded && chosenModel != nil
    }

    var body: some View {
        Group {
            if isSubCard {
                content
            } else {
                Card { content }
            }
        }
        // Ce que cette carte affiche vient de trois sources qu'aucune
        // notification ne signale : des fichiers sur le disque, l'avis de
        // launchd, et l'existence d'un socket. Seule `phase` est observable — et
        // s'y fier seule s'est révélé insuffisant : le journal montrait le
        // service démarré et `phase` passée à `.done`, pendant que la vue
        // restait figée sur « … 9 s ».
        //
        // C'est `EngineStateMonitor` qui regarde désormais, pour tout le monde.
        // La carte avait sa propre boucle, la carte parente une deuxième, et la
        // fenêtre de démarrage une troisième — trois horloges pour la même
        // question.
        .onAppear {
            monitor.observe()
            // Le modèle peut changer depuis ailleurs — un retrait dans une
            // autre carte, un descripteur réécrit par le service.
            draftModel = prefs.chosenCrisperModel ?? EngineInstall.selectedModel
        }
        .onDisappear { monitor.release() }
    }

    /// Quatre sections, dans cet ordre, et qui ne se mélangent pas.
    ///
    /// 1. Ce qu'est CrisperWhisper — porté par la ligne de choix au-dessus.
    /// 2. Le rendu : texte nettoyé ou mot à mot.
    /// 3. **Le modèle**, avec deux états : la grille des quatre, ou celui qu'on
    ///    a retenu avec de quoi en changer ou l'effacer.
    /// 4. **L'action** : installer, télécharger, démarrer, ou l'état du service.
    ///
    /// Les sections 3 et 4 étaient mêlées — le bouton « Démarrer le service »
    /// vivait dans la boîte qui nomme le modèle, si bien qu'on lisait « Turbo,
    /// changer, supprimer, démarrer » d'un seul tenant sans savoir ce qui
    /// répondait à quoi. Séparées, chacune ne pose qu'une question : *lequel*,
    /// puis *et maintenant*.
    @ViewBuilder
    private var content: some View {
        renderSection
        languageCoverage
        modelSection
        actionBox
    }

    /// Combien de langues les poids savent transcrire, et comment on la choisit.
    ///
    /// La question revient : « avec CrisperWhisper, faut-il encore choisir une
    /// langue ? » La requête la lui transmet, et elle construit le jeton de
    /// langue du décodeur — mais Whisper est multilingue, et ce jeton
    /// **oriente** sans contraindre : parler français avec l'anglais réglé
    /// donne le plus souvent du français correct. C'est le même mécanisme qui
    /// lui fait tenir le franglais, et c'est ce qu'il faut dire plutôt que de
    /// promettre une contrainte que le modèle n'applique pas.
    @ViewBuilder
    private var languageCoverage: some View {
        let covered = prefs.primary.isCoveredByCrisperWhisper
        Note("**\(Language.crisperWhisperBases.count) langues** — français, "
             + "anglais, espagnol, allemand, italien, portugais, néerlandais, "
             + "japonais, chinois, russe… La langue principale lui est indiquée "
             + "à chaque dictée et se change depuis la barre flottante, mais "
             + "elle l'oriente plutôt qu'elle ne le contraint : le modèle est "
             + "multilingue et retombe souvent sur ses pieds si vous parlez une "
             + "autre langue. C'est ce qui lui permet de tenir le franglais."
             + (covered ? ""
                : " **\(prefs.primary.displayName) n'en fait pas partie** : "
                  + "macOS écrit tant que cette langue est active."))
    }

    /// Section 3 — le modèle.
    @ViewBuilder
    private var modelSection: some View {
        if showsCompact {
            chosenModelRow
        } else {
            catalogue
        }
    }

    // MARK: - Rendu

    /// Le mode par défaut, toujours en tête du panneau.
    ///
    /// En tête parce que c'est le seul réglage qu'on change souvent : le modèle
    /// se choisit une fois, le rendu se discute à chaque type de dictée.
    private var renderSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RENDU")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(Style.textTertiary)
                    Text("Mode par défaut")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                PillPicker(options: [(TranscriptionMode.intended, "Texte nettoyé"),
                                     (TranscriptionMode.verbatim, "Mot à mot")],
                           selection: $prefs.defaultMode)
            }

            // Le texte change avec le mode : expliquer les deux en permanence
            // ferait lire la description de celui qu'on n'a pas choisi.
            Text(prefs.defaultMode == .intended
                 ? "« Nettoyé » retire les hésitations et les répétitions ; "
                   + "« mot à mot » garde tout, y compris les « euh ». Le choix "
                   + "se change aussi en cours de dictée depuis la barre flottante."
                 : "« Mot à mot » (Verbatim) transcrit fidèlement chaque son et "
                   + "hésitation prononcée. Le mode se change aussi en direct "
                   + "depuis la barre flottante.")
                .font(.system(size: 11))
                .foregroundStyle(Style.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: - Vue compacte

    /// Le modèle retenu, et rien d'autre : lequel, et comment en changer.
    ///
    /// L'état du service n'est **pas** ici. Il appartient à la section
    /// suivante, qui répond à « et maintenant ». Les mêler faisait cohabiter
    /// « Supprimer ce modèle » et « Démarrer le service » dans le même cadre,
    /// à deux centimètres l'un de l'autre.
    private var chosenModelRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MODÈLE RETENU")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(Style.textTertiary)
                Text(draftModel.catalogueName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(draftModel.residentMemory) en mémoire vive une fois chargé.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Style.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // Tout se grise pendant une opération. Changer de modèle ou
            // supprimer des poids au milieu d'un téléchargement ou d'un
            // chargement en mémoire laisse le service et le disque dans un
            // état que rien ne décrit — mieux vaut rendre le geste impossible
            // que d'avoir à le rattraper.
            VStack(alignment: .trailing, spacing: 4) {
                Button("Changer de modèle…") { catalogueExpanded = true }
                    .buttonStyle(CasprSecondaryButtonStyle())
                DestructiveLink("Supprimer ce modèle (\(draftModel.downloadSize))") {
                    remove(draftModel)
                }
                .help("Retire les \(draftModel.downloadSize) du disque et oublie "
                      + "ce choix : la grille des quatre modèles revient.")
            }
            .disabled(installing)
            .opacity(installing ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)))
    }

    // MARK: - Catalogue

    @ViewBuilder
    private var catalogue: some View {
        HStack {
            Text("MODÈLE D'IA LOCALE (~10 LANGUES INCLUSES)")
                .font(.system(size: 10, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Style.textTertiary)
            Spacer()
            Text(.init("Mémoire : **\(draftModel.residentMemory)**"))
                .font(.system(size: 11))
                .foregroundStyle(Style.textSecondary)
        }

        modelGrid

        Text(.init("ℹ️ \(draftModel.explanation)"))
            .font(.system(size: 11.5))
            .foregroundStyle(Style.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// La grille 2×2. Deux colonnes fixes : quatre modèles en une colonne
    /// occuperaient toute la hauteur de la fenêtre pour quatre lignes de texte.
    private var modelGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)],
                  spacing: 8) {
            ForEach(CrisperWhisperModel.allCases, id: \.self) { model in
                modelTile(model)
            }
        }
    }

    /// Un modèle est-il inaccessible parce qu'un autre s'installe ?
    ///
    /// Le verrou ne valait que pendant l'accueil. Or ce qu'il empêche — deux
    /// téléchargements de 1,6 Go lancés en parallèle, ou un service qu'on
    /// bascule pendant qu'il charge — est tout aussi fâcheux depuis les
    /// réglages, où l'on passe justement pour changer de modèle. Il vaut
    /// partout, pendant toute opération en cours.
    ///
    /// Il ne dépend plus non plus de `step == .ready` : un service qui tourne
    /// n'est pas une raison d'interdire d'en changer, c'est même le cas
    /// ordinaire du bouton « Changer de modèle… ».
    ///
    /// `failure == nil` est la condition qui relâche tout : une erreur doit
    /// laisser choisir un autre modèle, pas enfermer sur celui qui échoue.
    private func isLocked(_ model: CrisperWhisperModel) -> Bool {
        guard failure == nil, model != draftModel else { return false }
        return installing
    }

    private func modelTile(_ model: CrisperWhisperModel) -> some View {
        let selected = model == draftModel
        let downloaded = model.isDownloaded
        let locked = isLocked(model)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.catalogueName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected ? Style.accent : .white)
                Spacer(minLength: 4)
                if downloaded {
                    Text("Installé ✓")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Style.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(Style.accent.opacity(0.2)))
                } else {
                    Text(model.downloadSize)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Style.textTertiary)
                }
            }
            Text("RAM : \(model.residentMemory)\(model.measuredLatency.map { " · \($0)" } ?? "")")
                .font(.system(size: 11))
                .foregroundStyle(Style.textSecondary)

            // Aucun retrait pendant l'accueil : proposer de désinstaller ce
            // qu'on vient d'installer n'a pas de sens à ce moment-là.
            if !isOnboarding, downloaded {
                HStack {
                    Spacer()
                    DestructiveLink("Supprimer (\(model.downloadSize))",
                                    size: 9.5) { remove(model) }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Style.accent.opacity(0.12) : Color.black.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Style.accent
                                  : (downloaded ? Style.accent.opacity(0.3)
                                                : Color.white.opacity(0.08)),
                                  lineWidth: 1)))
        .opacity(locked ? 0.45 : 1)
        .saturation(locked ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if !locked { select(model) } }
        .help(locked ? "Un téléchargement est en cours" : "")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - L'encart d'action de l'étape courante

    @ViewBuilder
    private var actionBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let failure, !installing {
                errorRow(failure)
            }

            if installing {
                progressRow
            } else {
                switch step {
                case .engineMissing:
                    need(title: draftModel.isDownloaded
                         ? "Environnement Python local à initialiser"
                         : "Installation autonome de CrisperWhisper",
                         detail: draftModel.isDownloaded
                         ? "Les poids de \(draftModel.catalogueName) "
                           + "(\(draftModel.downloadSize)) sont déjà sur votre "
                           + "disque. Il reste à initialiser Python et PyTorch "
                           + "(~1,2 Go)."
                         : "Télécharge Python & dépendances (~1,2 Go) + poids de "
                           + "\(draftModel.catalogueName) "
                           + "(\(draftModel.downloadSize)) directement dans le "
                           + "dossier de Caspr. Zéro impact système.")
                    licence
                    installButton(draftModel.isDownloaded
                                  ? "Installer l'environnement (~1,2 Go)"
                                  : "Installer CrisperWhisper (\(draftModel.totalDownload))")

                case .modelMissing(let model):
                    need(title: "Poids de \(model.catalogueName) manquants",
                         detail: "L'outil uv et l'environnement Python sont "
                         + "prêts. Il reste à télécharger les "
                         + "\(model.downloadSize) du modèle "
                         + "\(model.catalogueName).")
                    // Toujours affichée, cochée ou non : c'est un rappel de
                    // ce sous quoi on récupère les poids, pas une formalité
                    // qu'on expédie une fois pour toutes.
                    licence
                    installButton("Télécharger les poids (\(model.downloadSize))")

                case .serviceMissing, .serviceStopped:
                    HStack(alignment: .top, spacing: 10) {
                        pendingCircle
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Service CrisperWhisper au repos")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Tout est téléchargé sur votre Mac. Démarrez "
                                 + "le service pour charger le modèle en "
                                 + "mémoire vive (\(draftModel.residentMemory)).")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Style.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button("Démarrer le service") { start() }
                            .buttonStyle(CasprPrimaryButtonStyle())
                    }

                // Absent du prototype, et c'est le Swift qui a raison : le
                // service peut tourner sans avoir fini de lire ses poids, et
                // l'annoncer « Prêt » envoie dicter dans le vide.
                case .serviceStarting:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Chargement de \(draftModel.catalogueName) en "
                             + "mémoire — la première fois peut prendre une minute.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Style.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                case .ready:
                    readyRow
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: Style.innerRadius,
                                          style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)))
    }

    private var pendingCircle: some View {
        Circle()
            .strokeBorder(Style.textTertiary, lineWidth: 1.5)
            .frame(width: 18, height: 18)
    }

    private func need(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            pendingCircle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Style.textSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// La licence, qui conditionne le bouton.
    ///
    /// **Volontairement non persistée**, et redemandée à chaque
    /// téléchargement. Elle l'était, et la case disparaissait dès qu'on l'avait
    /// cochée une fois : six mois plus tard on récupérait d'autres poids sans
    /// que rien ne rappelle sous quelle licence. Or c'est le seul moment où
    /// l'information compte. Cf. `Preferences.crisperLicenceAccepted`.
    private var licence: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $prefs.crisperLicenceAccepted)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                Text(.init("J'accepte la **licence de recherche non "
                           + "commerciale** des poids de Nyra Health."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Style.textSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Lire la licence") {
                    NSWorkspace.shared.open(
                        URL(string: "https://huggingface.co/nyralabs")!)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)))
    }

    /// Le bouton d'installation — ou la raison pour laquelle il n'y en a pas.
    ///
    /// L'empêchement était mesuré **après** le clic : on proposait un
    /// téléchargement de plusieurs gigaoctets sur un Mac Intel, sur une copie
    /// sans le code du moteur, ou sur un disque plein — et l'échec tombait
    /// ensuite, parfois après vingt minutes de réseau. Ce qui empêche de
    /// commencer se dit avant de commencer.
    @ViewBuilder
    private func installButton(_ label: String) -> some View {
        if let obstacle = EngineBootstrap.obstacle(installing: draftModel) {
            Note(obstacle, warning: true)
        } else {
            HStack {
                Spacer()
                Button(label) { install() }
                    .buttonStyle(CasprPrimaryButtonStyle())
                    .disabled(!prefs.crisperLicenceAccepted)
            }
        }
    }

    /// La progression, avec la fraction quand elle est **réelle**.
    ///
    /// Contrairement aux modèles d'Apple, le service local expose de vraies
    /// mesures : la fraction de `uv` téléchargée, celle des poids déduite de ce
    /// qui est sur disque. Les étapes qui n'ont rien à mesurer portent leur
    /// libellé et un indicateur indéterminé, plutôt qu'un pourcentage inventé.
    @ViewBuilder
    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(phaseLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Style.textSecondary)
                Spacer(minLength: 8)
                if let fraction = phaseFraction {
                    Text("\(Int(fraction * 100)) %")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Style.accent)
                }
            }
            if let fraction = phaseFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Style.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Style.accent)
            }
        }
    }

    private var phaseLabel: String {
        switch bootstrap.phase {
        case .fetchingTool:
            "Téléchargement de uv & configuration de Python 3.12…"
        case .preparing(let what):
            what
        case .installingDependencies(let line):
            line.isEmpty
                ? "Installation des bibliothèques PyTorch et Transformers (~1,2 Go)…"
                : line
        case .downloadingModel:
            "Téléchargement des poids de \(draftModel.catalogueName) "
                + "(\(draftModel.downloadSize))…"
        case .startingService(let seconds):
            "Lancement du service et chargement en mémoire… \(seconds) s"
        case .idle, .done, .failed:
            ""
        }
    }

    private var phaseFraction: Double? {
        switch bootstrap.phase {
        case .fetchingTool(let f), .downloadingModel(let f): f
        default: nil
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Style.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Erreur de téléchargement ou de lancement")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Style.danger)
                Text(message + (isOnboarding
                     ? " Les autres modèles sont déverrouillés si vous préférez "
                       + "en tester un autre."
                     : ""))
                    .font(.system(size: 11))
                    .foregroundStyle(Style.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Réessayer") { install() }
                .buttonStyle(CasprSecondaryButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Style.danger.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Style.danger.opacity(0.3), lineWidth: 1)))
    }

    private var readyRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Style.accent).frame(width: 18, height: 18)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Style.onAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    // Le modèle est nommé juste au-dessus, dans la section qui
                    // le choisit. Le répéter ici ferait lire deux fois « Turbo
                    // ★ (Recommandé) » à trois lignes d'intervalle.
                    Text("Service actif")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(draftModel.residentMemory) RAM")
                        .font(.system(size: 11))
                        .foregroundStyle(Style.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(Style.accent.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Style.accentBorder, lineWidth: 1)))
                }
                Text("Joignable sur son socket local. La dictée passe par lui.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Style.textSecondary)
            }
            Spacer(minLength: 8)
            Button("Arrêter (Libérer RAM)") { stop() }
                .buttonStyle(CasprSecondaryButtonStyle())
                .help("Arrêter le service pour libérer la mémoire")
                .disabled(installing)
                .opacity(installing ? 0.4 : 1)
        }
    }

    // MARK: - Actions

    /// Regarder un modèle, et parfois le prendre.
    ///
    /// Cliquer sur une tuile ne fait qu'afficher ce modèle : on parcourt la
    /// grille pour lire ce que chacun fait, et rien n'est décidé. Il n'y a
    /// engagement que si ses poids sont déjà là — le service bascule alors
    /// dessus, ce qui est un vrai choix, et il est retenu comme tel.
    ///
    /// Le basculement passe par la machine à états : appeler `installService`
    /// directement démarrait bien le service, mais sans rien afficher pendant
    /// la minute de chargement.
    private func select(_ model: CrisperWhisperModel) {
        draftModel = model
        guard model.isDownloaded, EngineInstall.isAvailable else { return }
        Task {
            await bootstrap.startService(model: model)
            // Relu tout de suite : l'inspecteur ne rebattra qu'au prochain
            // tour, et ce qui suit décide de replier le catalogue.
            monitor.refresh()
            if monitor.step(for: model) == .ready {
                EngineSafetyManager.shared.confirmWorking(.crisperWhisper)
                catalogueExpanded = false
            }
        }
    }

    private func install() {
        // La grille reste ouverte pendant le téléchargement. Sans ça, retenir
        // le modèle dès le premier octet la replierait aussitôt sur la vue
        // compacte, et l'on ne verrait jamais les autres se griser.
        catalogueExpanded = true
        Task {
            await bootstrap.install(model: draftModel,
                                    licenceAccepted: prefs.crisperLicenceAccepted)
            monitor.refresh()
            // Le catalogue se replie de lui-même quand tout est prêt : la
            // question qu'il posait n'a plus lieu d'être.
            if monitor.step(for: draftModel) == .ready {
                catalogueExpanded = false
            }
        }
    }

    private func start() {
        Task {
            await bootstrap.startService(model: draftModel)
            monitor.refresh()
        }
    }

    /// Arrêter le service, c'est choisir de ne plus dicter avec CrisperWhisper.
    ///
    /// Le réglage suit donc le geste. Sans ça, le moteur restait coché sur
    /// CrisperWhisper avec un bandeau d'avertissement permanent : rouvrir
    /// l'application le retrouvait sélectionné mais inopérant, et le bandeau
    /// annonçait une indisponibilité subie là où il s'agissait d'une décision.
    ///
    /// Rien n'est perdu : le modèle reste sur le disque et reste le modèle
    /// retenu. Le reprendre est un clic.
    ///
    /// `finalEngine` et non `engine` : ce dernier écrirait aussi la version de
    /// macOS, et forcerait Apple Intelligence à quelqu'un qui a choisi Dictée.
    private func stop() {
        EngineService.reconcile(needed: false)
        prefs.finalEngine = .apple
        onStopped()
        LanguageSwitchCoordinator.shared.announce(
            "Service arrêté — \(draftModel.residentMemory) libérés. "
            + "macOS écrit désormais ; \(draftModel.catalogueName) reste sur "
            + "votre disque.")
        // Une courte rafale plutôt qu'un seul regard : `launchctl` rend la main
        // avant que le serveur ait retiré son socket, donc le premier constat
        // voit encore un service qui répond — et la carte garderait « Service
        // actif » sous les yeux de quelqu'un qui vient de l'arrêter.
        Task {
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(400))
                monitor.refresh()
            }
        }
    }

    private func remove(_ model: CrisperWhisperModel) {
        EngineInstall.remove(model: model)
        monitor.refresh()
        // Retirer les poids annule le choix : il n'y a plus de décision à
        // rappeler, et la grille reprend sa place d'elle-même.
        if prefs.chosenCrisperModel == model { prefs.chosenCrisperModel = nil }
        // Retirer le modèle qui écrivait laisse la dictée sans moteur : le
        // repli s'en occupe, mais il faut qu'il soit réévalué tout de suite.
        draftModel = EngineInstall.selectedModel
        catalogueExpanded = true
    }
}

/// Une action destructive discrète, qui rougit au survol.
///
/// Elle ne crie pas : supprimer un modèle est réversible d'un téléchargement, et
/// un bouton rouge permanent ferait douter d'un geste courant. Mais elle rougit
/// dès qu'on l'approche, pour qu'on sache ce qu'on s'apprête à faire.
private struct DestructiveLink: View {
    let label: String
    var size: CGFloat = 10.5
    let action: () -> Void

    @State private var hovering = false

    init(_ label: String, size: CGFloat = 10.5, action: @escaping () -> Void) {
        self.label = label
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: size))
            .foregroundStyle(hovering ? Style.danger : Style.textTertiary)
            .onHover { hovering = $0 }
    }
}

#Preview("CrisperWhisper") {
    ScrollView {
        CrisperEngineCard()
            .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: Style.windowHeight)
    .background(Color(hex: 0x141821))
}
