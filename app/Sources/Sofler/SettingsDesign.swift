import AppKit
import SwiftUI

/// Le vocabulaire visuel commun à la barre flottante et aux réglages.
///
/// Il existe parce que les deux surfaces se ressemblaient de loin sans jamais
/// se répondre : la barre avait son verre, sa teinte et ses pastilles, les
/// réglages affichaient des `Form` système gris. Deux dialectes pour une même
/// application. Les valeurs ci-dessous sont celles de `RecordingOverlay`, une
/// seule fois, pour qu'elles ne divergent pas.
enum Style {
    // MARK: Couleurs

    /// Le turquoise de Sofler.
    ///
    /// Une valeur fixe, et non `NSColor.systemTeal` : la teinte système varie
    /// d'une version de macOS à l'autre et se désature hors focus, ce qui
    /// faisait dériver l'identité de l'application au fil des mises à jour.
    /// Toutes les surfaces de Sofler sont sombres, donc rien n'oblige à suivre
    /// l'apparence claire du système.
    static let accent = Color(hex: 0x00E5CC)
    static let accentHover = Color(hex: 0x38EFD8)
    static let accentDim = accent.opacity(0.12)
    static let accentBorder = accent.opacity(0.35)
    static let accentGlow = accent.opacity(0.30)
    /// Le texte posé **sur** l'accent. Presque noir, verdâtre : le blanc sur
    /// turquoise vif tombe sous le seuil de contraste lisible.
    static let onAccent = Color(hex: 0x042F2E)

    /// L'ambre de la collecte, sur la barre d'enregistrement.
    static let collecting = Color(hex: 0xFB923C)
    /// L'ambre des avertissements, dans les réglages. Distinct du précédent :
    /// « ceci est archivé » et « attention » ne disent pas la même chose et ne
    /// doivent pas se confondre d'un coup d'œil.
    static let warning = Color(hex: 0xF59E0B)
    static let danger = Color(hex: 0xF87171)

    static let textPrimary = Color(hex: 0xF8FAFC)
    static let textSecondary = Color(hex: 0x94A3B8)
    static let textTertiary = Color(hex: 0x64748B)

    // MARK: Surfaces

    static let cardFill = Color.white.opacity(0.035)
    static let cardHover = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.08)
    /// Le fond des encarts d'action à l'intérieur d'une carte.
    static let innerBoxFill = Color.black.opacity(0.28)

    // MARK: Géométrie

    static let cardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    /// Encarts d'action et zone d'essai, à l'intérieur d'une carte.
    static let innerRadius: CGFloat = 11
    /// Champs de saisie et barres de recherche.
    static let fieldRadius: CGFloat = 9

    // MARK: Fenêtres

    /// Largeur commune à l'accueil et aux réglages.
    ///
    /// Elle est **identique** dans les deux fenêtres, et c'est tout l'intérêt :
    /// les cartes de configuration sont les mêmes vues, instanciées aux deux
    /// endroits. Une largeur qui diffère de dix points suffit à faire passer un
    /// libellé sur deux lignes ici et une seule là, et la même carte paraît
    /// alors avoir été dessinée deux fois.
    static let windowWidth: CGFloat = 580
    static let windowHeight: CGFloat = 700
    static let windowPadding: CGFloat = 30
    /// Largeur utile des cartes — `windowWidth - 2 × windowPadding`.
    static var contentWidth: CGFloat { windowWidth - 2 * windowPadding }
}

extension NSColor {
    /// L'accent de Sofler, pour le code AppKit — barre d'enregistrement,
    /// enregistreur de raccourci, vumètre.
    ///
    /// La même valeur que `Style.accent`, et non `systemTeal` : la teinte
    /// système varie d'une version de macOS à l'autre et se désature hors
    /// focus, si bien que les surfaces AppKit et SwiftUI de l'application
    /// avaient fini par ne plus s'accorder tout à fait.
    static let soflerAccent = NSColor(srgbRed: 0x00 / 255.0, green: 0xE5 / 255.0,
                                      blue: 0xCC / 255.0, alpha: 1)
    /// L'ambre des avertissements, pour le code AppKit.
    static let soflerWarning = NSColor(srgbRed: 0xF5 / 255.0, green: 0x9E / 255.0,
                                       blue: 0x0B / 255.0, alpha: 1)
}

