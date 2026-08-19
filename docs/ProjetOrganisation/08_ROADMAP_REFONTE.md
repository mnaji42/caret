# 🗺️ 08 — Roadmap de la Refonte (document vivant)

> Ce fichier est **l'état de vérité** de l'avancement de la refonte. Il est mis à
> jour à chaque fin de bloc, avant le commit. Si vous reprenez le projet après une
> interruption, lisez ce fichier en premier.

**Dernière mise à jour :** 2026-08-18 — **les six blocs sont terminés.**
**Bloc courant :** aucun. Reste la vérification à l'exécution (cf. §7).
**Commit de référence (avant refonte) :** `2ea716b`

---

## 1. État d'avancement

| Bloc | Contenu | Statut |
| :--- | :--- | :---: |
| **0** | Socle : design system, géométrie, `Preferences` multi-langues, découplage moteurs, services | ✅ **Fait** |
| **1** | Composants atomiques réutilisables (11 vues) | ✅ **Fait** |
| **2** | Onboarding 5 étapes + `SetupRecoveryGuard` | ✅ **Fait** |
| **3** | Réglages 6 onglets + menu barre épuré + modale de mise à jour | ✅ **Fait** |
| **4** | `RecordingOverlay` — habillage seul, logique intacte | ✅ **Fait** |
| **5** | `UninstallationView` — habillage seul, logique intacte | ✅ **Fait** |

**Portes de validation (à chaque fin de bloc, sans exception) :**
1. `swift build` — zéro erreur, **zéro avertissement**.
2. `swift test` — vert.
3. Une dictée réelle de bout en bout (déclencheur → overlay → insertion au curseur).
4. `sessions.jsonl` toujours lisible par le script pandas du README du corpus.
5. Commit git atomique.

---

## 2. Audit initial — ce qui est conservé tel quel

Le code de `app/Sources/Sofler/` (≈ 12 100 lignes) n'est pas un brouillon : c'est
un dépôt de **décisions déjà payées**, dont la plupart sont documentées en
commentaire avec le symptôme qui les a provoquées. La refonte capitalise dessus.

Intouchable sans raison mesurée :

* **`Uninstall.swift` / `UninstallWindow.swift`** — translocation DMG
  (`SecTranslocateCreateOriginalPathForURL`), `trashItem` partout, `tccutil reset`,
  `launchctl bootout`, `SMAppService.unregister()`. **Zéro modification de logique.**
* **`Corpus.swift`** — 94 dictées et 248 Mo d'audio réels sur cette machine. Format
  en ajout seul, jamais réécrit. Le champ `storedOutcome: Outcome?` est optionnel
  **exprès** (`Codable` synthétisé lève `keyNotFound` au lieu de retomber sur une
  valeur par défaut) : toute évolution du schéma doit être **additive et optionnelle**.
* **`EngineChoice.swift`** — modèle famille/version (`macOS · Dictée`) et
  disponibilité **mesurée à l'exécution**. Plus juste que ce que décrivent les docs.
* **`DictationController.swift`** — les réglages sont *lus* au moment de servir,
  jamais recopiés (bug corrigé : changer de langue sans fermer les réglages
  transcrivait avec le mauvais modèle). `previewEngine` figé avec `previewText`
  (bug corrigé : une entrée du corpus portait le texte de la dictée suivante).
* **`SpeechAssets.swift`** — l'absence de guetteur sur `request.progress` est un
  **correctif**, pas un oubli. Voir §3.1.
* **`AppDelegate.warnIfNotInstalled()`** — le piège du double-clic depuis l'image
  disque, diagnostiqué à travers quatre pannes distinctes.
* **`SoflerSwitch`** — interrupteur dessiné à la main parce que `Toggle(.switch)`
  se désature quand la fenêtre perd le focus, et qu'un réglage activé se lisait
  alors comme désactivé sur le verre sombre.

---

## 3. Audit initial — contradictions relevées et arbitrages

### 3.1 ❌ La barre de progression 0-100 % des modèles Apple est impossible

`02_SPECIFICATIONS` §1.3 et `04_GUIDE_REFACTORING` §1 exigent une *« barre de
progression fluide 0–100 % »* pour le téléchargement `SpeechTranscriber`.

`SpeechAssets.swift` documente précisément le contraire, et c'est mesuré :
observer `request.progress` **fait échouer le téléchargement** avec
`Cannot check the download status, fr.lyriastudio.sofler is not subscribed to
transcription.fr`. L'erreur est apparue au commit qui a introduit le guetteur.
Deux correctifs ont été livrés à l'aveugle avant qu'on lise le message.

