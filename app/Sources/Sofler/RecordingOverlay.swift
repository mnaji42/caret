import AppKit
import AVFoundation
import QuartzCore

/// Panneau flottant affiché pendant la dictée.
///
/// Il ne se contente pas d'indiquer que l'enregistrement tourne : il permet de
/// corriger le tir **en parlant**. On se rend compte au milieu d'une phrase
/// qu'on est en mot-à-mot au lieu de texte nettoyé, ou que la destination
/// n'est pas la bonne — il faut pouvoir changer sans arrêter, sinon la dictée
/// est à refaire.
///
/// Quatre contraintes non négociables :
///
/// * **ne jamais prendre le focus.** Le texte doit atterrir dans l'application
///   que l'utilisateur avait devant lui ; une fenêtre qui devient active
///   déplacerait le curseur. D'où un `NSPanel` `.nonactivatingPanel`, dont les
///   contrôles restent cliquables sans activer Sofler.
/// * **montrer qu'on entend.** Un point fixe dit que l'enregistrement est
///   lancé, pas que le micro capte. Le niveau en direct, si.
/// * **montrer l'état, pas seulement l'action.** Des boutons qui font défiler
///   les valeurs obligent à lire le libellé pour savoir où on en est. Des
///   segments montrent la valeur active d'un coup d'œil.
/// * **rester étroite.** Elle vit en bas de l'écran pendant qu'on travaille
///   ailleurs. D'où deux lignes courtes plutôt qu'une longue : ce qui
///   concerne la *captation* en haut — chrono, niveau, micro, aperçu — et ce
///   qui concerne le *texte* en dessous — mode et destination.
@MainActor
final class RecordingOverlay {
    /// Tout ce que la barre affiche, en un seul objet.
    ///
    /// Regroupé parce que ces valeurs bougent ensemble : changer de mode
    /// pendant une dictée doit repeindre la barre entière, et une signature à
    /// six paramètres se serait désynchronisée au premier oubli.
    struct Status {
        var mode: TranscriptionMode
        var target: DictationTarget
        /// Nom du fichier de notes mémorisé, `nil` si aucun.
        var noteName: String?
        /// Faux quand basculer sur les notes exigerait un sélecteur qu'on ne
        /// peut pas ouvrir maintenant.
        var canPickNote: Bool = true
        var previewEnabled: Bool
        /// Faux quand le moteur actif n'a qu'un rendu : la pastille de mode
        /// **disparaît** plutôt que d'être grisée. Un contrôle inerte occupe
        /// la place et l'attention sans rien offrir.
        var modesAvailable: Bool = true
        var corpusEnabled: Bool
        var corpusKeepsAudio: Bool
    }

    private var panel: NSPanel?
    private var timer: Timer?

    private let dot = NSView()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let statusLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private let meter = LevelMeter()
    private let modeControl = PillSelector(
        labels: TranscriptionMode.allCases.map(\.label), accent: accent)
    private let targetControl = PillSelector(
        labels: ["Curseur", "Notes…"], accent: accent)
    private let micButton = FirstMouseButton()
    private let corpusBadge = BadgeButton()
    private var container: NSStackView?
    private var recordingRow: NSStackView?
    private var textRow: NSStackView?
    private var previewHeight: NSLayoutConstraint?
    private var card: NSVisualEffectView?
    private var cardSheen: CAGradientLayer?
    private var processingGlow: CALayer?
    private var cardBelowTabs: NSLayoutConstraint?
    private var cardAlone: NSLayoutConstraint?
    private var previewLineCount = 1
    /// Composition courante de la rangée d'onglets.
    private var tabsShowMode: Bool?

    var levelProvider: (() -> Float)?
    var onSelectMode: ((TranscriptionMode) -> Void)?
    var onSelectTarget: ((Bool) -> Void)?

    var onToggleCorpus: (() -> Void)?
    var onCancel: (() -> Void)?