extension Color {
    /// Couleur depuis un littéral hexadécimal — `Color(hex: 0x00E5CC)`.
    ///
    /// Un entier plutôt qu'une chaîne : la chaîne oblige à traiter le cas du
    /// format invalide, qui ne peut pas arriver dans du code compilé et qui se
    /// solde toujours par un `?? .clear` invisible à la relecture.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension NSWindow {
    /// Crée une fenêtre Sofler autour d'une vue SwiftUI.
    ///
    /// ## Pourquoi une fabrique, et pas trois appels à la suite
    ///
    /// Parce qu'une des étapes est facile à oublier et qu'elle casse tout.
    ///
    /// `NSHostingController` propage par défaut la taille *idéale* de sa vue
    /// SwiftUI vers la fenêtre — c'est `sizingOptions = .preferredContentSize`
    /// — et il le fait **après** l'appel qui fixe la taille. Une page dont le
    /// contenu dépasse produit donc une fenêtre plus haute que l'écran, dont le
    /// pied devient inatteignable : le bouton « Continuer » de l'accueil se
    /// retrouve sous le bord inférieur, sans aucun moyen de l'atteindre puisque
    /// la fenêtre n'est pas redimensionnable. Constaté, et parfaitement muet
    /// côté compilation.
    ///
    /// La fabrique neutralise donc ce comportement : c'est la **fenêtre** qui
    /// impose sa taille, et le contenu qui défile dedans.
    static func sofler<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> NSWindow {
        let hosting = NSHostingController(rootView: content())
        // Aucune remontée de taille : sans ça, tout ce qui suit est écrasé.
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        // Le fond est peint par la vue : sans ça, macOS glisse son gris système
        // derrière et les surfaces de l'application ne se ressemblent plus.
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        // Les fenêtres de Sofler contiennent des boutons qui ouvrent les
        // Réglages Système. Sans ça, elles s'effacent au moment d'y aller, et
        // on revient devant rien — en croyant avoir fait fuir l'application.
        window.hidesOnDeactivate = false
        window.applySoflerGeometry()
        return window
    }

    /// Applique la géométrie commune : 580 × 700, non redimensionnable.
    ///
    /// La hauteur est **écrêtée à l'écran**. Les documents de conception la
    /// notaient `min(700pt, 92vh)`, ce qui est du raisonnement web : il n'y a
    /// pas de `vh` en AppKit, et une fenêtre non redimensionnable plus haute
    /// que la zone utile devient une fenêtre dont on ne peut plus atteindre le
    /// bas — ni le bouton qui s'y trouve. `visibleFrame` retire déjà la barre
    /// de menus et le Dock ; la marge couvre l'ombre et la barre de titre.
    ///
    /// Écrêter plutôt qu'autoriser le redimensionnement : la largeur, elle, ne
    /// doit jamais bouger, sinon les cartes partagées entre l'accueil et les
    /// réglages ne se ressemblent plus.
    func applySoflerGeometry() {
        let available = (screen ?? NSScreen.main)?.visibleFrame.height
            ?? Style.windowHeight
        let height = min(Style.windowHeight, available - 40)
        setContentSize(NSSize(width: Style.windowWidth, height: height))
        // Sans ça, la fenêtre reste étirable par les bords même dépourvue du
        // bouton d'agrandissement.
        styleMask.remove(.resizable)
        center()
    }
}

/// Le verre du fond, identique à celui de la barre.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Le fond des fenêtres de configuration.
///
/// Le verre seul ne suffisait pas, et c'était visible : `hudWindow` en
/// `behindWindow` laisse passer assez du bureau pour que le papier peint
/// traverse les cartes, que les contrastes changent selon ce qu'il y a
/// derrière, et qu'un texte secondaire devienne illisible sur une photo claire.
/// La barre flottante peut se le permettre — elle est petite et éphémère ; une
/// fenêtre qu'on lit pendant plusieurs minutes, non.
///
/// D'où la couche quasi opaque par-dessus, à la valeur du prototype
/// (`rgba(20, 24, 33, 0.96)`) : il reste juste ce qu'il faut de verre pour que
/// la fenêtre appartienne à macOS, et plus assez pour qu'elle dépende du fond
/// d'écran.
struct WindowBackground: View {
    var body: some View {
        ZStack {
            GlassBackground()
            Color(hex: 0x141821).opacity(0.96)
        }
    }
}

/// La barre de titre : la place des feux tricolores, et ce qu'on met à droite.
///
/// La fenêtre est en `fullSizeContentView`, donc le contenu passerait sous les
/// feux sans cette réserve de 48 pt. Le titre lui-même reste celui de macOS —
/// le redessiner donnerait deux titres à trois pixels d'écart.
struct WindowChrome<Trailing: View>: View {
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Spacer()
            trailing
        }
        .frame(height: 48)
        .padding(.horizontal, Style.windowPadding)
    }
}

