# 🔬 09 — Analyse du prototype React, composant par composant

> Relevé exhaustif de ce que fait le prototype, de ce que fait le Swift actuel,
> et de l'écart. Écrit après avoir lu **tout** le prototype — la première
> tentative de portage n'en avait lu que des fragments, et le résultat s'en
> ressentait.
>
> Colonne « arbitrage » : ce qu'on retient, et pourquoi. Le prototype fait foi
> pour l'UI, l'UX et le wording. Le Swift fait foi quand il porte une contrainte
> système que le prototype ne pouvait pas connaître.

---

## 0. Ce que la lecture complète a changé

Trois choses n'étaient pas devinables sans lire les fichiers d'assemblage :

1. **Les en-têtes de page vivent dans `App.jsx` et `SettingsView.jsx`**, pas
   dans les composants. Chaque écran a son `h1` + sa phrase d'introduction.
2. **Il existe un `services/LanguageSwitchService.js`** — 166 lignes de matrice
   de repli que je n'avais pas vues, et qui est plus fine que mon
   `LanguageSwitchCoordinator`.
3. **Il existe un `components/logo-system/`** (Caspr) et un
   `InstallPromptModal.jsx` absents de mon relevé initial.

---

## 1. `CrisperEngineCard` — le composant le plus dense

### Machine à états, dérivée de trois booléens

```
crisperEnvReady ── non ──> engineMissing
      │ oui
isModelDownloaded(crisperModel) ── non ──> modelMissing
      │ oui
activeLoadedModel == crisperModel ── non ──> serviceStopped
      │ oui
    ready
```

**Point clé :** l'état est calculé **pour le modèle sélectionné**, pas
globalement. Sélectionner un modèle non téléchargé fait retomber en
`modelMissing` même si un autre modèle est prêt et chargé.

### Vue compacte vs catalogue déployé

Compacte **seulement si** `!isOnboarding && !catalogueExpanded && step == ready
&& !installing`. Sinon, catalogue complet.

* **Compacte** — deux colonnes :
  * gauche, 2 lignes : point turquoise lumineux + `Prêt` + `· Modèle {nom}` /
    `{ram} alloués en mémoire vive · Service actif`
  * droite, 2 lignes : bouton `Changer de modèle…` / lien discret
    `Supprimer ce modèle ({taille})`, qui **devient rouge au survol**
* **Catalogue** — en-tête `Modèle d'IA locale (~10 langues incluses)` +
  `Mémoire : {ram}` à droite, puis grille **2×2**.

### Grille 2×2 des modèles

Par carte : nom, badge `Installé ✓` **ou** taille de téléchargement, puis
`RAM : {ram} · {vitesse}`. Bouton `Supprimer ({taille})` en pied de carte
**uniquement si `!isOnboarding && isDownloaded`**.

Les quatre modèles, avec les libellés exacts :

| id | nom affiché | dl | RAM | vitesse |
| :-- | :-- | :-- | :-- | :-- |
| `turbo` | `Turbo ★ (Recommandé)` | 1,62 Go | ~3 Go | Ultra-rapide (210 ms) |
| `small` | `Small (Léger)` | 488 Mo | ~1,5 Go | Rapide (410 ms) |
| `medium` | `Medium (Équilibré)` | 1,53 Go | ~3,5 Go | Équilibré (690 ms) |
| `large` | `Large (Précision Max)` | 3,09 Go | ~6 Go | Intensif (1200 ms) |

### Verrouillage pendant l'installation (Onboarding)

```js
isLockedInOnboarding = isOnboarding && (installing || step === 'ready')
                       && !installError && !isSelected
```

→ `opacity 0.45`, `grayscale(0.6)`, clic ignoré.

**`&& !installError` est le détail qui compte :** dès qu'une erreur survient,
tous les modèles se **déverrouillent**, pour pouvoir en choisir un autre plutôt
que rester coincé sur celui qui échoue. C'est exactement le genre de cas
particulier que le prototype existe pour fixer.

### Licence Nyra Health

Case à cocher qui **désactive le bouton d'installation** tant qu'elle n'est pas
cochée. Affichée systématiquement en `engineMissing`, et en `modelMissing`
**seulement si pas encore acceptée**.