**Arbitrage :** on n'implémente pas la barre déterminée. L'encart affiche un
indicateur indéterminé **avec l'étape nommée** (`Téléchargement de Français…`),
ce qui répond au vrai besoin — savoir que quelque chose se passe — sans
réintroduire une panne déjà payée. À réévaluer si une API d'Apple le permet un jour.

### 3.2 ⚠️ Le passage à `fr-FR` couperait le corpus en deux

Les 94 entrées existantes portent `language: "fr"` (85) ou `"en"` (9). Les docs
imposent `selectedLanguages: ["fr-FR"]` et `primaryLanguage: "fr-FR"`.

Si le corpus se met à écrire `"fr-FR"`, un `groupby("language")` produit deux
groupes pour une même langue et **tout l'historique cesse d'être comparable au
présent** — exactement ce que la collecte existe pour permettre.

**Arbitrage (à valider) :** les préférences passent bien en BCP-47 en interne
(c'est nécessaire pour `SpeechTranscriber.supportedLocale` et pour 24 langues),
mais `CorpusEntry.language` **continue d'écrire le code court** (`fr`, `en`), et
un champ **`locale: String?`** optionnel est ajouté pour la locale complète.
Additif, rétrocompatible, et l'historique reste d'un seul tenant.

Migration de la clé `sofler.language` (`"fr"` → `"fr-FR"`) : faite une fois au
démarrage, dans `Preferences.init`, sur le modèle de la migration `triggerEnabled
→ triggerKind` déjà présente.

### 3.3 ❌ `01_ARCHITECTURE` §3 et `06_STRUCTURE` se contredisent sur les clés

Le tableau `@AppStorage` de `01` nomme `selectedLanguages`, `triggerMode`,
`finalTranscriptionEngine`, `dictationDestination`, `hasCompletedOnboarding`.
Les clés réelles — et celles de `06` — sont `sofler.languages.selected`,
`sofler.trigger.kind`, `sofler.engine`, `sofler.onboarded`.

**Arbitrage :** `06` fait foi. Et surtout : **aucun `@AppStorage` dans les vues.**
Tout passe par `Preferences.shared` (`@Observable`), parce que les `didSet`
portent des effets de bord indispensables — `EngineService.reconcile(needed:)` et
le `NotificationCenter.post(.soflerTriggerChanged)` qui reconstruit le tap clavier.
Un `@AppStorage` écrivant la même clé les court-circuiterait en silence.

### 3.4 ❌ `launchAtLogin` ne doit pas être une préférence stockée

`06` déclare `var launchAtLogin: Bool` persisté dans `UserDefaults`. Or
`LoginItemCard` relit `LoginItem.isEnabled` (donc `SMAppService`) **à chaque
affichage**, exprès : l'utilisateur peut révoquer le démarrage depuis Réglages
Système › Général › Ouverture sans prévenir l'application.

**Arbitrage :** `SMAppService` reste la seule source de vérité. `SettingsToggleRow`
reçoit un binding calculé, et recale l'interrupteur sur ce que le système a
réellement fait — pas sur ce qu'on lui a demandé.

### 3.5 ⚠️ Six onglets ne tiennent pas en 520 pt avec leurs icônes

`[Général][Enregistrement][Moteur IA][Lexique][Historique][Collecte]` sur une
ligne : ≈ 55 caractères à 12 pt semi-gras (~6,5 pt/car) = 358 pt, plus 6 × 24 pt
de marges = **502 pt**. Ça passe *tout juste*. Avec une icône SF Symbol par
onglet (+16 pt chacune) on monte à **598 pt** — au-delà des 520 pt utiles.

**Arbitrage :** la barre à six onglets abandonne les icônes et garde les
libellés seuls. Si la mesure réelle déborde, `Enregistrement` devient `Dictée`.

### 3.6 ❌ Le chemin du socket est faux dans la doc

`03_REGLES_SYSTEME` §4 annonce `/tmp/engine.sock` dans le schéma et
`/tmp/sofler-engine.sock` quatre lignes plus bas. Le chemin réel est
`~/Library/Caches/sofler/engine.sock` (`SocketSpeechEngine.defaultSocketPath`).

**Arbitrage :** on garde le chemin réel — `/tmp` est partagé entre utilisateurs et
n'a aucune raison d'accueillir un socket applicatif. La doc sera corrigée.

### 3.7 ❌ Trois modèles CrisperWhisper dans une doc, quatre dans l'autre

`01` §3 et `06` §1 listent `'small' | 'turbo' | 'large'`. `02` §5.3 et `04`
§3.ter en listent quatre. Le code (`CrisperWhisperModel`) en a **quatre** :
`small` (480 Mo), `medium` (1,53 Go), `turbo` (1,62 Go), `large` (3,09 Go).

**Arbitrage :** quatre. La grille 2×2 du prototype est d'ailleurs faite pour ça.

### 3.8 ✅ Le commit transactionnel des moteurs corrige un vrai bug

`02` §0.bis a raison, et le problème est réel aujourd'hui : `prefs.engine =
.crisperWhisper` est écrit immédiatement, même sans modèle téléchargé. La dictée
suivante appelle alors `SocketSpeechEngine` sur un service absent et échoue.

**Arbitrage :** adopté intégralement — sélection brouillon (`draft*`), commit
seulement à `.ready`, `lastValidEngine` pour le repli. C'est l'apport le plus
utile des documents.

### 3.9 ⚠️ Découpler live et final casse une propriété voulue

`04` §3.ter veut séparer `liveEngineTechnology` et `finalEngine`. Mais
`SpeechPreview.engine(writing:for:)` choisit aujourd'hui l'aperçu **d'après le
moteur d'écriture**, exprès : quand macOS écrit, l'aperçu emploie exactement la
même version et devient une vraie préversion du texte inséré.

**Arbitrage :** on découple, mais avec une règle qui préserve la propriété —
si `finalEngine == .apple`, l'aperçu suit la technologie Apple retenue pour le
final ; `liveEngineTechnology` ne devient réellement indépendant que lorsque
CrisperWhisper écrit (cas où il n'existe aucune préversion possible de toute façon).

### 3.10 ⚠️ Le menu barre : ne pas retirer l'indication de destination

`01` §2.ter et `02` §12 demandent de retirer toute la section « fichier de notes »
du menu. Le déplacement du *choix* vers `DestinationCard` est juste. Mais la
**ligne de statut** quand la destination est verrouillée sur un fichier est un
filet de sécurité : verrouillé, le texte n'apparaît plus là où l'utilisateur
regarde, et rien d'autre ne le lui dit hors dictée.

**Arbitrage :** on retire `Choisir…`, `Changer…`, `Revenir au curseur` et
`Pourquoi mon fichier n'est pas détecté ?` (ce dernier réapparaît dans les
Réglages). On **garde** la ligne non cliquable `▸ Écrit dans journal.md`.