    private var startedAt: Date?
    private var pulsePhase: CGFloat = 0
    private var status = Status(mode: .intended, target: .caret, noteName: nil,
                                previewEnabled: false,
                                corpusEnabled: false, corpusKeepsAudio: false)

    // MARK: - Mesures et couleurs

    /// Teinte des états actifs. Une seule dans toute la barre : deux accents
    /// concurrents et plus rien ne ressort.
    static let accent = NSColor.systemTeal
    /// La collecte a sa propre couleur, et c'est délibéré : c'est le seul
    /// réglage qui écrit sur le disque à l'insu de l'utilisateur. Il doit se
    /// distinguer d'un simple choix de mode.
    private static let collecting = NSColor.systemOrange

    private static let rowHeight: CGFloat = 26
    private static let controlRowHeight: CGFloat = 32
    private static let padding: CGFloat = 13
    private static let rowSpacing: CGFloat = 9
    /// Vide entre les onglets flottants et la carte. C'est lui qui les fait
    /// lire comme deux plans distincts.
    private static let tabGap: CGFloat = 9
    private static let previewLines = 3
    private static let previewFontSize: CGFloat = 13
    private static let previewLineHeight: CGFloat = 18
    private static let minimumWidth: CGFloat = 380
    private static let widthWithPreview: CGFloat = 440
    /// Borne de sécurité avant mesure : trois lignes n'en contiendront jamais
    /// autant, et mesurer la dictée entière à chaque mot serait inutile.
    private static let previewCharacters = 400

