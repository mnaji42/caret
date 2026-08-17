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

/// Un bloc de réglages : titre en capitales espacées, contenu sur une carte.
///
/// Remplace `Section` dans un `Form` groupé, dont le rendu système jure avec le
/// reste de l'application.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Style.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                        .fill(Style.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Style.cardRadius,
                                             style: .continuous)
                                .strokeBorder(Style.cardStroke, lineWidth: 1))
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
                    .foregroundStyle(active
                        ? Color(nsColor: NSColor.systemTeal
                            .blended(withFraction: 0.25, of: .white) ?? .systemTeal)
                        : Color.secondary)
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
struct ChoiceRow<Detail: View>: View {
    let title: String
    let subtitle: String
    let selected: Bool
    /// Ce moteur a-t-il des options propres ? Explicite plutôt que déduit du
    /// contenu : tester `detail is EmptyView` marche mal dans un ViewBuilder.
    var hasDetail = true
    let action: () -> Void
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Style.accent : Color.secondary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)

            // Les options du moteur retenu sont attachées sous lui, pas
            // ailleurs : elles n'existent que parce qu'il a été choisi.
            // Affichées même quand le moteur n'est pas retenu : on peut
            // écrire avec macOS tout en collectant avec CrisperWhisper, et il
            // faut alors pouvoir régler ce dernier.
            if hasDetail {
                Divider().opacity(0.25).padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 12) { detail }
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selected ? Style.accent.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(selected ? Style.accent.opacity(0.35)
                                               : Color.white.opacity(0.07),
                                      lineWidth: 1)))
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


/// Interrupteur d'une fonctionnalité entière, par opposition à une case qui
/// coche une option.
///
/// La distinction n'est pas décorative : une case à cocher se lit comme « ce
/// détail est retenu », un interrupteur comme « cette fonctionnalité est en
/// marche ». Confondre les deux fait qu'on active une collecte de données en
/// croyant cocher une préférence.
struct FeatureSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn)
                .toggleStyle(SoflerSwitch())
                .labelsHidden()
        }
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