### Libellés d'action, qui changent selon l'état du disque

* `engineMissing` + modèle déjà téléchargé → `Installer l'environnement (~1,2 Go)`
* `engineMissing` + rien → `Installer CrisperWhisper (2,82 Go (uv/python 1,2 Go + modèle 1,62 Go))`
* `modelMissing` → `Télécharger les poids (1,62 Go)`
* `serviceStopped` → `Démarrer le service`
* `ready` → badge + `Arrêter (Libérer RAM)`

### Section « Rendu », toujours en haut

Pill picker `Texte nettoyé` / `Mot à mot`, et **le paragraphe d'explication
change selon le mode sélectionné** (deux textes distincts).

### 🔴 Écart avec mon portage Swift

Mon `CrisperEngineCard` enveloppe `CrisperWhisperSetup` et n'a **rien** de tout
ceci : ni la grille 2×2, ni la vue compacte, ni le verrouillage, ni le
déverrouillage sur erreur, ni les libellés conditionnels. À refaire entièrement.

---

## 2. `FinalEngineCard`

Deux `.choice-card` avec `radio-circle`, titre `h3`, badge
`★ Conseillé pour vous` (si `showRecommendations`), description, puis panneau de
détail révélé **seulement quand la carte est sélectionnée**, séparé par un filet.

* macOS : `macOS (Natif)` — « Fourni par macOS : aucune licence, aucun compte,
  rien à installer, et rien ne réside en mémoire entre deux dictées.
  **0 Mo de RAM résidente**. »
* Crisper : `CrisperWhisper 2.0 (IA Multilingue & Code)` — « Deuxième passe
  intelligente par IA locale : comprend le **Franglais sans changer de langue**,
  respecte le **vocabulaire technique et le code** (`useEffect`, variables) et
  nettoie les hésitations (*euh*). »

`showRecommendations` vaut `isOnboarding` par défaut — donc masqué dans les
Réglages.

---

## 3. `AppleEngineCard`

* `isSubCard` → rendu nu dans `.choice-detail`. Sinon → `.choice-card.selected`
  avec `cursor: default` et un en-tête statut + titre + description.
* Titre : `macOS · Apple Intelligence` / `macOS · Dictée` /
  `macOS · Dictée (Mac Intel)`.
* `isCardOk = technology == 'apple' ? isPrimaryLanguageInstalled : speechGranted`
* Sélecteur de version **masqué** si `isLegacyOrIntel`.
* Trois états de téléchargement :
  1. tout installé → `✓ Modèles de langue installés (Français, English)`
  2. principale installée, d'autres manquantes → encart **non bloquant** avec
     `✓ Modèle de langue active (Français) prêt` + bouton secondaire
     `Télécharger tout (X Mo)`
  3. principale manquante → encart d'action + **barre de progression 0-100 %**
* Bloc reconnaissance vocale si `appleLegacy || isLegacyOrIntel`.

### ⚖️ Arbitrage conservé : pas de barre déterminée

`SpeechAssets.swift` documente que lire `request.progress` **fait échouer** le
téléchargement. On garde l'indicateur indéterminé + l'étape nommée. C'est le
seul endroit où le Swift l'emporte sur le prototype pour une raison mesurée.

---

## 4. `SettingsView` — six onglets

### La barre d'onglets **a** des icônes

Conteneur `border-radius: 10px`, fond `rgba(0,0,0,0.35)`, `padding: 3px`,
`max-width: 560px`, `width: 100%`. Chaque bouton : `flex: 1`, `padding: 6px 8px`,
`font-size: 11.5px`, `border-radius: 7px`, icône 12 px + libellé, actif =
`accent-dim` + bordure `accent-border`.

**Je m'étais trompé** en concluant qu'il fallait retirer les icônes : elles
tiennent parce que la police est à 11,5 px et le padding à 8 px, pas 12.
`Enregistrement` reste le libellé le plus long et doit être vérifié à l'écran.

### En-têtes par onglet (`h1` à 18 px + `p`)

