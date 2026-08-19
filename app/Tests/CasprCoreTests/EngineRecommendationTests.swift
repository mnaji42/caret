import Testing
@testable import CasprCore

/// Le conseil de moteur donné à l'écran 2, et la règle de saisie qui l'alimente.
///
/// L'enjeu : ce conseil décide si quelqu'un télécharge 1,6 Go ou non, au tout
/// premier contact avec l'application. Se tromper dans un sens fait installer un
/// modèle inutile ; se tromper dans l'autre laisse repartir avec un moteur qui
/// écrira « use effect » toute l'année.
@Suite("Conseil de moteur")
struct EngineRecommendationTests {

    private func advise(_ habits: UsageHabits, base: String = "fr",
                        covers: Bool = true) -> EngineRecommendation {
        EngineRecommendation.advise(habits: habits, primaryBase: base,
                                    crisperCoversAll: covers)
    }

    // MARK: - Les règles

    @Test("La légèreté demandée l'emporte sur tout le reste")
    func legereteEmporte() {
        // Même en anglais, même avec du jargon : c'est une demande explicite.
        let habits = UsageHabits(mixesLanguages: true, usesJargon: true,
                                 wantsLightweight: true)
        #expect(advise(habits, base: "en").choice == .appleNative)
    }

    @Test("Le jargon appelle CrisperWhisper")
    func jargonAppelleCrisper() {
        #expect(advise(UsageHabits(usesJargon: true)).choice == .crisperWhisper)
    }

    @Test("Le mélange de langues appelle CrisperWhisper")
    func melangeAppelleCrisper() {
        #expect(advise(UsageHabits(mixesLanguages: true)).choice == .crisperWhisper)
    }

    @Test("L'anglais et l'allemand suffisent, sans rien avoir coché")
    func languesFortesDeWhisper() {
        #expect(advise(UsageHabits(), base: "en").choice == .crisperWhisper)
        #expect(advise(UsageHabits(), base: "de").choice == .crisperWhisper)
    }

    @Test("Sans rien de particulier, macOS suffit")
    func defautMacOS() {
        #expect(advise(UsageHabits(), base: "fr").choice == .appleNative)
        #expect(advise(UsageHabits(), base: "es").choice == .appleNative)
    }

    /// Conseiller un moteur qui ne couvre pas toutes les langues retenues
    /// promettrait un repli silencieux à la première bascule.
    @Test("Une couverture partielle disqualifie CrisperWhisper")
    func couverturePartielleDisqualifie() {
        let habits = UsageHabits(mixesLanguages: true, usesJargon: true)
        #expect(advise(habits, base: "en", covers: false).choice == .appleNative)
    }

    @Test("Le conseil porte toujours une raison non vide")
    func raisonToujoursPresente() {
        for mix in [true, false] {
            for jargon in [true, false] {
                for light in [true, false] {
                    for base in ["fr", "en", "de", "ja"] {
                        for covers in [true, false] {
                            let habits = UsageHabits(mixesLanguages: mix,
                                                     usesJargon: jargon,
                                                     wantsLightweight: light)
                            let advice = advise(habits, base: base, covers: covers)
                            #expect(!advice.reason.isEmpty)
                        }
                    }
                }
            }
        }
    }

    // MARK: - La règle de saisie

    /// Demander 0 Mo en mémoire **et** un modèle de 1,6 Go est un état dont
    /// aucune recommandation ne peut se justifier. La saisie l'interdit.
    @Test("Cocher la légèreté décoche les deux autres")
    func legereteExclutLesAutres() {
        var habits = UsageHabits(mixesLanguages: true, usesJargon: true)
        habits.toggle(.wantsLightweight)

        #expect(habits.wantsLightweight)
        #expect(!habits.mixesLanguages)
        #expect(!habits.usesJargon)
    }

    @Test("Cocher une habitude technique décoche la légèreté")
    func habitudeTechniqueExclutLegerete() {
        var habits = UsageHabits(wantsLightweight: true)
        habits.toggle(.usesJargon)

        #expect(habits.usesJargon)
        #expect(!habits.wantsLightweight)
    }

    @Test("Les deux habitudes techniques coexistent")
    func habitudesTechniquesCoexistent() {
        var habits = UsageHabits()
        habits.toggle(.usesJargon)
        habits.toggle(.mixesLanguages)

        #expect(habits.usesJargon)
        #expect(habits.mixesLanguages)
    }

    @Test("Une bascule deux fois revient au point de départ")
    func basculeReversible() {
        for habit in UsageHabits.Habit.allCases {
            var habits = UsageHabits()
            habits.toggle(habit)
            habits.toggle(habit)
            #expect(habits == UsageHabits())
        }
    }
}