### 3.11 ⚠️ Le `TrialSandbox` ne doit rien simuler

Le prototype React a un bouton `[ 🎙️ Simuler Touche Option ]` qui écrit un texte
factice. En natif, il n'y a rien à simuler : le champ d'essai de l'onboarding
actuel reçoit le texte **par le même chemin que n'importe quelle application**,
ce qui est précisément la preuve qu'on cherche à donner.

**Arbitrage :** `TrialSandbox` = un `TextEditor` réel + le vrai déclencheur, plus
le verrou `🔒` tant que micro et accessibilité manquent. Aucun bouton de simulation.

### 3.12 ⚠️ Vider le lexique par défaut change une mesure en cours

`02` §8 veut `lexicon = []` par défaut (argument juste : un médecin n'a que faire
de `useEffect`). Mais aujourd'hui `useDefaultLexicon = true` fait appliquer la
liste intégrée du moteur, et `Preferences` documente une mesure : à 36 termes le
modèle perd des virgules. Changer ce défaut **change la qualité de transcription
au milieu d'une collecte en cours**.

**Arbitrage (à valider) :** adopté pour les installations neuves uniquement, avec
le bouton `[ + Insérer des exemples (Développement Web) ]`. Le champ `lexicon` de
chaque entrée du corpus enregistre déjà ce qui a été envoyé : la rupture reste
traçable a posteriori.

### 3.13 ℹ️ `SetupRecoveryGuard` : ne pas détourner le clic sur l'icône

`01` §1.bis veut intercepter le clic sur l'icône de la barre des menus pour
rouvrir l'onboarding. Détourner ce clic empêche notamment de **quitter**
l'application.

**Arbitrage :** le menu s'ouvre toujours, mais réduit à deux lignes tant que
l'étape 3 n'est pas validée : `Terminer la configuration…` et `Quitter Sofler`.
L'interception vaut pour ⌘, et pour le déclencheur de dictée, pas pour le menu.

### 3.14 ℹ️ `07_IDEES_FUTURES_ENREGISTREMENT.md` — rien n'en sera codé

Isolement de la voix, ducking audio : hors périmètre, conformément à la consigne.

---

## 4. Découpage de l'exécution

### Bloc 0 — Socle (le seul bloc à risque sur les données)

* `SoflerTheme.swift` : tokens de `05_DESIGN_SYSTEM` (accent `#00e5cc`, cartes,
  typographie, rayons), en remplacement/extension de `Style`.