| onglet | titre | sous-titre |
| :-- | :-- | :-- |
| Général | Réglages Généraux | Langue de travail, destination du texte transcrit et intégration système. |
| Enregistrement | Enregistrement & Dictée | Configurez comment Sofler capte votre voix et affiche la transcription en direct. |
| Moteur IA | Moteur IA & Transcription Finale | Choisissez le moteur neuronal qui rédige le texte définitif de votre dictée vocale. |
| Lexique | Lexique & Mots Métier | Personnalisez le dictionnaire local pour garantir l'orthographe exacte de vos termes clés. |
| Historique | Historique des Dictées | Retrouvez et copiez vos dernières transcriptions locales en un clic. |
| Collecte | Collecte & Comparatif Moteurs | Archivez localement vos enregistrements pour mesurer et comparer la précision de chaque IA. |

### Onglet Général

`Langue Principale de Dictée` → carte avec `Langue active :` + pill picker
(≤ 2 langues) ou `<select>` stylé turquoise (≥ 3), puis une ligne
note + bouton `⚙️ Gérer / Ajouter des langues...` / `▲ Masquer le catalogue`,
puis les **bannières de repli**, puis le message de confirmation, puis le
catalogue déplié.

Note adaptative : `La langue principale pilote la reconnaissance vocale.` (≤ 2)
vs `Vous avez N langues actives configurées.` (≥ 3).

Puis `Destination des Dictées`, `Mises à jour du Logiciel`,
`Démarrage & Système`.

### Onglet Enregistrement

`Déclencheur & Permissions` → `TriggerCard(showTrialSandbox: false)`.
`Aperçu du texte en direct (Live Preview)` → toggle
`Afficher les mots prononcés en temps réel`, avec une **note qui n'apparaît que
si désactivé** : « L'aperçu textuel est masqué. La barre flottante affichera
uniquement les ondes sonores pendant la parole. »
Si activé → `AppleEngineCard(isSubCard: false, target: live)`.
Puis `Retours Sonores`.

---

## 5. `LanguageSwitchService` — la matrice de repli

Audite **séparément** le moteur live et le moteur final, puis consolide en
0..n bannières. Quatre cas :

| cas | condition | titre de bannière | action |
| :-- | :-- | :-- | :-- |
| A | live ET final replient, final = apple | Bascule sur macOS Dictée (Aperçu Live & Moteur Final) | télécharger modèle |
| B | live seul replie | Aperçu Live : Bascule sur macOS Dictée | télécharger modèle |
| C | final seul replie, crisper | Moteur Final : Bascule sur macOS Natif (0 Mo) | naviguer vers Moteur IA |
| C' | final seul replie, apple | Moteur Final : Bascule sur macOS Dictée | télécharger modèle |
| D | live replie ET crisper pas prêt | Bascule sur macOS Dictée & macOS Natif | télécharger modèle |

Chaque bannière est **fermable** (`dismissedBanners`) et porte un `id` dérivé de
la langue, donc réapparaît si l'on rebascule.

### ⚖️ Ce que le prototype fait mieux que mon Swift

Il **calcule un effectif sans jamais muter l'état**. Mon
`LanguageSwitchCoordinator.audit()` écrit `prefs.appleTechnology = usable` —
ce qui contredit le principe que j'ai moi-même posé dans `EngineSafetyManager`
(« le repli ne réécrit jamais la préférence »). **À corriger : le coordinateur
doit devenir une pure évaluation.**

---

## 6. `HistoryView`

* Master toggle `Conserver l'historique des dictées` + note si désactivé.
* Carte de détail **bordée d'accent** et légèrement teintée.
* Sélecteur de capacité `[5 | 10 | 20 | 50]` avec texte dynamique.
* Lignes : texte tronqué 1 ligne + infobulle, âge relatif, bouton copier qui
  devient `✓ Copié` pendant 1,5 s.
* Pied : `Effacer l'historique` en rouge (désactivé si vide) +
  `Seul le texte est conservé · 0 Mo d'audio stocké`.

**Swift actuel :** limite figée à 5 (`static let limit = 5`). Le sélecteur
5/10/20/50 est à ajouter, avec troncature non destructive à la baisse.

---

## 7. `VocabularyView`

* Carte 1 explicative, carte 2 bordée d'accent avec la gestion.
* Champ + bouton `+ Ajouter` (désactivé si vide), validation `Entrée` ou `,`,
  collage de listes séparées par virgules/retours.
