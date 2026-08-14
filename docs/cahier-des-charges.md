# CrispType

> **Native, private, local AI dictation for Apple Silicon.**

## 1. Vision

CrispType est une application macOS native de dictée vocale conçue exclusivement pour les Mac Apple Silicon.

L'objectif n'est **pas** de créer une application de productivité remplie de fonctionnalités.

L'objectif est de créer la meilleure expérience possible pour un workflow extrêmement simple :

> **Raccourci → parler → raccourci → le texte apparaît au curseur.**

L'application doit être :

* native macOS ;
* Apple Silicon uniquement ;
* 100 % locale ;
* sans compte ;
* sans cloud ;
* sans API distante ;
* sans télémétrie ;
* sans abonnement ;
* extrêmement légère en fonctionnalités ;
* très rapide ;
* silencieuse en arrière-plan ;
* parfaitement intégrée à macOS.

Le projet doit privilégier la qualité de l'expérience et les performances plutôt que le nombre de fonctionnalités.

---

# 2. Plateforme cible

## Support

### Obligatoire

* macOS 26+
* Apple Silicon uniquement :

  * M1
  * M2
  * M3
  * M4
  * générations futures compatibles

### Non supporté volontairement

* Windows
* Linux
* Intel Mac

Cette restriction est intentionnelle.

Le projet doit exploiter les capacités spécifiques des Mac Apple Silicon plutôt que chercher une abstraction cross-platform.

---

# 3. Philosophie technique

CrispType ne doit pas être un wrapper macOS autour d'un script Python.

L'objectif est de construire une **vraie application native Apple**.

Priorité aux frameworks Apple natifs :

* Swift
* SwiftUI
* AppKit lorsque nécessaire
* AVFoundation / AVFAudio
* Speech
* Core ML
* Core AI lorsque pertinent
* Foundation Models lorsque pertinent
* Accessibility APIs
* Service Management
* App Intents si une intégration future avec Siri/Shortcuts devient pertinente

Apple indique que Core ML exploite CPU, GPU et Neural Engine pour l'inférence on-device, tandis que macOS 27 introduit Core AI pour intégrer des modèles personnalisés dans les expériences Apple. Ces possibilités doivent être étudiées avant de choisir définitivement le backend d'inférence de CrisperWhisper.

**Ne jamais choisir une technologie uniquement parce qu'elle est multiplateforme.**

---

# 4. Fonctionnalités MVP

Le MVP doit rester volontairement minimal.

## 4.1 Global hotkey

L'utilisateur choisit un raccourci global.

Exemple par défaut :

`⌥ Space`

Comportement :

1. Premier appui :

   * démarrer l'enregistrement ;
   * afficher immédiatement un indicateur visuel ;
   * capturer le microphone.

2. Deuxième appui :

   * arrêter l'enregistrement ;
   * lancer l'inférence ;
   * obtenir la transcription ;
   * injecter le texte dans l'application active.

3. `Escape` pendant l'enregistrement :

   * annuler l'enregistrement ;
   * ne rien transcrire ;
   * ne rien insérer.

Le raccourci doit fonctionner même lorsque CrispType n'est pas l'application active.

---

# 5. Capture audio

Utiliser les APIs audio natives macOS.

Priorité :

* `AVAudioEngine`
* `AVAudioInputNode`
* buffers PCM natifs
* traitement asynchrone

Ne pas enregistrer inutilement des fichiers audio temporaires sur disque.

Pipeline souhaité :

```text
Microphone
    ↓
AVAudioEngine
    ↓
PCM buffer
    ↓
Audio preprocessing
    ↓
Speech inference
```

L'audio doit rester en mémoire autant que possible.

Aucun envoi réseau.

Aucune sauvegarde permanente de l'audio.

---

# 6. Modèle principal : CrisperWhisper 2.0

## Modèles à tester

Le projet doit prévoir une architecture permettant de tester facilement :

### `large`

Modèle de référence pour la qualité maximale.

Actuellement environ 3,09 Go sur disque pour les poids `large`.

### `turbo`

Modèle privilégiant la vitesse.

### `medium`

Compromis qualité / vitesse / taille.

### `small`

Option très légère.

---

# 7. Stratégie de modèle

Ne pas décider arbitrairement que `large` est obligatoire.

Créer un benchmark local sur Apple Silicon.

Mesurer au minimum :

