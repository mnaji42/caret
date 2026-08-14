import AppKit
import Carbon.HIToolbox

/// Raccourci global, actif même quand Caret n'est pas au premier plan.
///
/// On passe par `RegisterEventHotKey` (Carbon) et non par un `CGEventTap` :
/// l'API Carbon ne demande **aucune permission**, là où un tap exige
/// l'Autorisation de saisie. Contrepartie : impossible d'écouter une touche
/// modificatrice seule — d'où un combo classique par défaut.
///
/// Contrainte macOS 15+ : un raccourci dont les seuls modificateurs sont
/// Option et/ou Majuscule est refusé (mesure anti-enregistreur de frappe).
/// Les raccourcis par défaut contiennent Contrôle, ils passent.
final class HotkeyMonitor {
    struct Shortcut: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var label: String
        /// Identifiant distinct par raccourci.
        ///
        /// Tous les moniteurs installent leur gestionnaire sur le même
        /// `GetApplicationEventTarget()` et reçoivent donc *tous* les
        /// événements de raccourci. Sans identifiant propre vérifié à la
        /// réception, chaque moniteur réagit à un raccourci qui ne le
        /// concerne pas.
        var id: UInt32

        /// Défaut : ⌃⌥⌘D.
        ///
        /// Un raccourci global vole la combinaison à *toutes* les apps : ⌃⌥D
        /// était déjà pris par Chrome et par plusieurs éditeurs. Trois
        /// modificateurs rendent la collision très improbable, et macOS ne
        /// réserve rien sur ⌃⌥⌘D.
        ///
        /// Deux modificateurs auraient suffi côté système — macOS 15+ n'exige
        /// qu'un modificateur autre qu'Option ou Majuscule — mais c'est la
        /// cohabitation avec les applications qui impose le troisième.
        static let dictate = Shortcut(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            label: "⌃⌥⌘D",
            id: 1
        )

        /// Échap, capté uniquement pendant l'enregistrement pour annuler.
        static let cancel = Shortcut(
            keyCode: UInt32(kVK_Escape),
            modifiers: 0,
            label: "Échap",
            id: 2
        )
    }

    private var hotKeyRef: EventHotKeyRef?
    private var registeredID: UInt32 = 0
    private var handlerRef: EventHandlerRef?
    private let onTrigger: () -> Void
    private static let signature = OSType(0x43524554)  // 'CRET'

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    deinit {
        unregister()
    }

    func register(_ shortcut: Shortcut = .dictate) -> Bool {
        unregister()
        registeredID = shortcut.id

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            // Filtrer sur l'identifiant est indispensable, pas seulement sur la
            // signature : les gestionnaires partagent la même cible et voient
            // donc les raccourcis des autres moniteurs.
            guard status == noErr,
                  hotKeyID.signature == HotkeyMonitor.signature,
                  hotKeyID.id == monitor.registeredID else {
                return noErr
            }
            DispatchQueue.main.async { monitor.onTrigger() }
            return noErr
        }

        let installed = InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard installed == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: shortcut.id)
        let registered = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return registered == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