* Géométrie unifiée 580 × 700 pt, non redimensionnable, hauteur écrêtée à
  `visibleFrame.height - marge` pour les écrans courts.
* `Preferences` : `selectedLanguages` + `primaryLanguage` (BCP-47, jamais vide),
  migration `"fr"` → `"fr-FR"`, découplage `liveEngineTechnology` / `finalEngine`,
  `lastValidEngine`, commit transactionnel.
* `Corpus` : ajout de `appVersion: String?` et `locale: String?` (additifs et
  optionnels — cf. §3.2).
* `LanguageSwitchCoordinator` et `EngineSafetyManager` : la logique de repli
  aujourd'hui dispersée (le `didSet` de `Preferences.language`) est déplacée là,
  **pas dupliquée**.
* Catalogue de langues : construit dynamiquement depuis
  `SpeechTranscriber.supportedLocales` / `SFSpeechRecognizer.supportedLocales()`,
  `languages.json` ne servant que pour les libellés, drapeaux et tailles.

### Bloc 1 — Composants atomiques

`SettingsToggleRow`, `LanguagePicker`, `PrimaryLanguageSelector`, `UsageHabitsCard`,
`AppleEngineCard`, `CrisperEngineCard`, `TriggerCard`, `TrialSandbox`,
`FinalEngineCard`, `DestinationCard`, `UpdateCard`.

Chacun expose `isValid` et `ComponentValidationError?`, et porte un `#Preview` —
l'équivalent natif du bac à sable React.

### Bloc 2 — Onboarding 5 étapes

Assemblage de Bloc 1. `OnboardingStep` à 5 cas, `onboardingCurrentStep` persisté,
`SetupRecoveryGuard` (cf. §3.13), `CompletionView`.

### Bloc 3 — Réglages 6 onglets

Les **mêmes vues** que le Bloc 2, jamais une seconde implémentation. Plus le menu
de la barre épuré (cf. §3.10) et `UpdateNotificationSheet`.

### Bloc 4 — `RecordingOverlay`

Habillage seul : largeur fixe 440 pt dans les trois états, deux étages, badge
collecte ambré. `NSPanel` non activant, `LevelMeter` 30 Hz et `visibleTail`
**inchangés**. La bascule de langue en direct reste un simple **indicateur** tant
qu'il n'est pas prouvé que redémarrer le recognizer en plein flux est sans effet.

### Bloc 5 — `UninstallationView`

Habillage seul. `Uninstall.swift` : zéro modification.

---

## 5. Découvertes en cours de route

### 5.1 Le code court n'était pas une préférence, c'était une contrainte

L'arbitrage §3.2 — garder `fr` dans le corpus — avait été pris pour préserver la
continuité de l'archive. En câblant le socle, on a trouvé une **seconde raison,
indépendante et plus contraignante** : `engine/sofler_engine/prompt.py` compose
le jeton Whisper `<|{language}|>` pour imposer la langue au décodeur.
`<|fr-FR|>` n'existe pas dans le vocabulaire du modèle ;
`convert_tokens_to_ids` rendrait le jeton inconnu et le préfixe de décodage
forcé partirait corrompu — **sans lever la moindre erreur**. La transcription
continuerait, simplement moins bonne.

C'est le mode de panne le plus coûteux pour ce projet : une dégradation muette
au milieu d'une collecte dont le seul objet est de mesurer la qualité.

**Conséquence architecturale :** la locale complète circule partout (les modèles
de macOS sont fournis par région), et la conversion vers le code court se fait à
**un seul endroit**, la frontière du socket, avec la raison écrite sur place.

### 5.2 Le schéma du corpus est monté dans `SoflerCore`