* temps de chargement ;
* mémoire utilisée ;
* CPU ;
* GPU ;
* latence totale ;
* temps d'inférence ;
* ratio temps réel ;
* qualité de transcription ;
* qualité du français ;
* qualité de l'anglais ;
* qualité des autres langues ciblées.

Objectif principal :

> obtenir la meilleure qualité possible avec une latence suffisamment faible pour que l'utilisateur ait l'impression que la transcription est instantanée.

---

# 8. Speculative decoding

Tester :

```text
CrisperWhisper Large
        +
CrisperWhisper Turbo
```

avec speculative decoding.

CrisperWhisper documente officiellement `turbo` comme modèle de draft pour `large` et annonce environ 1,3–1,4× d'accélération dans les scénarios où le speculative decoding est bénéfique.

Le système doit être benchmarké plutôt que considéré comme automatiquement meilleur.

Pour les phrases très courtes, l'overhead du speculative decoding peut dépasser son bénéfice.

Le moteur doit donc pouvoir décider de l'activer ou non selon la longueur du segment audio.

---

# 9. Verbatim / Intended

C'est une fonctionnalité centrale.

## Mode Verbatim

Le modèle doit conserver ce qui a réellement été dit :

* hésitations ;
* répétitions ;
* faux départs ;
* bégaiements ;
* fillers ;
* événements vocaux lorsqu'ils sont reconnus.

Exemple :

> "Euh je pense que, enfin, je pense qu'on devrait reporter la réunion."

## Mode Intended

Le modèle doit produire la version propre correspondant à l'intention :

> "Je pense qu'on devrait reporter la réunion."

Le mode doit être sélectionnable depuis le menu principal.

Configuration :

```text
Transcription mode

○ Verbatim
● Intended
```

Le choix doit être persistant.

---

# 10. Utiliser `transcribe_dual` lorsque pertinent

CrisperWhisper permet de produire Verbatim et Intended à partir du même passage, avec un encoder partagé.

Cette possibilité doit être étudiée pour permettre éventuellement :

* une transcription unique ;
* disponibilité instantanée des deux variantes ;
* possibilité future de basculer entre Verbatim et Intended sans refaire toute l'inférence.

Cependant, ne pas complexifier inutilement le MVP si cela augmente fortement la mémoire ou la latence.

---

# 11. Multilingue

L'application doit permettre de sélectionner la langue.

Interface :

```text
Language

Auto
French
English
Vietnamese
Spanish
Indonesian
German
...
```

Important :

Ne pas déclarer arbitrairement que toutes les langues Whisper sont équivalentes avec CrisperWhisper.

Le projet doit créer un benchmark des langues réellement utiles et vérifier leur qualité avec CrisperWhisper 2.0.

Priorité personnelle pour les tests :

1. Français
2. Anglais
3. Vietnamien
4. Espagnol
5. Indonésien

Ajouter d'autres langues en fonction des capacités réelles du modèle.

---

# 12. Détection automatique de langue

Option :

```text
Language
● Auto
○ French
○ English
...
```

Le mode Auto doit être évalué en termes de :

* latence ;
* précision ;
* changements accidentels de langue.

Si Auto ajoute trop de latence, le mode manuel doit rester la recommandation.

---

# 13. Insertion automatique dans l'application active

Après transcription :

```text
Audio
 ↓
CrisperWhisper
 ↓
Text
 ↓
Active application
 ↓
Current cursor
```

Le texte doit apparaître directement à l'emplacement du curseur.

C'est une fonctionnalité fondamentale.

Elle doit fonctionner autant que possible dans :

* Safari
* Chrome
* Arc
* ChatGPT
* VS Code
* Cursor
* Xcode
* Terminal
* Slack
* Discord
* Messages
* Notes
* Mail
* éditeurs de texte
* champs texte macOS génériques

Utiliser les APIs Accessibility/macOS natives lorsque possible.

Prévoir un fallback raisonnable lorsque l'application cible ne permet pas une insertion directe.

---

# 14. Problème du curseur absent

Si l'utilisateur lance une transcription sans avoir placé son curseur dans un champ texte :

### Ne jamais perdre la transcription.

La transcription doit être conservée automatiquement.

Exemple :

```text
No text field detected.

Transcription saved to Recent.
```

L'utilisateur peut ensuite la récupérer.

---

# 15. Historique court des transcriptions

Conserver localement les dernières transcriptions.

Nombre par défaut :

**10**

Chaque entrée :