    init() {
        // Une fenêtre créée sur un écran qui disparaît reste rattachée à
        // l'espace de cet écran : macOS ne la rapatrie pas. Elle continue
        // d'être ordonnée au premier plan, avec des coordonnées correctes,
        // sans jamais s'afficher — panne observée en débranchant un second
        // écran, et parfaitement muette côté application. On jette donc le
        // panneau à chaque changement d'écrans ; le suivant sera reconstruit
        // dans l'espace courant.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildForNewScreens() }
        }
    }

    // MARK: - Cycle de vie

    func showRecording(_ status: Status) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        startedAt = Date()
        stopProcessingGlow()
        statusLabel.isHidden = true
        container?.isHidden = false
        textRow?.isHidden = false
        cardAlone?.isActive = false
        cardBelowTabs?.isActive = true
        // Une ligne vide laisserait croire que l'aperçu est en panne le temps
        // que les premiers mots arrivent.
        setPreviewNotice(status.previewEnabled ? "en écoute…" : "")
        update(status)

        panel.orderFrontRegardless()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Bascule sur « transcription en cours ».
    ///
    /// Sur une longue dictée le traitement prend plusieurs secondes ; sans ce
    /// retour, on croit à un échec et on relance.
    func showProcessing() {
        guard let panel else { return }
        timer?.invalidate()
        container?.isHidden = true
        textRow?.isHidden = true
        cardBelowTabs?.isActive = false
        cardAlone?.isActive = true
        statusLabel.isHidden = false
        statusLabel.stringValue = "Transcription…"
        panel.setContentSize(NSSize(width: 210, height: 2 * Self.padding + 20))
        cardSheen?.frame = card?.bounds ?? .zero
        position(panel)
        startProcessingGlow()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        stopProcessingGlow()
        panel?.orderOut(nil)
    }

    /// Liseré lumineux qui fait le tour de la carte pendant la transcription.
    ///
    /// Sans lui, l'état « Transcription… » est parfaitement immobile : sur une
    /// longue dictée, plusieurs secondes sans le moindre mouvement se lisent
    /// comme un plantage, et on relance une dictée déjà en cours.
    ///
    /// Un dégradé conique tournant plutôt qu'un trait qui parcourt le
    /// contour : `strokeStart`/`strokeEnd` butent sur les bornes 0 et 1, donc
    /// l'arc s'y écrase à chaque tour. La rotation, elle, boucle sans couture.
    /// Le dégradé tourne à l'intérieur d'un calque porteur, et c'est ce
    /// dernier qui porte le masque — masquer le dégradé lui-même ferait
    /// tourner le masque avec, et il n'y aurait plus de contour du tout.
    private func startProcessingGlow() {
        guard let card, let host = card.layer else { return }
        stopProcessingGlow()
        card.layoutSubtreeIfNeeded()
        let bounds = card.bounds
        guard bounds.width > 0 else { return }

        let outline = CAShapeLayer()
        outline.path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                              cornerWidth: 15, cornerHeight: 15, transform: nil)
        outline.fillColor = nil
        outline.strokeColor = NSColor.black.cgColor      // seul l'alpha compte
        outline.lineWidth = 2

        let carrier = CALayer()
        carrier.frame = bounds
        carrier.mask = outline

        let side = max(bounds.width, bounds.height) * 1.5
        let glow = CAGradientLayer()
        glow.type = .conic
        glow.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2,
                            width: side, height: side)
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 0.5)
        glow.colors = [Self.accent.withAlphaComponent(0).cgColor,
                       Self.accent.cgColor,
                       Self.accent.withAlphaComponent(0).cgColor,
                       Self.accent.withAlphaComponent(0).cgColor]
        glow.locations = [0, 0.06, 0.30, 1]
        carrier.addSublayer(glow)
        host.addSublayer(carrier)

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = 1.6
        spin.repeatCount = .infinity
        glow.add(spin, forKey: "rotation")
        processingGlow = carrier
    }

    private func stopProcessingGlow() {
        processingGlow?.removeFromSuperlayer()
        processingGlow = nil
    }

    var isRecording: Bool { timer != nil }

    func update(_ status: Status) {
        self.status = status

        modeControl.select(TranscriptionMode.allCases.firstIndex(of: status.mode) ?? 0)
        // Masquer ne suffit pas à recentrer : les entretoises restent en
        // place et le contrôle survivant se retrouve décalé d'une demi-
        // entretoise. On refait la rangée avec les seuls contrôles visibles.
        layoutTabs(showMode: status.modesAvailable)

        targetControl.setLabel(Self.noteLabel(for: status), at: 1)
        targetControl.select(status.target.isLocked ? 1 : 0)
        targetControl.setEnabled(status.noteName != nil || status.canPickNote, at: 1)
        // Court, et sur deux lignes : macOS ne replie pas les infobulles, une
        // phrase entière produit une bulle plus large que la moitié de l'écran.
        targetControl.toolTip = status.noteName.map {
            "Ajouté à \($0)\nVaut aussi pour la dictée en cours"
        } ?? "Aucun fichier de notes\nEn choisir un dans le menu de Sofler"

        micButton.attributedTitle = Self.buttonTitle(Self.microphoneModeLabel)
        micButton.toolTip = "Mode micro du système\nCliquer pour le changer"

        previewLabel.toolTip = Self.previewExplanation
        previewLabel.isHidden = !status.previewEnabled

        corpusBadge.setActive(status.corpusEnabled, color: Self.collecting)
        corpusBadge.toolTip = status.corpusEnabled
            ? (status.corpusKeepsAudio
                ? "Chaque dictée est archivée, audio compris\nCliquer pour arrêter"
                : "Chaque dictée est archivée (texte seul)\nCliquer pour arrêter")
            : "Collecte arrêtée\nCliquer pour archiver les dictées"

        resize()
    }

    /// Texte reconnu en direct.
    ///
    /// Ne change ni la largeur ni la position : seule la hauteur suit, et
    /// uniquement quand le nombre de lignes change — deux fois par dictée au
    /// plus, jamais à chaque mot.
    func setPreviewText(_ text: String) {
        guard status.previewEnabled else { return }
        let (visible, lines) = visibleTail(of: text)
        previewLabel.stringValue = visible
        // Plus lisible que le gris des messages d'état : c'est le seul
        // contenu de la barre qu'on lit vraiment, en parlant.
        previewLabel.textColor = .secondaryLabelColor
        setPreviewLines(lines)
    }

    /// Portion affichable du texte : sa **fin**, repliée sur trois lignes au
    /// plus, précédée de points de suspension si on a coupé.
    ///
    /// Calculée ici plutôt que confiée à `.byTruncatingHead`, et c'est une
    /// correction : ce mode de coupe force `NSTextField` en ligne unique, donc
    /// il est incompatible avec le repli. Combinés, on obtenait une seule
    /// ligne tronquée par la fin — exactement l'inverse de ce qu'il faut, où
    /// c'est le dernier mot prononcé qui doit rester visible.
    ///
    /// On cherche donc le plus long suffixe qui tienne dans la boîte, par
    /// dichotomie sur la position de départ.
    private func visibleTail(of text: String) -> (String, Int) {
        guard let font = previewLabel.font, !text.isEmpty else { return (text, 1) }
        let width = previewLabel.bounds.width > 0
            ? previewLabel.bounds.width
            : (panel?.frame.width ?? Self.widthWithPreview) - 2 * (Self.padding + 4)
        guard width > 0 else { return (text, 1) }

        let ceiling = CGFloat(Self.previewLines) * Self.previewLineHeight
        func height(_ candidate: String) -> CGFloat {
            (candidate as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]).height
        }
        func lineCount(_ candidate: String) -> Int {
            max(1, min(Self.previewLines,
                       Int((height(candidate) / Self.previewLineHeight).rounded())))
        }

        // Trois lignes ne contiendront jamais plus de quelques centaines de
        // caractères : mesurer la dictée entière à chaque mot coûterait cher
        // pour rien.
        let bounded = text.count > Self.previewCharacters
            ? String(text.suffix(Self.previewCharacters))
            : text
        if bounded.count == text.count, height(bounded) <= ceiling {
            return (bounded, lineCount(bounded))
        }

        let characters = Array(bounded)
        var low = 0
        var high = characters.count
        while low < high {
            let middle = (low + high) / 2
            if height("… " + String(characters[middle...])) <= ceiling {
                high = middle
            } else {
                low = middle + 1
            }
        }
        let tail = "… " + String(characters[low...])
        return (tail, lineCount(tail))
    }

    private func setPreviewLines(_ lines: Int) {
        guard lines != previewLineCount else { return }
        previewLineCount = lines
        resize()
    }

    /// Message sur l'aperçu lui-même — attente, téléchargement, indisponibilité
    /// — à la place du texte reconnu.
    func setPreviewNotice(_ message: String) {
        previewLabel.stringValue = message
        previewLabel.textColor = .tertiaryLabelColor
        setPreviewLines(1)
    }

    private static let previewExplanation =
        "Aperçu indicatif, par le moteur de macOS\n"
        + "Sans le lexique : le texte inséré différera\n"
        + "Cliquer pour l'activer ou le couper"

    /// Nom court : la largeur de la barre suit celle des contrôles, donc un
    /// nom de fichier long la ferait grossir d'autant. Le nom entier reste
    /// dans l'infobulle.
    private static func noteLabel(for status: Status) -> String {
        guard let name = status.noteName else { return "Notes…" }
        let short = name.count > 14 ? name.prefix(13) + "…" : name[...]
        return "Notes › \(short)"
    }

    /// Mode micro courant, tel que macOS le rapporte.
    ///
    /// Lecture seule : Apple ne laisse aucune application imposer ce réglage,
    /// c'est un choix de l'utilisateur. On peut en revanche ouvrir le panneau
    /// système, ce qui évite d'aller le chercher dans le Centre de contrôle.
    private static var microphoneModeLabel: String {
        switch AVCaptureDevice.activeMicrophoneMode {
        case .voiceIsolation: "Isolement"
        case .wideSpectrum: "Large"
        default: "Standard"
        }
    }

    // MARK: - Construction

    private static func buttonTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    /// Largeur dictée par les contrôles seuls — jamais par le texte reconnu —
    /// et jamais plus large que l'écran. Hauteur ajustée au nombre de lignes
    /// que l'aperçu occupe vraiment : réserver trois lignes en permanence
    /// laissait un vide sous le texte les trois quarts du temps.
    private func resize() {
        guard let panel else { return }
        let rows = [recordingRow?.fittingSize.width ?? 0,
                    textRow?.fittingSize.width ?? 0]
        let needed = (rows.max() ?? Self.minimumWidth) + 2 * Self.padding + 14
        let floor = status.previewEnabled ? Self.widthWithPreview : Self.minimumWidth
        let ceiling = (NSScreen.main?.visibleFrame.width ?? 1440) - 80
        let width = min(max(floor, needed), max(floor, ceiling))

        var height = Self.controlRowHeight + Self.tabGap
            + Self.padding + Self.rowHeight + Self.padding
        if status.previewEnabled {
            height += Self.rowSpacing + CGFloat(previewLineCount) * Self.previewLineHeight
        }
        previewHeight?.constant = CGFloat(previewLineCount) * Self.previewLineHeight
        previewLabel.isHidden = !status.previewEnabled
        panel.setContentSize(NSSize(width: width, height: height))
        // Les couches Core Animation ne suivent pas Auto Layout.
        cardSheen?.frame = card?.bounds ?? .zero
        position(panel)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.minimumWidth, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Visible au-dessus du plein écran et sur tous les bureaux : dicter en
        // travaillant ailleurs est précisément l'usage.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // La fenêtre elle-même ne dessine rien : les onglets doivent flotter
        // *à côté* de la carte, séparés par du vide, et non dans un même bloc.
        let root = NSView()
        panel.contentView = root

        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)

        // Le reflet du verre : une lumière rasante en haut, qui s'éteint vers
        // le bas. C'est ce dégradé, plus que la transparence, qui donne
        // l'impression d'une surface et non d'un rectangle gris.
        let sheen = CAGradientLayer()
        sheen.colors = [NSColor.white.withAlphaComponent(0.10).cgColor,
                        NSColor.white.withAlphaComponent(0.02).cgColor,
                        NSColor.clear.cgColor]
        sheen.locations = [0, 0.35, 1]
        card.layer?.insertSublayer(sheen, at: 0)
        cardSheen = sheen
        self.card = card

        buildIndicators()
        buildControls()

        let recording = makeRow([dot, timeLabel, meter, NSView(),
                                 micButton, corpusBadge])
        let tabs = makeSpacedRow([modeControl, targetControl])
        recordingRow = recording
        textRow = tabs

        let inner = NSStackView(views: [recording, previewLabel])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = Self.rowSpacing
        inner.translatesAutoresizingMaskIntoConstraints = false
        container = inner

        card.addSubview(inner)
        root.addSubview(tabs)
        root.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let height = previewLabel.heightAnchor.constraint(
            equalToConstant: Self.previewLineHeight)
        height.isActive = true
        previewHeight = height

        // Deux ancrages hauts pour la carte, un seul actif à la fois : masquer
        // les onglets ne suffit pas, une contrainte reste en vigueur même
        // quand la vue qu'elle vise est cachée. Sans ça, l'état
        // « Transcription… » gardait la place des onglets et la carte se
        // retrouvait écrasée sur quelques pixels.
        cardBelowTabs = card.topAnchor.constraint(equalTo: tabs.bottomAnchor,
                                                  constant: Self.tabGap)
        cardAlone = card.topAnchor.constraint(equalTo: root.topAnchor)
        cardBelowTabs?.isActive = true

        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: root.topAnchor),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabs.heightAnchor.constraint(equalToConstant: Self.controlRowHeight),

            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor,
                                           constant: Self.padding + 4),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor,
                                            constant: -(Self.padding + 4)),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: Self.padding),

            recording.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            recording.widthAnchor.constraint(equalTo: inner.widthAnchor),
            previewLabel.widthAnchor.constraint(equalTo: inner.widthAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return panel
    }

    /// Rangée centrée, tous les espaces égaux — bords compris.
    ///
    /// C'est le `space-evenly` de flexbox, et non `space-around` : ce dernier
    /// donne des bords valant la moitié de l'intervalle central, ce qui se
    /// voit tout de suite à l'œil comme un déséquilibre. `NSStackView` ne sait
    /// faire ni l'un ni l'autre — ses distributions ne répartissent l'espace
    /// qu'*entre* les vues, jamais aux extrémités — d'où des entretoises dont
    /// on contraint toutes les largeurs à être identiques.
    /// Recompose la rangée d'onglets pour les contrôles réellement affichés.
    ///
    /// Appelée à chaque mise à jour, mais ne fait rien tant que la composition
    /// ne change pas : reconstruire des contraintes vingt fois par seconde
    /// pendant une dictée serait absurde.
    private func layoutTabs(showMode: Bool) {
        guard showMode != tabsShowMode || textRow == nil else { return }
        tabsShowMode = showMode
        guard let row = textRow else { return }
        for view in row.arrangedSubviews {
            row.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        fill(row, with: showMode ? [modeControl, targetControl] : [targetControl])
    }

    private func makeSpacedRow(_ views: [NSView]) -> NSStackView {
        let row = makeRow([])
        row.spacing = 0
        fill(row, with: views)
        return row
    }

    /// Pose les contrôles et les entretoises qui les séparent.
    private func fill(_ row: NSStackView, with views: [NSView]) {
        let spacers = (0...views.count).map { _ in NSView() }
        for (index, view) in views.enumerated() {
            row.addArrangedSubview(spacers[index])
            row.addArrangedSubview(view)
            spacers[index].setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        }
        row.addArrangedSubview(spacers[views.count])
        spacers[views.count].setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        for spacer in spacers.dropFirst() {
            spacer.widthAnchor.constraint(equalTo: spacers[0].widthAnchor).isActive = true
        }
    }

    private func makeRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        // La vue vide sert d'entretoise : elle seule doit s'étirer.
        for view in views where type(of: view) == NSView.self {
            view.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        }
        return row
    }

    private func buildIndicators() {
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        timeLabel.textColor = .labelColor
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        // Italique et discret : l'aperçu ne doit jamais être pris pour le
        // texte qui sera inséré.
        previewLabel.font = NSFontManager.shared.convert(
            .systemFont(ofSize: Self.previewFontSize), toHaveTrait: .italicFontMask)
        previewLabel.textColor = .secondaryLabelColor
        // Repli simple : la coupe est faite en amont, sur la chaîne, donc
        // AppKit n'a plus qu'à mettre à la ligne.
        previewLabel.lineBreakMode = .byWordWrapping
        previewLabel.maximumNumberOfLines = Self.previewLines
        previewLabel.usesSingleLineMode = false
        previewLabel.cell?.wraps = true
        // Sans ça, le champ impose sa largeur naturelle au panneau : mesuré,
        // une fenêtre de 1164 px pour un écran de 1728, le texte sortant par
        // la droite. Un libellé doit céder, c'est le panneau qui commande.
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            meter.widthAnchor.constraint(equalToConstant: 46),
            meter.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    private func buildControls() {
        for (button, action) in [(micButton, #selector(openMicrophoneModes))] {
            button.isBordered = false
            button.bezelStyle = .inline
            button.target = self
            button.action = action
            // Réagit sans que Sofler passe au premier plan.
            button.setButtonType(.momentaryChange)
        }
        corpusBadge.title = "COLLECTE"
        corpusBadge.target = self
        corpusBadge.action = #selector(toggleCorpus)

        modeControl.onSelect = { [weak self] index in
            let modes = TranscriptionMode.allCases
            guard modes.indices.contains(index) else { return }
            self?.onSelectMode?(modes[index])
        }
        targetControl.onSelect = { [weak self] index in
            self?.onSelectTarget?(index == 1)
        }
    }

    /// Jette le panneau après un changement d'écrans, et le remonte aussitôt
    /// si une dictée est en cours — sinon la barre disparaîtrait en plein
    /// milieu d'une phrase.
    private func rebuildForNewScreens() {
        guard panel != nil else { return }
        let wasRecording = isRecording
        let elapsed = startedAt

        stopProcessingGlow()
        panel?.orderOut(nil)
        panel = nil
        cardBelowTabs = nil
        cardAlone = nil
        container = nil
        recordingRow = nil
        textRow = nil
        card = nil
        cardSheen = nil
        tabsShowMode = nil
        NSLog("sofler: écrans modifiés — panneau reconstruit")

        guard wasRecording else { return }
        showRecording(status)
        startedAt = elapsed          // le chrono ne repart pas de zéro
    }

    /// Bas de l'écran, centré — hors du regard et du texte en cours de saisie,
    /// mais visible du coin de l'œil.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.minY + 90))
    }

    private func tick() {
        if let startedAt {
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            timeLabel.stringValue = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        }
        meter.level = levelProvider?() ?? 0

        pulsePhase += 0.09
        dot.layer?.opacity = Float(0.55 + 0.45 * (sin(pulsePhase) + 1) / 2)
    }

    @objc private func toggleCorpus() { onToggleCorpus?() }

    @objc private func openMicrophoneModes() {
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }
}