`CorpusEntry` et `CorpusTranscription` ont quitté `Corpus.swift` pour
`Sources/SoflerCore/CorpusEntry.swift`. Motif : `SoflerCore` est la cible sans
dépendance système, donc la seule **testable** — et la règle de
rétrocompatibilité du corpus (tout champ ajouté doit être optionnel, sinon
`keyNotFound` rend illisible l'historique entier) ne valait jusqu'ici que par un
commentaire. Elle est désormais vérifiée à chaque `swift test`.

Le reste de `Corpus` (écriture JSONL, fichiers audio, statistiques) demande
AppKit et AVFoundation et reste côté application.

### 5.3 Le repli de moteur ne réécrit jamais la préférence

`EngineSafetyManager.effectiveEngine` supplée un moteur momentanément incapable
d'écrire, mais **ne touche pas au réglage**. Quelqu'un qui a choisi
CrisperWhisper et dont le service est arrêté doit retrouver CrisperWhisper quand
il redémarre, pas découvrir que l'application a décidé à sa place. Le corpus,
lui, archive le moteur qui a **réellement** écrit — sinon il mentirait sur la
seule chose qu'il sert à mesurer.

---

### 5.4 La validité ne passe pas par un `@Binding`

Les docs décrivent `@Binding var isValid: Bool` en **sortie**, le composant y
écrivant depuis son corps. C'est un `useEffect` React transposé littéralement,
et SwiftUI le refuse : écrire dans un binding pendant l'évaluation d'une vue
déclenche « Modifying state during view update ».

Le fond du problème est que la validité n'est pas un état mais une
**conclusion**, tirée de sources qui existent déjà (`PermissionsMonitor`,
`SpeechAssets`, `Preferences`, `EngineService`). La stocker une seconde fois
recrée l'occasion de divergence que ce projet a déjà payée.

Chaque composant expose donc une fonction pure `validate()` que le parent
appelle aussi. Les deux lisent les mêmes sources : ils ne peuvent pas
diverger, et il n'y a rien à synchroniser.

### 5.5 Deux contradictions supplémentaires tranchées

* **Validité et langues secondaires.** Doc 02 §1 exige que *toutes* les langues
  retenues aient leur modèle ; §0.quater dit que seule la langue active
  décide. C'est §0.quater qui a raison — bloquer quelqu'un sur un modèle
  espagnol dont il se servira dans trois semaines n'a aucune contrepartie. Les
  modèles secondaires sont **proposés, jamais exigés**.
* **`LaunchAtLogin` dans `DestinationCard`.** Doc 02 §6 l'y place, doc 01
  §2.bis en fait une section distincte. Le second a raison : le démarrage
  automatique ne dit rien de la destination du texte.

### 5.6 Ce qui reste à reprendre dans les blocs suivants

* **`FeatureSwitch` et `SettingsToggleRow` font double emploi.** Le second est
  un sur-ensemble (description, note, `disabled`, `isCard`). Les six sites
  d'appel de `FeatureSwitch` sont dans les onglets que le Bloc 3 réécrit :
  la conversion s'y fera, plutôt que de créer de la turbulence maintenant.
* **`PermissionsChecklist`** n'est plus utilisée que par l'accueil, que le
  Bloc 2 réécrit avec `TriggerCard`. Elle disparaîtra à ce moment-là.

---

## 6. Journal

| Date | Bloc | Fait |
| :--- | :--- | :--- |
| 2026-08-18 | — | Audit initial. Base : `swift build` propre, `swift test` vert (30), corpus à 94 dictées / 248 Mo. |
| 2026-08-18 | 5 | Désinstallation alignée sur la géométrie commune, bouton destructif en rouge. Accent unifié : quatre surfaces AppKit tenaient encore `systemTeal`. `Uninstall.swift` inchangé. |
| 2026-08-18 | 4 | Barre d'enregistrement à largeur fixe 440 pt dans les trois états, indicateur de langue, teintes alignées. Mécanique `NSPanel`/`LevelMeter`/`visibleTail` inchangée. |
| 2026-08-18 | 3 | Réglages à six onglets sans icônes (mesure : ~598 pt avec, pour 520 pt utiles). Menu épuré, ligne de destination conservée. `FeatureSwitch` supprimé, 3 sites convertis. |
| 2026-08-18 | 2 | Onboarding refondu en 5 étapes assemblant les composants. `SetupRecoveryGuard`, étape persistée. `PermissionsChecklist` supprimée (`PermissionsView` 321 → 149 lignes). |
| 2026-08-18 | 1 | 11 composants livrés, chacun avec son `validate()` et son `#Preview`. `PreferencesWindow` 647 → 429 lignes, `TranscriptionSettings` 224 → 25. `swift test` : **49 tests, 7 suites**. |
| 2026-08-18 | 0 | Socle livré. `Language` (39 locales), `Preferences` multi-langues + migration `fr`→`fr-FR`, découplage `finalEngine`/`appleTechnology`/`liveEngineTechnology`, `EngineSafetyManager`, `LanguageSwitchCoordinator`, schéma corpus dans `SoflerCore` + `locale`/`appVersion`, tokens de design, géométrie 580×700 écrêtée. |

### Vérifications du Bloc 0

* `swift build` — zéro erreur, **zéro avertissement**.
* `swift test` — **38 tests, 6 suites**, verts (8 nouveaux sur le schéma du corpus).
* **Corpus réel décodé avec le nouveau type : 94 lues, 0 illisibles**, 69 min,
  `fr: 85 / en: 9` — chiffres identiques au relevé d'avant modification.
  *(Les deux fichiers `sessions.jsonl.avant-*` restent illisibles : ce sont des
  instantanés de l'ancien schéma par moteur — `textApple`, `textIntended` — déjà
  convertis dans `sessions.jsonl`, et illisibles bien avant cette refonte.)*
* Migration vérifiée sur cette machine : région `FR` détectée, `fr` → `fr-FR`,
  `fr-CA` préservé tel quel, langue hors catalogue affichée via `Locale` au lieu
  de disparaître de l'interface.
* Réglages réels relus : `sofler.lexicon.useDefault = true` est **explicitement
  stocké**, donc préservé — le nouveau défaut à liste vide ne vaut que pour les
  installations neuves, comme arbitré.

> **Note sur la granularité des commits :** le socle forme un seul commit.
> Transformer `Preferences.language` en propriété calculée impose de reprendre
> tous ses sites d'appel dans le même mouvement ; le découper produirait des
> commits intermédiaires qui ne compilent pas. Les blocs suivants sont
> naturellement atomiques — un composant par commit.

---

## 7. Ce qui reste à vérifier

Tout est compilé, testé et commité, mais **rien n'a encore été exécuté** : les
builds SwiftUI passent sans garantir qu'une mise en page tienne à l'écran.

```bash
./scripts/install.sh
```

Compile depuis la copie de travail, signe avec le certificat de développement
**stable** de `dev-cert.sh` — donc l'autorisation d'accessibilité survit aux
réinstallations, contrairement aux releases signées ad hoc — installe dans
`/Applications/Sofler.app` et relance.

### Ce que le premier lancement va faire

La migration écrit `sofler.languages.selected = ["fr-FR"]`, `sofler.engine.final`,
`sofler.engine.apple`, `sofler.engine.live`, `sofler.engine.lastValid`,
`sofler.dictation.destination` et `sofler.schema.migrated`.

Elle **ne supprime rien** : `sofler.language` et `sofler.engine` restent en
place. Revenir à un build antérieur relit les anciennes clés et retrouve le
comportement d'avant.

### À regarder en priorité

1. **La barre d'onglets des Réglages** — la mesure donne ~502 pt sur 520 pt
   utiles, c'est la marge la plus étroite de toute la refonte.
2. **L'onboarding à l'étape 3** — la plus chargée : `TriggerCard` avec zone
   d'essai plus `AppleEngineCard`. Vérifier qu'elle ne déborde pas des 700 pt.
3. **Une dictée réelle de bout en bout**, puis que `sessions.jsonl` porte bien
   `language: "fr"` **et** `locale: "fr-FR"` sur la nouvelle ligne.
4. **La barre d'enregistrement** dans ses trois états, pour confirmer que la
   largeur ne bouge plus.

## Passe visuelle sur les six onglets de réglages — fd8de72

Vérifiée écran par écran, pilotée par capture d'écran plutôt qu'à l'œil.

**Corrigé**
- Onglets : `Text` + `onTapGesture` → vrais `Button` (clavier + VoiceOver).
- `PageHeader.Scale` : 18/14 pt en onglet, 24/20 pt en onboarding.
- Marge de 12 pt portée par la carte, plus par le conteneur.
- Zone de contenu remise à 26/30/24, soit 520 pt utiles.
- `followsHeader` sur le premier libellé de section (Général + Dictée).
- Aperçu en direct scindé en deux cartes.
- Titre en double retiré du lexique.
- Bouton primaire désactivé : estompé, plus repeint en gris.

**Vérifié conforme, aucun changement**
- « Retours Sonores » existait déjà (hors champ à la capture).
- Zone de dépôt du fichier de notes toujours visible : c'est le seul chemin de
  configuration, et la pastille « Fichier de notes » reste verrouillée sans
  fichier (infobulle incluse).
- Moteur IA, Historique, Collecte : conformes.

**Écarts assumés vis-à-vis du prototype**
- Icônes SF Symbols à la place des emoji dans la barre d'onglets et sur
  « Gérer / Ajouter des langues… » (demande explicite).
- Chevron rotatif au lieu du glyphe `▲`.
- « Téléchargement de *Français*… » nomme la langue, là où le prototype reste
  générique.

**Reste à faire**
- Passe équivalente sur l'onboarding.
- Matrice des 4 bannières de `LanguageSwitchService` (« Fermer cette
  notification »).
- `LanguageSwitchCoordinator.audit()` écrit `prefs.appleTechnology` — à rendre
  non mutant (constat S1).
- `RecordingOverlay` : la pastille de langue est un sélecteur à gauche en
  multilingue macOS, un simple indicateur au centre sous CrisperWhisper.
- `UpdateNotificationModal`, `InstallPromptModal` : absents du Swift.
- Rebranding Caspr.

## Passe visuelle sur l'accueil — e64c5b8

**Corrigé**
- Titre de fenêtre figé sur « Bienvenue dans Sofler » à la reprise (bug de
  capture : le rappel visait une variable affectée trop tard). `Step.resumed`.
- Compteur d'étapes remonté dans la barre de titre : 48 pt de bande morte.
- `PageHeader.Scale.summary` pour l'écran final (18 pt, 2 pt, 2 pt).
- Premier libellé de section sans marge haute, comme dans les réglages.
- Puces des astuces : emoji → symboles SF.
- Noms d'accessibilité sur les deux boutons du pied de page.

**Vérifié conforme, aucun changement**
- Liste de langues coupée en bas : c'est `max-height: 125px`, l'affordance de
  défilement du prototype.
- Étapes 1 à 4 : marges et wording conformes.

**Écart assumé**
- Libellés de section à 16 pt partout, là où le prototype alterne 16 et 12.

## Constat S1 clos + bannières de bascule — ea3d5d6

**Corrigé**
- `audit()` n'écrit plus `appleTechnology`. Redondant (`EngineSafetyManager`
  replie déjà au moment de dicter) et destructeur (le choix était perdu sans
  retour). Vérifié : plus aucune écriture automatique de la préférence.