```text
timestamp
language
mode
text
```

Ne pas sauvegarder l'audio.

Uniquement le texte.

---

# 16. Réinsertion d'une ancienne transcription

Raccourci secondaire :

`⌘⇧V`

ou raccourci configurable.

Afficher une petite palette :

```text
Recent transcriptions

Just now
"Il faudrait modifier le composant..."

2 min ago
"Je pense qu'on devrait..."

5 min ago
"Peux-tu vérifier cette fonction..."
```

Cliquer sur une entrée :

→ insertion dans le champ actuellement actif.

---

# 17. Confidentialité

Principe absolu :

> **Audio never leaves the Mac.**

L'application ne doit envoyer :

* aucun audio ;
* aucune transcription ;
* aucun historique ;
* aucune donnée utilisateur

vers un serveur.

Pas de :

* analytics ;
* tracking ;
* télémétrie ;
* crash reporting cloud par défaut ;
* compte ;
* API key.

Les logs locaux doivent être minimaux et ne jamais contenir le contenu des transcriptions par défaut.

---

# 18. Interface

L'application doit principalement vivre dans la **menu bar**.

Utiliser SwiftUI `MenuBarExtra`.

Exemple :

```text
🎙 CrispType

Status
● Ready

Transcription
● Intended
○ Verbatim

Language
French

Recent Transcriptions
────────────────────
...

Settings
Quit CrispType
```

Pas de fenêtre principale permanente.

---

# 19. Indicateur d'enregistrement

Pendant l'enregistrement :

```text
🎙 Recording...
```

Prévoir une petite UI flottante native.

Objectif :

* extrêmement discrète ;
* toujours visible ;
* faible consommation ;
* aucun effet graphique inutile.

L'utilisateur doit immédiatement savoir que le microphone est actif.

---

# 20. Microphone

Settings :

```text
Microphone

System Default
MacBook Pro Microphone
AirPods Pro
External USB Microphone
...
```

L'utilisateur doit pouvoir sélectionner explicitement le microphone.

Gérer correctement :

* microphone débranché ;
* AirPods connectés/déconnectés ;
* changement de périphérique ;
* permissions microphone ;
* absence de microphone.

---

# 21. Permissions

Au premier lancement :

1. demander permission microphone ;
2. expliquer pourquoi ;
3. demander Accessibility uniquement lorsque nécessaire ;
4. expliquer clairement pourquoi Accessibility est nécessaire.

Ne jamais demander une permission inutile.

---

# 22. Launch at Login

Option :

```text
Launch CrispType at login
```

Utiliser les APIs modernes de Service Management / `SMAppService`.

CrispType doit pouvoir fonctionner en arrière-plan sans fenêtre Dock permanente si possible.

---

# 23. Architecture recommandée

```text
CrispType
│
├── App
│   ├── CrispTypeApp
│   ├── AppState
│   └── MenuBar
│
├── Audio
│   ├── AudioCapture
│   ├── AudioBuffer
│   └── AudioDeviceManager
│
├── Speech
│   ├── SpeechEngine
│   ├── CrisperWhisperEngine
│   ├── ModelManager
│   └── LanguageManager
│
├── Transcription
│   ├── TranscriptionResult
│   ├── TranscriptionMode
│   └── TranscriptionHistory
│
├── Input
│   ├── GlobalHotkey
│   └── RecordingController
│
├── Integration
│   ├── AccessibilityController
│   ├── TextInjector
│   └── ActiveApplicationDetector
│
├── UI
│   ├── MenuBarView
│   ├── RecordingOverlay
│   ├── SettingsView
│   └── HistoryView
│
├── Storage
│   ├── Preferences
│   └── HistoryStore
│
└── Diagnostics
    └── PerformanceMonitor
```

---

# 24. Séparer le moteur STT de l'application

Créer un protocole abstrait :

```swift
protocol SpeechEngine {
    func load() async throws
    func unload() async
    func transcribe(
        audio: AudioBuffer,
        language: String?,
        mode: TranscriptionMode
    ) async throws -> TranscriptionResult
}
```

Cela permettra de tester plusieurs backends sans réécrire l'application.

Exemples futurs :

```text
SpeechEngine
├── CrisperWhisperEngine
├── AppleSpeechEngine
└── FutureEngine
```

Mais **le MVP ne doit pas exposer plusieurs moteurs à l'utilisateur**.

CrisperWhisper est le moteur principal.