* Tags **rectangulaires** (rayon 6 px, pas des pilules), `✕` rouge au survol.
* État vide : `Aucun terme personnalisé. Sofler transcrit en français courant
  sans conditionnement.` + `+ Insérer des exemples (Développement Web)`.
* Pied : compteur, avertissement ambre si > 25, `Tout effacer` rouge.
* Liste d'exemples du prototype : `useEffect, useState, React, Next.js,
  TypeScript, props, state, refactor, pull request, endpoint, async, await,
  Docker, Kubernetes` — **diffère** de `Preferences.starterLexicon` côté Swift.

---

## 8. `CollectView`

* Master toggle `Archiver mes dictées (Collecte & Comparatif)`.
* Si activé : toggle audio (`isCard: false`), séparateur, section moteurs.
* **Apple Intelligence est masqué si `isLegacyOrIntel`** (rendu conditionnel).
* **CrisperWhisper est grisé et non cliquable si `!isCrisperReady`**, avec un
  libellé qui change : `CrisperWhisper 2.0 — non téléchargé (indisponible)`.
* Encart statistiques : badge `N dictées · ~X min · Y Mo`, puis
  `Format JSON Lines · Version active de l'app : v0.8.0`.
* `📂 Afficher dans le Finder` + `Tout effacer` rouge, avec **confirmation**.

### ⚖️ Divergence à trancher

Le Swift **liste** les moteurs indisponibles au lieu de les masquer, avec un
commentaire qui défend ce choix : « savoir qu'une version n'existe pas sur cette
machine est une information, une ligne absente n'en est pas une. »

Le prototype masque Apple Intelligence et grise CrisperWhisper. **Retenu : la
demi-mesure du prototype pour Crisper (grisé + libellé explicite) est meilleure
que la mienne ; le masquage complet d'Apple Intelligence est moins bon.** On
grise tout, on ne masque rien.

---

## 9. `DestinationCard`

* Pill `Au curseur` / `Fichier de notes`, le second **grisé et non cliquable**
  tant qu'aucun fichier n'est configuré, avec infobulle explicative.
* Zone fichier **toujours visible**, deux états :
  * sans fichier : zone en **pointillés** qui s'illumine au survol de dépôt,
    icône 📄 32×32, deux boutons `+ Choisir un fichier…` et `Saisir nom…`
  * avec fichier : encart dont l'apparence **dépend du mode actif** —
    teinté turquoise + bordure accent si `notes` est actif, sombre sinon ;
    sous-titre `Destination active · Ajout en fin de fichier` vs
    `Fichier configuré (mode veille)` ; boutons `Modifier…` et `✕ Retirer` rouge
* Le **dépôt fonctionne dans les deux états**.
* Note finale à **trois** variantes (curseur sans fichier / curseur avec fichier
  mémorisé / notes).
* Mentionne « ajoutée à la fin de X **avec horodatage** » → à vérifier côté
  `TargetWriter`.

Le `launchAtLogin` déclaré dans ce composant n'est **jamais utilisé** — code mort
du prototype. Confirme que doc 01 a raison contre doc 02 : le démarrage est une
section à part.

---

## 10. Reste à lire

`RecordingOverlayView` (558), `UninstallationView` (457),
`UpdateNotificationModal` (272), `UpdateCard` (269),
`InstallPromptModal` (195), `logo-system/*`.

---

## 11. `RecordingOverlayView` — la rangée d'onglets est **conditionnelle**

C'est là que je m'étais le plus trompé. La rangée du bas n'a pas trois places
fixes : sa composition dépend du moteur **et** du nombre de langues.

| moteur final | langues actives | gauche | centre | droite |
| :-- | :-- | :-- | :-- | :-- |
| CrisperWhisper | quelconque | `Texte nettoyé \| Mot à mot` | **indicateur** `🇫🇷 FR` | `Curseur \| Notes › x` |
| macOS | ≥ 2 | **bascule** `🇫🇷 FR \| 🇬🇧 EN` (max 3) | — | `Curseur \| Notes › x` |
| macOS | 1 | *(rien)* | — | `Curseur \| Notes › x` |