- Contrôle du modèle manquant mesuré sur la version *effective*.
- Bandeau : titre du prototype, bouton de fermeture, action « Configurer dans
  Moteur IA » enfin portée par un bouton (`selectSettingsTab`).
- Récapitulatif de l'accueil : moteur effectif, plus la préférence.

**Non vérifié visuellement**
Le bandeau lui-même : le reproduire demanderait de changer la configuration de
langues de la machine. Compilé et câblé, mais pas exercé à l'écran.

**Arbitrage confirmé, aucun changement**
Le prototype a deux réglages libres (`liveEngineTechnology`,
`finalAppleTechnology`). Le Swift couple l'aperçu à la passe finale dès que
macOS écrit, pour que l'aperçu soit une vraie préversion du texte inséré. Les
quatre cas de bannières restent atteignables.

**Reste à faire**
- `RecordingOverlay` : pastille de langue (sélecteur à gauche en multilingue
  macOS, indicateur au centre sous CrisperWhisper).
- `UpdateNotificationModal`, `InstallPromptModal`.
- Rebranding Caspr.

## Reprise du prototype comme spécification — 0a7a15a, e9eda2c

Relecture intégrale de `SoflerContext.jsx`, `LanguagePicker.jsx`,
`AppleEngineCard.jsx`, `FinalEngineCard.jsx`, `LanguageSwitchService.js` et la
section langue de `SettingsView.jsx`. Six divergences de **comportement**.