---

# 25. Apple Speech comme fallback technique

macOS dispose désormais de `SpeechAnalyzer` et `SpeechTranscriber`, avec des assets installables pour les capacités de transcription on-device.

Il peut être intéressant de l'utiliser comme :

* fallback ;
* outil de benchmark ;
* comparaison de qualité ;
* solution de secours si CrisperWhisper échoue.

Mais il ne doit pas remplacer CrisperWhisper dans le MVP sans benchmark.

Le projet doit également vérifier précisément quelles langues sont disponibles sur le système et quelles ressources doivent être installées.

---

# 26. Apple Silicon

C'est un élément fondamental du projet.

CrispType doit être conçu pour Apple Silicon, pas simplement compilé pour Apple Silicon.

Étudier :

### Core ML

Vérifier s'il est possible de convertir efficacement le pipeline CrisperWhisper vers Core ML.

Objectif potentiel :

```text
CrisperWhisper
      ↓
Core ML
      ↓
Apple Silicon
 ┌────┼────┐
CPU   GPU  Neural Engine
```

Core ML est conçu pour exploiter CPU, GPU et Neural Engine tout en limitant consommation et mémoire.

### Important

Ne pas supposer que CrisperWhisper est directement compatible Core ML.

Faire un POC de conversion.

Si la conversion est :

* stable ;
* suffisamment rapide ;
* compatible avec les fonctionnalités nécessaires ;
* suffisamment précise ;

alors Core ML peut devenir le backend natif privilégié.

Sinon, utiliser le meilleur runtime disponible pour Apple Silicon.

---

# 27. CTranslate2

CrisperWhisper fournit officiellement un backend CTranslate2 optimisé et un backend Transformers.

Le backend CTranslate2 est la référence performance de CrisperWhisper et supporte notamment le speculative decoding.

Cependant, le support officiel fourni par CrisperWhisper est principalement orienté vers Linux pour les wheels CTranslate2, tandis que le backend Transformers est portable sur macOS.

Il faut donc **faire un POC natif macOS avant de décider** comment intégrer CTranslate2 dans l'application finale.

Options à benchmarker :

1. Core ML
2. CTranslate2 compilé/intégré nativement
3. Metal/MPS si une implémentation adaptée est disponible
4. Transformers/PyTorch comme fallback de développement

Ne pas choisir Python comme architecture finale par défaut.

---

# 28. macOS 27 / Core AI

Le projet doit être pensé pour évoluer avec macOS 27.

Apple introduit dans macOS 27 :

* Core AI ;
* Foundation Models ;
* intégration plus poussée avec Apple Intelligence ;
* possibilités d'intégrer des modèles personnalisés ;
* App Intents améliorés.

CrispType doit donc isoler son moteur d'inférence derrière une abstraction permettant éventuellement d'adopter Core AI lorsqu'il devient pertinent.

Ne pas dépendre d'une API bêta si elle n'est pas nécessaire au MVP.

---

# 29. Foundation Models

Ne PAS ajouter un LLM Apple dans le pipeline initial.

CrisperWhisper 2.0 fournit déjà :

```text
Verbatim
Intended
```

Le MVP doit donc être :

```text
Audio
 ↓
CrisperWhisper
 ↓
Text
```

et non :

```text
Audio
 ↓
CrisperWhisper
 ↓
LLM
 ↓
Text
```

Foundation Models pourra éventuellement être étudié en V2 pour :

* formatage intelligent ;
* correction contextuelle ;
* transformation du texte ;
* commandes vocales ;
* compréhension du contexte de l'application active.

Mais ce n'est pas nécessaire pour la mission principale.

Si Foundation Models est utilisé plus tard, maintenir l'exigence "on-device only" et ne jamais utiliser Private Cloud Compute ou un fournisseur cloud pour le pipeline principal.

---

# 30. Apple Silicon performance monitoring

Créer un mode développeur permettant de mesurer :

```text
Model:
Large

Backend:
Core ML / CT2 / ...

Audio:
12.4 sec

Inference:
0.72 sec

RTF:
0.058

Peak memory:
X GB

CPU:
X %

GPU:
X %

Neural Engine:
X %

Total latency:
X ms
```

Ces données ne doivent pas être collectées à distance.

Elles servent au développement et au benchmark local.

---

# 31. Objectifs de performance

Le but n'est pas de maximiser l'utilisation CPU/GPU.