/// L'en-tête d'un écran : titre et phrase d'introduction.
///
/// Reprend `.page-header` du prototype — 24 pt gras avec un crénage serré, un
/// sous-titre de 13 pt, et 20 pt sous l'ensemble.
struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .kerning(-0.72)
                .foregroundStyle(.white)
            if let subtitle {
                Text(.init(subtitle))
                    .font(.system(size: 13))
                    .foregroundStyle(Style.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
    }
}

/// Le titre d'une section, au-dessus d'une carte — `.section-label`.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .kerning(0.84)
            .foregroundStyle(Style.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Le compteur d'étapes de l'accueil — « 2 / 5 ».
struct StepCounter: View {
    let current: Int
    let total: Int

    var body: some View {
        Text("\(current) / \(total)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Style.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Style.accentDim)
                    .overlay(Capsule().strokeBorder(Style.accentBorder, lineWidth: 1)))
            .accessibilityLabel("Étape \(current) sur \(total)")
    }
}

/// Le bouton principal : pilule turquoise, texte sombre.
///
/// `.borderedProminent` teinté ne donne pas ça — il garde le rayon système et
/// une graisse de texte plus légère, si bien que l'action principale de
/// l'accueil se lisait comme un bouton secondaire. Le contraste vient du texte
/// **sombre** sur le turquoise : du blanc dessus passe sous le seuil lisible.
struct SoflerPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Style.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(isEnabled ? Style.accent
                                                 : Color.white.opacity(0.12)))
            .shadow(color: isEnabled ? Style.accentGlow : .clear,
                    radius: configuration.isPressed ? 4 : 10, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Bouton secondaire : même pilule, sans le remplissage.
struct SoflerSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Style.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.13 : 0.08))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08),
                                                    lineWidth: 1)))
    }
}

/// Une pastille numérotée — « 1 », « 2 », « 3 ».
///
/// Carré arrondi bordé plutôt que disque plein : le disque plein se confond
/// avec les puces d'autorisation accordée (`GrantedLine`), qui disent tout
/// autre chose.
struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Style.accent)
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Style.accentDim)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Style.accentBorder, lineWidth: 1)))
    }
}

/// Un bloc de réglages : titre en capitales espacées, contenu sur une carte.
///
/// Remplace `Section` dans un `Form` groupé, dont le rendu système jure avec le
/// reste de l'application.
struct Card<Content: View>: View {
    let title: String
    /// Teintée turquoise, pour la carte qui porte le message essentiel d'un
    /// écran. Une seule par écran : deux accents concurrents et plus rien ne
    /// ressort.
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Un titre vide n'imprime pas de ligne : certaines cartes se
            // suffisent, et réserver la hauteur laisserait un blanc inexpliqué.
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.9)
                    .foregroundStyle(Style.textTertiary)
            }

            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                        .fill(highlighted ? Style.accent.opacity(0.05) : Style.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Style.cardRadius,
                                             style: .continuous)
                                .strokeBorder(highlighted ? Style.accentBorder
                                                          : Style.cardStroke,
                                              lineWidth: 1))
                )
        }
    }
}

/// Note explicative sous un réglage. Le projet en met beaucoup, parce qu'un
/// réglage dont on ignore la conséquence ne sera jamais touché.
struct Note: View {
    let text: String
    var warning = false

    init(_ text: String, warning: Bool = false) {
        self.text = text
        self.warning = warning
    }

    var body: some View {
        Text(.init(text))
            .font(.system(size: 11))
            .foregroundStyle(warning ? Style.warning : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Sélecteur en pastilles.
///
/// Les mesures viennent de `PillSelector`, celui de la barre flottante, et
/// doivent le rester : c'est le même contrôle, sur deux surfaces. Il avait
/// dérivé — rayons, hauteurs et graisses différents — et la version des
/// réglages paraissait bâclée à côté de l'autre alors qu'elle prétendait être
/// la même chose.
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var disabled = false

    /// Identiques à PillSelector : conteneur de 32, marge de 4, segment de 24.
    private static var height: CGFloat { 32 }
    private static var inset: CGFloat { 4 }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Text(option.label)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Style.accent : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: Self.height - 2 * Self.inset)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(active ? Style.accent.opacity(0.20) : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { if !disabled { selection = option.value } }
            }
        }
        .padding(Self.inset)
        .frame(height: Self.height)
        .background(
            Capsule().fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1)))
        .opacity(disabled ? 0.4 : 1)
    }
}

/// Ligne « libellé à gauche, contrôle à droite ».
struct Row<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 16)
            trailing
        }
    }
}