**Corrigé**
1. Aperçu et transcription : deux technologies indépendantes (`target`).
   Seul point de contact restant : l'accueil pose la même des deux côtés tant
   que celle de la transcription n'a jamais été choisie
   (`finalTechnologyWasChosen`).
2. `primaryLanguage` stockée à part de l'ordre de la liste. Plus de
   permutation des pastilles. Migration : `languages[0]` repris tel quel.
3. Bannière dérivée au lieu de stockée + sondage de l'inventaire au changement
   de langue → elle apparaît immédiatement. Fermeture par identité suffixée de
   la langue.
4. Sélecteur de langue retiré de l'onglet Moteur IA.
5. Ligne du haut : « Langue active : » à gauche, sélecteur à droite. Note
   corrigée (« la première est celle avec laquelle Sofler dicte » était devenu
   faux).
6. `SpeechPreview.make` prend la technologie de l'aperçu, plus celle du moteur
   d'écriture. Idem pour la permission de reconnaissance vocale.

**Au passage**
`PillPicker` : `Text` + `onTapGesture` → vrais boutons. Portait le choix de la
langue, de la destination et de la version du moteur.

**Vérifié à l'écran**
- Bascule de langue sans permutation.
- Aperçu sur « Dictée » et transcription sur « Apple Intelligence »
  simultanément (clé `sofler.engine.live` posée puis retirée).
- Rien n'utilise `languages[0]` hors de l'invariant interne ; le chemin de
  dictée et l'aperçu passent par la langue principale.

**Non exercé**
- Le cas d'auto-alignement de l'accueil : la clé existe déjà sur cette machine,
  donc la condition est fausse.
- La bannière elle-même (demande une langue sans modèle installé).

## Prise en charge des langues par Apple Intelligence — 12c1c10, 804827f