Le but est :

> **minimiser la latence perçue tout en conservant une excellente qualité.**

Objectifs indicatifs :

### Après arrêt de l'enregistrement

* feedback visuel immédiat ;
* transcription la plus rapidement possible ;
* idéalement < 1 seconde pour une phrase courte sur une machine Apple Silicon moderne.

Ces valeurs sont des objectifs, pas des garanties.

Les benchmarks doivent être réalisés sur plusieurs générations :

* M1
* M2
* M3
* M4

si du matériel est disponible.

---

# 32. Gestion mémoire

Le modèle `large` fait environ 3,09 Go sur disque.

Mais ne jamais considérer cette valeur comme la consommation RAM réelle.

Mesurer :

* RAM au repos ;
* RAM après chargement ;
* RAM pendant inference ;
* peak memory ;
* mémoire avec large ;
* mémoire avec turbo ;
* mémoire avec large + turbo.

Objectif :

* garder le modèle chargé après le premier usage pour éviter les reloads ;
* libérer le modèle si une option "low memory mode" est ajoutée plus tard ;
* éviter les copies inutiles des buffers audio ;
* éviter de charger plusieurs modèles lourds simultanément sans raison.

---

# 33. Model Manager

Le modèle ne doit pas forcément être inclus dans le bundle de l'application.

Prévoir :

```text
Application
    ↓
Model Manager
    ↓
Download selected model
    ↓
Local model cache
```

Exemple :

```text
~/Library/Application Support/CrispType/Models/
```

Modèles :

```text
CrisperWhisper2.0_large
CrisperWhisper2.0_turbo
CrisperWhisper2.0_medium
```

Afficher :

* taille ;
* installé/non installé ;
* version ;
* supprimer ;
* télécharger.

Pour le MVP, le modèle recommandé peut être :

```text
Large — Best quality
```

ou `Turbo` si les benchmarks montrent une expérience nettement meilleure.

---

# 34. Pas de téléchargement automatique silencieux

Au premier lancement :

```text
Welcome to CrispType

Choose your speech model

Large
Best quality
~3 GB

Turbo
Faster
Smaller

[Download Large]
```

Informer clairement l'utilisateur de la taille du téléchargement.

---

# 35. Stockage

Utiliser les mécanismes macOS natifs pour :

* préférences ;
* historique ;
* état du modèle.

Ne pas utiliser de base de données lourde.

Le stockage local doit rester simple.

---

# 36. Historique et confidentialité

Par défaut :

* conserver les 10 dernières transcriptions ;
* uniquement en local ;
* aucun audio ;
* possibilité de supprimer tout l'historique.

Option :

```text
Clear transcription history
```

Prévoir également :

```text
Store transcription history
● On
○ Off
```

---

# 37. Design

Le design doit être extrêmement minimal.

Inspirations :

* Apple Voice Memos
* macOS Spotlight
* Raycast
* petites utilities natives macOS

Éviter :

* dashboard ;
* sidebar permanente ;
* gros boutons ;
* animations inutiles ;
* interface "AI startup" générique ;
* gradients ;
* surcharge visuelle.

CrispType doit donner l'impression d'être **une fonction native de macOS**.

---

# 38. Feedback pendant la dictée

États :

```text
Idle
 ↓
Recording
 ↓
Processing
 ↓
Inserted
```

Exemple visuel :

```text
● Recording
```

Puis :

```text
◌ Processing
```

Puis disparition automatique.

En cas d'erreur :

```text
Unable to transcribe

[Retry]
```

---

# 39. Gestion des erreurs

Gérer proprement :

* permission microphone refusée ;
* permission Accessibility refusée ;
* aucun microphone ;
* microphone déconnecté ;
* modèle absent ;
* modèle corrompu ;
* modèle incompatible ;
* mémoire insuffisante ;
* inference échouée ;
* application cible incompatible ;
* texte impossible à injecter.

Ne jamais afficher une stack trace à l'utilisateur.

---

# 40. Packaging

Application native :

```text
CrispType.app
```

Architecture :

```text
arm64
```

Universal binary non nécessaire puisque le projet cible exclusivement Apple Silicon.

Prévoir :

* code signing ;
* notarization ;
* DMG ou distribution adaptée ;
* mises à jour futures.

---

# 41. Licence du projet

Le code de CrispType peut être open source.

Le choix initial recommandé :

```text
MIT
```