Autrement dit : la pastille de langue est un **sélecteur à gauche** sous macOS
multi-langues, et un **indicateur au centre** sous CrisperWhisper. Mon portage
l'avait mise systématiquement au centre, en indicateur — donc faux dans les deux
cas.

### ⚖️ La bascule de langue en direct : arbitrage révisé

`02_SPECIFICATIONS` §14.3 me déléguait explicitement la décision. Ma première
réponse était « indicateur seulement ». **Je la révise, et le prototype a
raison :** `DictationController.transcribeAndInject` lit `language` *après*
l'arrêt de l'enregistrement. Changer de langue en cours de dictée agit donc
réellement sur la **passe finale** — c'est-à-dire sur le texte qui sera inséré.

Seul l'aperçu en direct garde son recognizer d'origine, et c'est acceptable : il
est indicatif par nature. La bascule est donc implémentée pour de vrai, avec ce
comportement documenté.

### Autres détails du rendu

* Point rouge `#ef4444` 8 px avec halo, pulsation 1,2 s.
* Chrono en monospace 12,5 px semi-gras, largeur minimale 32 px.
* Vumètre : 10 barres de 2,5 px, hauteur 3→14 px, rayon 2 px.
* Bouton mode micro : texte nu, blanc 65 %, cycle Isolement → Standard → Large.
* Badge `COLLECTE` : rayon **5 px**, 9,5 px, `letter-spacing 0.04em`, ambre
  `#fb923c` + bordure `rgba(249,115,22,0.6)` quand actif, blanc 45 % sinon.
* Aperçu live : *italique*, 13 px, blanc 75 %, 3 lignes maximum.
* Transcription : anneau 16 px + `Transcription en cours…` centré.
* Échec : `⚠️` + message en `#fca5a5`.
* Onglet notes : `Notes › {nom tronqué à 10 car. + …}` ou `Notes…`.
* Les onglets flottants ont leur propre fond `rgba(23,26,35,0.92)`, bordure
  blanche 14 %, rayon plein, et une ombre portée — ils se lisent comme un
  **second plan détaché** de la carte.

---

## 12. `UninstallationView`

Bonne nouvelle : le prototype **reprend fidèlement** la logique Swift existante
— mêmes identifiants, mêmes défauts `checkedByDefault`, wording très proche.
`Uninstall.swift` reste la source de vérité, seul l'habillage change.

Ordre du prototype : `settings`, `permissions`, `service`, `engine`, `logs`,
`corpus`, `model`. Fenêtre de **560 px**, rayon 12 px.

Deux garanties affichées en pied, à conserver mot pour mot :
* « **Votre fichier de notes.** S'il en existe un, c'est votre document :
  Sofler y écrivait, il ne lui appartient pas. »
* « **Tout part à la corbeille**, jamais en suppression définitive. Vous gardez
  la main jusqu'à ce que vous la vidiez. »

---

## 13. `UpdateCard` & `UpdateNotificationModal`

### `UpdateCard`

* En-tête : `Sofler v0.8.0` + badge `✓ À jour` (accent) **ou**
  `Mise à jour disponible` (ambre `#fef08a`).
* `Dernière vérification : {âge} · Release officielle`.
* Bouton `⟳ Vérifier maintenant` : **rayon 7 px, pas une pilule**, texte
  turquoise sur `accent-dim`, bordure `rgba(0,229,204,0.4)`, halo.
* Encart de mise à jour ambré : `🎉 Sofler v0.9.0 est disponible (24.8 Mo)` +
  `Publiée le {date}`, **liste des nouveautés** dans une boîte sombre interne,
  puis `Mettre à jour vers vX` (accent) + `Ignorer cette version` (discret) +
  `Voir sur GitHub ↗` aligné à droite.
* Progression en **trois phases nommées** avec remplissage **ambre** :
  téléchargement / vérification de signature / remplacement & redémarrage.
* Toggle auto en pied, séparé par un filet, `isCard: false`.

### `UpdateNotificationModal` — n'existe pas encore en Swift

Dialogue au lancement, avec trois issues qui **mémorisent** le choix :
* `Mettre à jour maintenant` → installation in-app avec progression.
* `Plus tard` → ferme ; le rappel reste dans le menu et les Réglages.
* `Ignorer cette version` → `sofler.update.ignoredVersion = version`.