/// Ligne sélectionnable, pour un choix qui mérite une explication.
///
/// Un `PillPicker` suffit quand les options tiennent en un mot. Choisir un
/// moteur de transcription n'est pas de cet ordre : il faut voir, au moment de
/// choisir, ce que l'option coûte et ce qu'elle empêche. D'où une ligne haute
/// qui porte son texte, plutôt qu'une pastille et une note en dessous qui ne
/// parle que de l'option déjà retenue.
/// Une carte de choix : la pastille radio, le titre, ce que ça change, et le
/// panneau qui ne s'ouvre que si on l'a retenue.
///
/// Reprend `.choice-card` du prototype — rayon 14, `16px 18px`, fond teinté
/// d'accent et bordure turquoise quand elle est sélectionnée.
///
/// ## Le dévoilement progressif
///
/// Le détail n'apparaît **que** sous la carte retenue. C'est ce qui rend la
/// page lisible : deux moteurs entièrement dépliés côte à côte, ce sont deux
/// écrans de réglages empilés pour une seule décision à prendre. Tant qu'on
/// n'a pas choisi, on lit deux phrases et on compare ; une fois choisi, on
/// configure.
struct ChoiceCard<Detail: View>: View {
    let title: String
    let subtitle: String
    let selected: Bool
    /// Le badge « ★ Conseillé pour vous », quand il y a lieu.
    var recommended = false
    let action: () -> Void
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RadioCircle(selected: selected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        if recommended {
                            Text("★ Conseillé pour vous")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Style.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Style.accent.opacity(0.15))
                                    .overlay(Capsule().strokeBorder(Style.accentBorder,
                                                                    lineWidth: 1)))
                        }
                    }
                    Text(.init(subtitle))
                        .font(.system(size: 12))
                        .foregroundStyle(Style.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)

            if selected {
                VStack(alignment: .leading, spacing: 10) { detail }
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                .fill(selected ? Style.accent.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                        .strokeBorder(selected ? Style.accentBorder
                                               : Color.white.opacity(0.06),
                                      lineWidth: 1)))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// La pastille radio du prototype : un cercle bordé, rempli d'un point quand il
/// est retenu. Dessinée plutôt qu'empruntée à SF Symbols, dont le
/// `largecircle.fill.circle` a des proportions différentes.
struct RadioCircle: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? Style.accent : Style.textTertiary,
                              lineWidth: 1.5)
                .frame(width: 16, height: 16)
            if selected {
                Circle().fill(Style.accent).frame(width: 8, height: 8)
            }
        }
        .padding(.top, 2)
    }
}

/// Titre de sous-partie, à l'intérieur d'une carte ou d'une ligne de choix.
///
/// Une `Card` imbriquée dans une autre se lit mal : deux fonds, deux bordures,
/// et le contenu paraît appartenir à un réglage voisin plutôt qu'à celui qui
/// l'englobe. Là où il faut séparer sans encadrer — le modèle, l'installation
/// et la licence sous CrisperWhisper — un filet et un titre suffisent.
struct Subsection: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.25)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Boutons secondaires alignés, taille et style uniformes.
struct ButtonRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}


/// L'interrupteur du projet, dessiné plutôt qu'emprunté au système.
///
/// `Toggle(.switch)` se désature quand la fenêtre n'est plus au premier plan.
/// Sur le gris clair d'une fenêtre système, un interrupteur actif reste
/// reconnaissable ainsi : la piste est pleine, même terne. Sur le verre sombre
/// de Sofler, cette piste grise se confond avec le fond et **un réglage activé
/// se lit comme désactivé** — au point de faire douter qu'il ait été pris en
/// compte.
///
/// On le dessine donc soi-même : l'état affiché ne dépend plus de la fenêtre
/// qui a le focus, seulement de la valeur.
struct SoflerSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Capsule()
            .fill(on ? Style.accent : Color.white.opacity(0.14))
            .overlay(
                Capsule().strokeBorder(
                    on ? Color.clear : Color.white.opacity(0.10), lineWidth: 1))
            .frame(width: 38, height: 22)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    // Le bouton reste blanc dans les deux états : c'est la
                    // piste qui porte l'information, comme sur macOS.
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: on)
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
    }
}

/// Case à cocher pour une option à l'intérieur d'une fonctionnalité.
struct OptionCheck: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.checkbox)
            .font(.system(size: 13))
    }
}

/// Dispose des éléments de largeurs inégales sur plusieurs lignes.
///
/// Un lexique tient en une trentaine de mots courts ; les empiler en colonne
/// donnerait une page entière pour ce qui tient en quatre lignes, et une
/// grille à colonnes fixes gâcherait la place sur « hook » pour l'économiser
/// sur « pull request ».
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
