import Testing
@testable import CasprCore

/// Les capacités d'un moteur, et surtout : ce qui doit rester vrai quand on en
/// ajoute un.
///
/// Ces règles n'étaient couvertes par rien, et ce sont précisément celles qui
/// se cassent en silence. Une capacité fausse ne lève aucune erreur — elle
/// fait dicter avec le mauvais moteur, ou arrête un service dont on avait
/// besoin. Le compilateur attrape désormais les `switch` ; ces tests attrapent
/// ce qu'un `switch` complété *sans réfléchir* laisserait passer.
@Suite("Capacités des moteurs")
struct EngineChoiceTests {

    /// **Le test qui compte.** Tout moteur est fourni par le système *ou*
    /// tourne derrière le service local, jamais les deux, jamais ni l'un ni
    /// l'autre.
    ///
    /// C'est l'invariant que les dix-neuf `== .crisperWhisper` violaient sans
    /// le dire : ils rangeaient implicitement tout moteur non-CrisperWhisper
    /// du côté de macOS. Un moteur ajouté demain qui répondrait `false` aux
    /// deux hériterait des règles d'Apple — pas de démon attendu, pas de
    /// téléchargement proposé — et échouerait à la première dictée.
    @Test("Tout moteur est système ou service local, exclusivement")
    func everyEngineSitsOnExactlyOneSide() {
        for engine in EngineChoice.allCases {
            #expect(engine.isSystem != engine.isLocalService,
                    "\(engine.rawValue) doit être exactement l'un des deux")
        }
    }

    @Test("Les deux familles sont peuplées")
    func bothFamiliesExist() {
        #expect(EngineChoice.allCases.contains { $0.isSystem })
        #expect(EngineChoice.allCases.contains { $0.isLocalService })
    }

    /// `systemEngines` sert à bâtir le sélecteur de version ; `isSystem` sert
    /// aux règles. Les deux se sont écrits séparément, donc ils peuvent
    /// diverger — et une divergence afficherait un moteur dans un sélecteur
    /// où les règles ne l'attendent pas.
    @Test("La liste des moteurs système correspond à la capacité")
    func systemListMatchesCapability() {
        #expect(Set(EngineChoice.systemEngines)
                == Set(EngineChoice.allCases.filter(\.isSystem)))
    }

    /// Le lexique et les deux modes passent par le prompt du décodeur. Un
    /// moteur du système n'a pas de prompt : lui prêter ces capacités ferait
    /// afficher un sélecteur de mode sans effet, et un lexique qui ne change
    /// rien — ce que Caspr dit explicitement ne pas faire.
    @Test("Un moteur système n'a ni lexique ni modes")
    func systemEnginesCarryNoPromptCapability() {
        for engine in EngineChoice.allCases where engine.isSystem {
            #expect(!engine.honoursLexicon)
            #expect(!engine.hasModes)
        }
    }

    /// Les `rawValue` sont écrits dans les préférences et dans le corpus. En
    /// renommer un ne casse aucune compilation : ça relit simplement `nil` au
    /// prochain lancement, l'utilisateur retrouve le moteur par défaut, et des
    /// mois de corpus deviennent inattribuables.
    @Test("Les identifiants persistés se relisent")
    func rawValuesRoundTrip() {
        for engine in EngineChoice.allCases {
            #expect(EngineChoice(rawValue: engine.rawValue) == engine)
        }
    }

    @Test("Les identifiants persistés sont ceux déjà écrits sur disque")
    func rawValuesAreStable() {
        #expect(EngineChoice.apple.rawValue == "apple")
        #expect(EngineChoice.appleLegacy.rawValue == "apple-legacy")
        #expect(EngineChoice.crisperWhisper.rawValue == "crisperwhisper")
    }

    /// `fullLabel` compose famille et version. Deux moteurs d'une même famille
    /// doivent rester distinguables à l'écran, sans quoi le sélecteur propose
    /// deux lignes identiques.
    @Test("Deux moteurs ne portent jamais le même libellé complet")
    func fullLabelsAreDistinct() {
        let labels = EngineChoice.allCases.map(\.fullLabel)
        #expect(Set(labels).count == labels.count)
    }

    @Test("Une famille à plusieurs versions les nomme toutes")
    func multiVersionFamiliesNameTheirVersions() {
        let byFamily = Dictionary(grouping: EngineChoice.allCases, by: \.label)
        for (family, engines) in byFamily where engines.count > 1 {
            for engine in engines {
                #expect(engine.versionLabel != nil,
                        "\(family) a \(engines.count) versions, donc \(engine.rawValue) doit se nommer")
            }
        }
    }

    /// Chaque ligne du sélecteur porte son explication. Une chaîne vide
    /// afficherait une ligne sélectionnable sans rien qui la justifie.
    @Test("Chaque moteur explique ce qu'il change")
    func everyEngineExplainsItself() {
        for engine in EngineChoice.allCases {
            #expect(!engine.explanation.isEmpty)
        }
    }
}