`UpdateChecker` sait déjà trouver la version ; il manque la persistance de
`ignoredVersion` et `lastPostponedDate`, et la fenêtre elle-même.

---

## 14. `InstallPromptModal` — remplace un `NSAlert`

Le message « Sofler tourne depuis l'image disque » est aujourd'hui un `NSAlert`
système. Le prototype en fait une vraie fenêtre : 360 px, rayon 22 px, dégradé,
icône d'application 68 px, titre `Caspr n'est pas encore installé`, deux
paragraphes, puis deux boutons empilés pleine largeur — `Installer et ouvrir`
et `Continuer quand même`.

La logique Swift (`warnIfNotInstalled`, translocation, veilleur détaché,
éjection de l'image) est **conservée intégralement** : seule la présentation
change.

---

## 15. Bugs et incohérences relevés — dans les deux sens

### Dans le prototype

| # | Où | Problème |
| :-- | :-- | :-- |
| P1 | `DestinationCard` | `launchAtLogin` déclaré et jamais utilisé — code mort. Confirme que doc 01 a raison contre doc 02 §6. |
| P2 | `SettingsView` | Les six onglets à `flex: 1` dans 548 px donnent 91 px chacun ; `🎙️ Enregistrement` en demande ~117 px avec `nowrap`. Débordement probable à vérifier. |
| P3 | `InstallPromptModal` | Mélange `Caspr` (titre) et `Sofler` (corps) — rebranding partiel. |
| P4 | `CollectView` | Masque Apple Intelligence si `isLegacyOrIntel`. Une ligne absente ne se distingue pas d'une ligne qu'on n'a pas trouvée. |
| P5 | `AppleEngineCard` | Barre 0-100 % sur le téléchargement des modèles — techniquement impossible (cf. §3). |
| P6 | `HistoryView`/`VocabularyView` | `+ Restaurer des exemples` est une commodité de maquette, à ne pas porter. |

### Dans le Swift actuel

| # | Où | Problème |
| :-- | :-- | :-- |
| S1 | `LanguageSwitchCoordinator.audit()` | **Écrit** `prefs.appleTechnology`, contredisant le principe posé dans `EngineSafetyManager` (« le repli ne réécrit jamais la préférence »). Le prototype calcule un effectif sans muter. À corriger. |
| S2 | `TranscriptionHistory` | `static let limit = 5` figé. Le sélecteur 5/10/20/50 manque, avec troncature non destructive. |
| S3 | `CrisperEngineCard` (mon portage) | Ne porte aucune de la logique du prototype. À refaire entièrement. |
| S4 | `RecordingOverlay` (mon portage) | Pastille de langue au centre en indicateur dans tous les cas — faux dans les deux configurations. |
| S5 | `Preferences.starterLexicon` | Diverge de `STARTER_WEB_TERMS`. Le prototype ajoute `Docker`, `Kubernetes` et retire `component`, `hook`, `merge`, `commit`, `branch`, `dependencies`, `chunk`. |
| S6 | `TargetWriter.append` | Le prototype annonce « avec horodatage ». À vérifier : si l'ajout n'horodate pas, soit on l'ajoute, soit on corrige le texte. |
| S7 | `UpdateChecker` | Pas de `ignoredVersion` ni de `lastPostponedDate`, donc la modale de lancement ne peut pas mémoriser les choix. |
| S8 | `warnIfNotInstalled` | `NSAlert` là où le prototype veut une fenêtre dessinée. |

---

## 16. Ordre d'exécution retenu

1. **`CrisperEngineCard`** — le plus dense, explicitement signalé, et le plus
   éloigné de ma première version.
2. **`SettingsView`** — six onglets avec icônes, en-têtes par onglet, et les
   trois sous-vues (`HistoryView`, `VocabularyView`, `CollectView`).
3. **`LanguageSwitchService`** — bannières fermables, action inline, et
   correction de S1.
4. **`RecordingOverlay`** — rangée d'onglets conditionnelle (S4).
5. **`UpdateCard` + `UpdateNotificationModal`** — dont S7.
6. **`InstallPromptModal`** — dont S8.
7. **Rebranding Caspr** — passe mécanique en fin de parcours, pour ne pas
   doubler le bruit de chaque diff pendant la refonte.