**La cause racine**
`SpeechTranscriber.supportedLocale(equivalentTo:)` n'est **pas** un test
d'appartenance. Mesuré : rend `pl_PL`, `ru_RU`, `ar_SA`, `vi_VN` alors
qu'aucune n'est dans `supportedLocales` (30 locales / 10 langues ici). Toute la
chaîne s'y fiait.

**Corrigé**
- Appartenance testée sur `supportedLocales` elle-même.
- `EngineChoice.isAvailable(for:)` consulte enfin la langue
  (`Language.appleSupports`, mémorisée avec verrou car lue hors MainActor).
- Identifiants normalisés (`fr_FR` → `fr-FR`) : la taille du modèle ne
  s'affichait dans aucune ligne, et « indisponible ici » jamais.
- Balayage des langues déclarées au démarrage.
- `estimatedSizeLabel` : « 62 Mo », plus « 62 MB ».
- Message de bascule aligné sur le prototype.
- Lignes du catalogue : `onTapGesture` → vrais boutons.

**Testé à l'écran**
- Polonais secondaire → aucun téléchargement proposé, aucun changement de moteur.
- Polonais principal → bannière immédiate, sans changer d'onglet.
- Espagnol principal (pris en charge, non téléchargé) → bannière + bouton de
  téléchargement.
- Fermeture de la bannière.

**Non reproductible ici**
Repli propre vers Dictée : demande une langue qu'Apple Intelligence ignore mais
que la Dictée a installée ; ce Mac n'a que en/fr côté Dictée.

## Barre d'écoute : bascule de langue — 29ff06f

L'indicateur devient un sélecteur. Mon objection (« redémarrer le recognizer en
pleine dictée ») était fausse : l'audio est transcrit à la fin, la langue est
lue à ce moment-là. Trois cas du prototype respectés. Vérifié à l'écran.

**Reste à faire**
- `UpdateNotificationModal`, `InstallPromptModal` : absents du Swift.
- Rebranding Caspr (nom, dépôt, `.dmg`, icônes, site).

## Moteurs, modèles et service local — 426e813 → c35bb79

**Bugs corrigés**
- `EngineService.isRunning` lançait un `launchctl` synchrone à chaque lecture
  de `step`, plusieurs fois par rendu → fil principal noyé pendant le
  démarrage. Mémoire d'une seconde.
- La vue cessait de se redessiner : `phase` passait à `.done` sans que rien ne
  suive. Les états viennent de fichiers, de launchd et d'un socket — rien
  d'observable. Sondage à 2 Hz tant que l'état n'est pas stable.
- `commitIfReady` ne se déclenchait qu'au clic : le choix de CrisperWhisper ne
  s'enregistrait jamais, et au changement d'onglet macOS réapparaissait.
- `effectiveEngine` repliait sur `isAvailable` (= « installé »), donc jamais
  quand le service était arrêté : la dictée partait vers un socket fermé et
  échouait sur « le modèle est en cours de chargement », ce qui était faux.
- Le service survivait à la fermeture de l'application : 3 Go résidents
  jusqu'au redémarrage de la machine.
- Historique vide à l'ouverture (`entries` jamais chargé).
- `AccentCard` sans marge basse.

**Comportements posés**
- `chosenCrisperModel` : mémoire du modèle retenu (téléchargé ou démarré au
  moins une fois). Parcourir la grille ne retient rien.
- Quatre sections dans la carte CrisperWhisper : explication, rendu, modèle
  (grille **ou** modèle retenu + changer/supprimer), action.
- Verrou sur les autres modèles pendant toute opération, partout.
- « Libérer la mémoire » fait suivre le réglage sur macOS, avec confirmation ;
  l'affichage reste épinglé sur CrisperWhisper jusqu'à la prochaine ouverture.
- Fenêtre de démarrage quand CrisperWhisper charge encore au lancement.

**Service central de compatibilité**
`LanguageSwitchCoordinator` raisonne sur *qui écrit* et couvre les deux
familles (CrisperWhisper : couverture, poids, service ; macOS : version,
modèle). Dérivé, non mutant. Affiché par `EngineNoticeBanner` dans Général
**et** Moteur IA.

**Reste à faire**
- Cartes de choix du moteur : `onTapGesture` → vrais boutons (clavier,
  VoiceOver, automatisation).
- `EngineBootstrap.obstacle` consulté seulement après le clic.
- Aucune vérification d'espace disque avant 1,6–3 Go de téléchargement.
- Couverture CrisperWhisper en dur dans `Language.swift` : à sortir en JSON.
- Titre de l'onglet « Enregistrement & Dictée » → proposition « Dictée &
  Aperçu ».
- `UpdateNotificationModal`, `InstallPromptModal`.
- Rebranding Caspr.