Cependant, les composants tiers doivent rester sous leurs licences respectives.

Important :

Le code d'inférence CrisperWhisper est MIT, mais les poids standard CrisperWhisper 2.0 sont actuellement sous une licence Nyra Health Non-Commercial Research.

Ne jamais mettre les poids CrisperWhisper sous la licence MIT de CrispType.

Le README doit clairement séparer :

```text
CrispType source code
→ MIT

CrisperWhisper inference code
→ MIT

CrisperWhisper model weights
→ Nyra Health license
```

Avant toute distribution commerciale de CrispType avec les poids CrisperWhisper, obtenir une licence commerciale écrite de Nyra.

---

# 42. Architecture commerciale future

L'architecture doit permettre plus tard :

```text
CrispType
│
├── Open-source code
│
├── SpeechEngine abstraction
│
├── Commercially redistributable model
│
└── Optional CrisperWhisper
```

Ne jamais coupler toute l'application au modèle de manière irréversible.

---

# 43. Features explicitement hors MVP

NE PAS ajouter :

* compte utilisateur ;
* cloud ;
* synchronisation iCloud ;
* abonnement ;
* analytics ;
* chatbot ;
* assistant vocal ;
* commandes vocales complexes ;
* résumé automatique ;
* traduction ;
* génération de texte ;
* correction LLM ;
* intégration Slack spécifique ;
* intégration VS Code spécifique ;
* dashboard ;
* plugin Chrome ;
* version Windows ;
* version Linux ;
* mobile ;
* historique illimité ;
* transcription de fichiers audio ;
* meeting recorder.

Tout cela peut éventuellement être étudié plus tard.

---

# 44. Features V2 possibles

Seulement après avoir validé le MVP :

### Apple Intelligence

Utiliser Foundation Models on-device pour :

* reformater ;
* nettoyer ;
* transformer ;
* exécuter des commandes vocales.

### App Intents

Permettre :

```text
Siri, start CrispType
```

ou :

```text
Start dictation with CrispType
```

### Context awareness

Détecter l'application active :

```text
VS Code
Safari
Mail
ChatGPT
```

et adapter éventuellement le traitement.

### Voice commands

Exemple :

> "New paragraph"

→ saut de ligne.

> "Delete last sentence"

→ suppression.

Mais seulement si cela reste fiable et rapide.

---

# 45. Tests

Créer des tests unitaires pour :

* transcription state machine ;
* history ;
* settings ;
* model manager ;
* language selection ;
* hotkey state ;
* error handling.

Tests d'intégration :

* microphone ;
* model loading ;
* transcription ;
* text injection ;
* permissions.

Tests manuels :

* Safari
* Chrome
* VS Code
* Xcode
* Terminal
* ChatGPT
* Slack
* Notes
* Mail
* Discord

---

# 46. Benchmark de référence

Créer un corpus personnel de phrases.

Exemples :

### Français

* phrases normales ;
* phrases longues ;
* hésitations ;
* répétitions ;
* noms propres ;
* vocabulaire technique ;
* anglais mélangé au français.

### Anglais

Même chose.

### Vietnamien / espagnol / indonésien

Évaluer :

* qualité ;
* latence ;
* hallucinations ;
* ponctuation.

Comparer :

```text
CrisperWhisper Large
CrisperWhisper Medium
CrisperWhisper Turbo
Apple Speech
```

si Apple Speech est disponible dans la langue concernée.

---

# 47. Critère de réussite du MVP

CrispType est considéré comme réussi si :

1. L'utilisateur appuie sur un seul raccourci.
2. Il parle naturellement.
3. Il appuie à nouveau.
4. Le texte apparaît rapidement au curseur.
5. La transcription est meilleure ou au moins aussi bonne que FluidVoice pour l'usage quotidien.
6. Verbatim et Intended sont fiables.
7. Le système fonctionne sans Internet.
8. Le système fonctionne en arrière-plan.
9. Aucun audio n'est envoyé hors du Mac.
10. L'application consomme peu de ressources lorsqu'elle est inactive.
11. Le fonctionnement est particulièrement fluide sur Apple Silicon.

---

# 48. Première phase de développement

NE PAS commencer directement par l'interface.

## Phase 1 — POC moteur

Créer un petit programme local permettant de tester :

```text
audio file
 ↓
CrisperWhisper Large
 ↓
Verbatim
 ↓
Intended
```

Puis :

```text
Large
vs
Medium
vs
Turbo
```