/// Pastille d'état, allumée ou éteinte.
///
/// Elle sert de rappel autant que d'interrupteur : la collecte écrit sur le
/// disque, et un réglage qu'on oublie d'avoir activé finit par accumuler des
/// gigaoctets d'audio sans qu'on s'en aperçoive.
private final class BadgeButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 17).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setActive(_ active: Bool, color: NSColor) {
        layer?.backgroundColor = active
            ? color.withAlphaComponent(0.9).cgColor
            : NSColor.clear.cgColor
        layer?.borderWidth = active ? 0 : 1
        layer?.borderColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.5).cgColor

        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            // L'espacement des lettres fait lire la pastille comme une
            // étiquette d'état plutôt que comme un mot de plus dans la barre.
            .kern: 0.8,
            .foregroundColor: active ? NSColor.white : NSColor.tertiaryLabelColor,
        ])
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 12
        return size
    }
}

/// Bouton qui répond au premier clic dans une fenêtre inactive.
///
/// Le panneau ne devient jamais clé — c'est ce qui garantit que le curseur ne
/// bouge pas. En contrepartie tout clic y est un « premier clic », que
/// `NSControl` ignore par défaut.
private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Barres de niveau sonore, défilant de droite à gauche.
private final class LevelMeter: NSView {
    var level: Float = 0 {
        didSet { needsDisplay = true }
    }

    private let barCount = 9
    private var history: [Float] = []

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        history.append(level)
        if history.count > barCount { history.removeFirst(history.count - barCount) }

        let barWidth: CGFloat = 3
        let gap = (bounds.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1)

        for index in 0..<barCount {
            let value = index < history.count ? history[history.count - 1 - index] : 0
            let height = max(3, CGFloat(value) * bounds.height)
            // Les barres récentes sont franches, les anciennes s'effacent :
            // le sens de défilement se lit sans y penser.
            let fade = 1 - CGFloat(index) / CGFloat(barCount) * 0.75
            context.setFillColor(NSColor.systemTeal.withAlphaComponent(fade).cgColor)
            let x = bounds.width - CGFloat(index + 1) * barWidth - CGFloat(index) * gap
            let rect = NSRect(x: x, y: (bounds.height - height) / 2,
                              width: barWidth, height: height)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 1.5,
                                   cornerHeight: 1.5, transform: nil))
            context.fillPath()
        }
    }
}