Mesurer :

* temps ;
* mémoire ;
* qualité.

---

# 49. Phase 2 — POC Apple Silicon

Tester les différentes stratégies :

```text
CrisperWhisper
     │
     ├── Transformers / PyTorch
     ├── CTranslate2
     └── Core ML / Core AI feasibility
```

Objectif :

déterminer le backend offrant le meilleur rapport :

```text
quality
+
latency
+
memory
+
battery
```

sur Apple Silicon.

---

# 50. Phase 3 — Native audio

Implémenter :

```text
AVAudioEngine
 ↓
PCM
 ↓
SpeechEngine
```

sans UI complexe.

---

# 51. Phase 4 — Hotkey

Ajouter :

```text
Global Hotkey
 ↓
Start / Stop recording
```

---

# 52. Phase 5 — Text injection

Ajouter :

```text
Transcription
 ↓
Accessibility
 ↓
Active text field
```

---

# 53. Phase 6 — Menu bar

Ajouter :

* mode ;
* langue ;
* modèle ;
* historique ;
* settings.

---

# 54. Phase 7 — Performance

Optimiser :

* modèle ;
* mémoire ;
* audio ;
* threads ;
* inference ;
* startup ;
* latency.

Objectif :

> L'application doit sembler instantanée.

---

# 55. Phase 8 — Distribution

Ajouter :

* code signing ;
* notarization ;
* DMG ;
* GitHub Releases ;
* documentation ;
* licence ;
* README ;
* benchmark ;
* vidéo de démonstration.

---

# 56. README du projet

Le README doit mettre immédiatement en avant :

> **CrispType**
>
> Fast, private, local AI dictation for Apple Silicon.
>
> Press a key. Speak. Press it again. Your words appear wherever your cursor is.

Puis :

```text
✓ 100% local
✓ Apple Silicon optimized
✓ Verbatim + Intended
✓ Multilingual
✓ Global hotkey
✓ Works in any text field
✓ No account
✓ No cloud
✓ No subscription
```

---

# 57. Positionnement du projet

CrispType ne doit pas être présenté comme :

> "another AI writing assistant"

mais comme :

> **"A native macOS voice-to-text utility powered by local AI."**

Le produit doit rester centré sur une seule chose :

> **faire de la voix une méthode de saisie extrêmement rapide et privée.**

---

# 58. Priorité absolue

Dans toutes les décisions techniques, appliquer cet ordre :

1. **Latence**
2. **Qualité de transcription**
3. **Fiabilité**
4. **Intégration macOS**
5. **Consommation mémoire**
6. **Consommation énergétique**
7. **Simplicité**
8. **Fonctionnalités supplémentaires**

Ne jamais sacrifier les quatre premiers points pour ajouter une feature.

---

# 59. Résumé technique

```text
                ┌──────────────────────────────┐
                │          CrispType           │
                │       Native macOS app       │
                └──────────────┬───────────────┘
                               │
             ┌─────────────────┼─────────────────┐
             │                 │                 │
             ▼                 ▼                 ▼
        SwiftUI/AppKit     Global Hotkey     Menu Bar
             │                 │                 │
             └─────────────────┼─────────────────┘
                               │
                               ▼
                       AVAudioEngine
                               │
                               ▼
                         PCM Audio
                               │
                               ▼
                    Speech Engine Layer
                               │
                               ▼
                     CrisperWhisper 2.0
                               │
                  ┌────────────┴────────────┐
                  │                         │
                  ▼                         ▼
              Verbatim                  Intended
                  │                         │
                  └────────────┬────────────┘
                               ▼
                         Text Injector
                               │
                               ▼
                      Active macOS App
                               │
                               ▼
                         Current Cursor
```

---

# 60. Principe final

**CrispType doit être petit à utiliser, mais sérieux techniquement.**

L'utilisateur ne doit presque rien voir.

Toute la complexité doit être cachée derrière une expérience extrêmement simple :

> **Press → Speak → Press → Done.**

La valeur technique du projet vient de ce qui se passe derrière :

* Apple Silicon ;
* on-device inference ;
* CrisperWhisper ;
* audio temps réel ;
* Swift concurrency ;
* macOS Accessibility ;
* global hotkeys ;
* memory management ;
* low latency ;
* privacy ;
* native Apple APIs.

Le produit final doit donner l'impression que la dictée vocale est une fonctionnalité native de macOS.
