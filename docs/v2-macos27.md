# Sofler V2 — mettre un cerveau derrière la transcription

> **Statut du document.** Plan de travail, pas une spécification. Rien ici
> n'est à coder tout de suite : la V1 doit d'abord exister et être utilisée par
> de vraies personnes.
>
> **Rédigé le 15 août 2026.** Les éléments marqués ✅ ont été vérifiés en ligne
> à cette date. Ceux marqués ❓ sont des hypothèses à confirmer — soit parce
> qu'Apple ne les a pas documentés, soit parce qu'ils dépendent de mesures que
> personne n'a encore faites sur ce projet.

---

## Où en est le projet

| | Ce que c'est | État |
|---|---|---|
| **V0** | Le moteur validé, l'app utilisée quotidiennement par une personne | fait |
| **V1** | Une application qu'on télécharge et qui marche pour un inconnu. C'est une bêta, et elle doit le dire. | en cours — 0.1.0 |
| **V2** | `parole → texte` devient `parole → intention → texte` | ce document |

La V1 n'est pas une étape administrative avant la V2. C'est elle qui produit la
seule chose qui rendra la V2 mesurable : **des dictées réelles, de plusieurs
personnes, avec ce qu'elles auraient voulu voir écrit.**

---

## 1. La thèse

Aujourd'hui Sofler fait `parole → texte`. Un seul modèle porte toute la charge :
entendre les sons, et deviner l'orthographe voulue. C'est beaucoup demander à
une seule étape, et ça se voit dans les compromis actuels :

| Moteur | Ce qu'il réussit | Ce qu'il rate | Ce qu'il coûte |
|---|---|---|---|
| macOS | français fluide, immédiat, gratuit | remplace les mots qu'il ne connaît pas | rien |
| CrisperWhisper | respecte le lexique, deux rendus | plus lent | 1,6 Go, 3 Go de RAM, licence non commerciale |

La V2 propose de séparer les deux problèmes :

```
🎙️  audio
     ↓
[ ÉTAPE 1 ]  entendre          →  transcription brute
     ↓
[ ÉTAPE 2 ]  comprendre        →  texte tel qu'on l'aurait écrit
     ↓
📝  insertion
```

**Et voici l'enjeu réel, qui n'est pas « du texte plus joli ».**

Si l'étape 2 sait restaurer le vocabulaire, alors l'étape 1 n'a plus besoin de
le connaître. Le moteur de macOS — gratuit, déjà installé, sans licence,
sans téléchargement — pourrait suffire. CrisperWhisper sortirait du chemin
critique, et avec lui les 1,6 Go, les 3 Go de RAM, l'installation par le
Terminal et la licence non commerciale.

> **C'est ça, le vrai gain de la V2 : faire disparaître trois problèmes
> d'adoption d'un coup, pas améliorer la ponctuation.**

### L'hypothèse centrale, formulée pour être réfutable

> Le lexique n'est pas perdu, il **change d'étape**.
> CrisperWhisper conditionne le *décodage*. Un modèle de langage peut
> conditionner la *correction*.

Concrètement : le moteur de macOS écrit « use effect ». Un modèle à qui l'on
fournit la liste des termes employés peut-il retrouver `useEffect` ? Et pour
« Nextjay », retrouver `Next.js` ?

Il y a une limite dure qu'il faut nommer tout de suite : **un modèle ne peut
pas restaurer ce qui n'a laissé aucune trace.** Si l'étape 1 rend une suite de
sons trop éloignée du mot voulu, aucune correction ne le retrouvera. La
question n'est donc pas « est-ce que ça marche » mais **« sur quelle proportion
des cas »** — et c'est exactement ce que le corpus permet de mesurer.

---

## 2. Ce que macOS 27 apporte vraiment

Vérifié en ligne. La note de départ (`notes/macos27.md`, issue de ChatGPT)
était **largement exacte** ; ce tableau distingue le confirmé du reste.

| Élément | Statut | Ce que c'est |
|---|---|---|
| Foundation Models ouvert à tout fournisseur | ✅ | Un protocole `LanguageModel` : modèle Apple, Claude, Gemini, MLX, ou le vôtre, derrière la même API |
| Multimodal (images en entrée) | ✅ | Prompts texte + image |
| Outils Vision appelables par le modèle | ✅ | OCR, lecture de codes-barres, en local |
| Dynamic Profiles | ✅ | Changer modèle, outils et instructions au cours d'une même session |
| **SDK Python** | ✅ | **Absent de la note. Le moteur de Sofler est en Python.** |
| **Outil en ligne de commande `fm`** | ✅ | **Absent de la note. `fm chat` ouvre une session interactive ; scriptable en shell.** |
| Core AI | ✅ | Exécution de modèles on-device, compilation anticipée, contrôle mémoire, zéro-copie |
| Evaluations | ✅ | Éprouver systématiquement un comportement d'IA, au-delà des tests unitaires |
| Foundation Models open source | ✅ | Annoncé, la même API Swift côté serveur |
| PCC gratuit pour le Small Business Program | ✅ | Moins de 2 M de téléchargements → accès gratuit aux modèles de nouvelle génération sur Private Cloud Compute. **Suppose une adhésion App Store.** |
| SpeechAnalyzer / SpeechTranscriber / SpeechDetector | ❓ | Existent depuis macOS 26. Le guide macOS 27 n'en parle pas — ni évolution ni régression annoncée |

### La correction qui change le plan

**Le Siri de Gemini ne tourne pas en local.** C'est un modèle sur mesure de
**1 200 milliards de paramètres**, réparti entre l'appareil et **Private Cloud
Compute**. Ce qui est local : l'orchestrateur, l'index Spotlight, le contexte
personnel. Les traitements lourds partent sur PCC.

Un modèle de cette taille ne tiendra jamais dans un Mac. L'idée « Apple va
mettre une IA très puissante en local sur tous les Macs, donc je n'aurai plus
besoin de mon propre modèle » est donc **vraie à moitié** :

- ✅ Il y a bien un **modèle Apple on-device**, gratuit, déjà présent,
  reconstruit et meilleur en suivi d'instructions. Pas de téléchargement, pas
  de licence. C'est exactement ce qu'il fallait.
- ❌ Mais **ce n'est pas le modèle de 1 200 milliards de paramètres**. Celui-là
  est dans le nuage — le nuage privé d'Apple, isolé de Google, mais du nuage.

Pour Sofler, ce n'est pas une mauvaise nouvelle. Nettoyer une phrase qu'on
vient de dire est une tâche **bornée** : elle ne demande pas un modèle
frontière. Il est très possible que le petit modèle local suffise. C'est
précisément ce qu'il faut mesurer avant toute décision d'architecture.

---

## 3. Ce que ça impose à la promesse de confidentialité

Sofler dit « rien ne sort de votre Mac », et cette phrase n'a aujourd'hui
**aucune exception**. C'est un actif : elle est facile à vérifier et il n'y a
rien à nuancer. Toute la V2 doit être conçue pour ne pas l'abîmer.

Trois niveaux, à présenter comme tels :

```
┌─ Niveau 1 ── aucun modèle de langage ─────────────────────────┐
│  Ce que fait Sofler aujourd'hui. La transcription, point.     │
│  Promesse intacte. Doit rester le défaut.                     │
└───────────────────────────────────────────────────────────────┘
┌─ Niveau 2 ── modèle local ────────────────────────────────────┐
│  Modèle Apple on-device, ou MLX. Rien ne quitte la machine.   │
│  Promesse intacte. C'est la cible de la V2.                   │
└───────────────────────────────────────────────────────────────┘
┌─ Niveau 3 ── Private Cloud Compute ───────────────────────────┐
│  Le texte dicté quitte le Mac. Chiffré, non conservé, isolé   │
│  de Google — mais il sort.                                    │
│  ⚠ Désactivé par défaut. Choix explicite, expliqué, comme     │
│    la licence de CrisperWhisper l'est aujourd'hui.            │
└───────────────────────────────────────────────────────────────┘
```

Le précédent existe déjà dans le projet et fonctionne : la licence non
commerciale de CrisperWhisper est présentée avant tout téléchargement, et le
choix appartient à l'utilisateur. Le niveau 3 se traite pareil.

---

## 4. Le risque central : le sens qui dérive

**C'est le point le plus important du document.**

Un modèle qui « améliore » un texte finira par en changer le sens. En dictée,
c'est bien plus grave qu'ailleurs, pour une raison précise :

> **On ne relit pas ce qu'on a dicté.**

C'est même la raison d'être de l'outil : parler au lieu de taper, sans
surveiller le résultat. Une hésitation laissée en place se voit et se corrige.
Un sens modifié en silence ne se voit pas — il part dans un courriel, un
commit, une note, et se découvre plus tard, ou jamais.

Donc la hiérarchie des mesures n'est pas négociable :

| Rang | Mesure | Seuil visé |
|---|---|---|
| 1 | **Sens modifié** | ~0. Un seul cas suffit à disqualifier un niveau de retouche |
| 2 | **Information ajoutée** (le modèle invente) | 0 |
| 3 | **Information supprimée** | ~0 |
| 4 | Terme technique restauré | à maximiser |
| 5 | Terme technique cassé (il était juste, le modèle l'abîme) | ~0 |
| 6 | Ponctuation | à maximiser |
| 7 | Hésitations retirées | à maximiser |
| 8 | Latence ajoutée | à contraindre |
| 9 | Mémoire | à contraindre |

Les rangs 1 à 3 sont des **critères d'élimination**, pas des scores à moyenner
avec le reste. Un niveau de retouche qui gagne 10 points de ponctuation et
change un sens sur cent est à rejeter.

### Deux risques que la note d'origine ne mentionne pas

**Le modèle peut refuser.** Les modèles de fondation ont des filtres. Quelqu'un
dicte un message sur un sujet médical, un conflit, un incident — et le modèle
réécrit, adoucit ou refuse. Sur un outil de dictée, un refus est une panne :
l'utilisateur a parlé, et rien n'apparaît. **À tester explicitement avec du
contenu banal mais sensible.**

**Le modèle d'Apple sera mis à jour sans vous.** Les modèles système sont des
ressources mises à jour par le système. Votre sortie peut donc changer sans que
vous ayez rien publié, et un réglage validé en janvier peut se comporter
autrement en mars. Conséquences pratiques :

- enregistrer la version du modèle avec chaque mesure ;
- rejouer le banc d'essai après chaque mise à jour de macOS ;
- ne jamais promettre un comportement exact à l'utilisateur, seulement un
  niveau d'intervention.

---

## 5. Le curseur de retouche

L'idée d'un curseur — jusqu'où l'IA a le droit d'aller — est la bonne réponse
au risque ci-dessus. Elle transforme une question insoluble (« quel est le bon
niveau de correction ? ») en un réglage que chacun tranche pour soi.

Elle prolonge en plus un contrôle **qui existe déjà** et que les utilisateurs
comprennent : « texte nettoyé / mot à mot ». Ce n'est pas un concept de plus à
faire adopter, c'est le même, avec plus de crans.

| Cran | Nom | Ce qui est permis | Exemple |
|---|---|---|---|
| 0 | **Mot à mot** | rien. Aucun modèle de langage | `je veux euh aller enfin non modifier le bouton bleu qui est à droite` |
| 1 | **Ponctuation** | ponctuer, segmenter. Aucun mot retiré | `Je veux, euh, aller… enfin non, modifier le bouton bleu qui est à droite.` |
| 2 | **Nettoyé** | retirer hésitations, répétitions, autocorrections orales | `Je veux modifier le bouton bleu qui est à droite.` |
| 3 | **Écrit** | tourner en français écrit, restaurer le vocabulaire | `Je veux modifier le bouton bleu situé à droite.` |
| 4 | **Réécrit** | reformuler selon un profil (courriel, note, prompt) | `Modifie le bouton bleu situé à droite.` |

Le cran 2 est probablement le bon défaut : c'est là que se trouve l'essentiel
du gain, et le risque de dérive du sens y est encore faible. **Le cran 4 ne
devrait jamais être un défaut** — c'est une transformation, pas une
transcription.

Techniquement, ces crans correspondent aux **Dynamic Profiles** ✅ : un seul
moteur, des instructions différentes, changeables en cours de session — donc
changeables depuis la barre pendant qu'on parle, comme le mode et la
destination aujourd'hui.

---

## 6. Ce qui est testable **maintenant**, sans macOS 27

**C'est la section la plus importante en pratique.**

L'idée centrale de la V2 ne dépend pas d'Apple. Un modèle de langage local,
c'est un modèle de langage local : le moteur est déjà en Python, MLX et
llama.cpp tournent sur Apple Silicon aujourd'hui. On peut répondre à la
question « est-ce qu'un second étage améliore vraiment le résultat ? » cette
semaine.

Si la réponse est oui, Foundation Models sera une **meilleure implémentation
d'une chose déjà validée** — gratuite, sans téléchargement, sans licence.
Si la réponse est non, on aura économisé un an d'attente.

### Le corpus est déjà l'actif décisif

`~/Library/Application Support/Sofler/corpus` — de l'audio réel, avec les
transcriptions de plusieurs moteurs, et la mention de quel moteur a produit
quoi. C'est très exactement le jeu de données qu'il faut. Il manque une seule
colonne :

> **le texte que vous auriez voulu voir écrit.**

Sans elle, on ne peut que comparer des moteurs entre eux ; avec elle, on peut
mesurer une distance à la cible. **Constituer cette colonne est la tâche la
plus rentable du projet**, et elle ne demande aucune technologie : relire
quelques centaines de dictées et corriger. Elle servira à tout ce qui suivra,
y compris au framework Evaluations quand il arrivera.

---

## 7. Plan de tests ordonné

### Phase 0 — maintenant, sans macOS 27

- [ ] **Annoter le corpus.** Ajouter le texte cible à ~200 dictées. Couvrir :
      français, anglais, franglais, termes techniques, noms propres, chiffres,
      URLs, phrases longues, hésitations, autocorrections.
- [ ] **Écrire le banc d'essai** : entrée = transcription brute, sortie = texte
      final, mesures = le tableau de la section 4. Hors ligne, sans toucher à
      l'application.
- [ ] **Établir la référence.** Ce que donnent aujourd'hui macOS seul et
      CrisperWhisper seul, sur ces 200 cas. Sans référence, tout ce qui suit
      est une impression.
- [ ] **Prototyper l'étape 2** avec un modèle local (MLX, 3–8 Md de
      paramètres). Cran 2 uniquement.
- [ ] **Répondre à la question qui décide de tout :**
      `macOS + étape 2` fait-il aussi bien que `CrisperWhisper seul` ?
      Si oui, la V2 supprime le téléchargement, la RAM et la licence.
- [ ] **Mesurer la latence ajoutée.** Budget à fixer d'avance — au-delà, la
      retouche doit être optionnelle par mode.
- [ ] **Tester le refus.** Contenu banal mais sensible (santé, conflit,
      argent). Le modèle réécrit-il ? Refuse-t-il ?

### Phase 1 — dès macOS 27 disponible (sur volume séparé)

- [ ] **Rejouer exactement le même banc** avec le modèle Apple on-device. La
      comparaison n'a de sens que si rien d'autre ne change.
- [ ] Comparer les quatre combinaisons :
      `macOS seul` · `CrisperWhisper seul` · `macOS + Apple` ·
      `CrisperWhisper + Apple`.
- [ ] **Vérifier la régression de SpeechTranscriber** entre macOS 26 et 27 —
      même Mac, même micro, mêmes fichiers. Ne rien supposer.
- [ ] Tester les crans 1 à 4 avec les Dynamic Profiles.
- [ ] Mesurer la fenêtre de contexte utile : 1 phrase, 30 s, 1 min, 5 min.
- [ ] Éprouver le SDK Python et `fm` — le moteur est déjà en Python, c'est
      peut-être le chemin d'intégration le plus court.

### Phase 2 — si la phase 1 est concluante

- [ ] Porter le banc d'essai sur **Evaluations**.
- [ ] Intégrer le cran dans l'interface (barre + réglages), défaut au cran 2.
- [ ] Décider du sort de CrisperWhisper : chemin critique, option avancée, ou
      retrait.
- [ ] **N'ouvrir le niveau 3 (PCC) que si le local est mesurablement
      insuffisant**, et jamais par défaut.

### Phase 3 — exploratoire, sans engagement

- [ ] `SpeechDetector` : sensibilités OFF / LOW / MEDIUM / HIGH. Critère
      dominant : **ne jamais couper le premier mot**, bien avant le CPU gagné.
- [ ] Contexte d'écran par Vision/OCR. Fort potentiel sur les noms propres et
      les termes techniques, mais capture d'écran = données très sensibles.
      Jamais en continu, jamais sans un signe visible.
- [ ] App Intents / Siri. Pas une priorité.

---

## 8. Questions ouvertes

1. **Le modèle Apple on-device est-il bon en français ?** Tout le projet est
   franco-anglais. Un modèle excellent en anglais et médiocre en français ne
   sert à rien ici. À mesurer en premier, avant toute architecture.
2. **Que fait-il du franglais ?** « Tu as oublié les dependencies dans le
   useEffect » — un modèle qui « corrige » vers le français pur détruirait
   exactement ce que Sofler protège.
3. **La latence est-elle compatible avec la dictée ?** Le texte apparaît quand
   on a fini de parler ; c'est le total qui compte.
4. **Que se passe-t-il quand Apple met son modèle à jour ?** Comment détecter
   qu'un comportement a changé sans le découvrir par un rapport de bug ?
5. **Le cran doit-il dépendre de la destination ?** Écrire dans un fichier de
   notes et écrire dans un champ de code ne demandent pas la même liberté.
6. **Faut-il montrer la retouche ?** Un aperçu « avant / après » consultable
   après coup rendrait la dérive du sens détectable, au lieu d'invisible.
   Peut-être la meilleure réponse au risque de la section 4.

---

## 9. Installer la bêta sans risquer la machine de travail

**Ne pas installer macOS 27 bêta sur le Mac de travail.**

Deux façons propres :

- **Volume APFS séparé sur le disque interne.** Gratuit, aucun
  repartitionnement, démarrable, supprimable en une commande. L'espace est
  partagé avec le volume principal.
- **SSD externe.** Plus lent, mais totalement isolé.

Dans les deux cas, le corpus reste sur le système principal : il ne faut ni le
copier ni y toucher depuis la bêta.

---

## Sources

Vérifiées le 15 août 2026.

- [WWDC26 macOS guide — Apple Developer](https://developer.apple.com/wwdc26/guides/macos/)
- [WWDC26 Apple Intelligence guide — Apple Developer](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- [What's new in the Foundation Models framework — WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
- [Apple ouvre Foundation Models à tout fournisseur de LLM](https://dev.to/arshtechpro/wwdc-2026-apple-just-opened-the-foundation-models-framework-to-any-llm-provider-5ejn)
- [Apple confirme que le Siri de Gemini passe par Private Cloud Compute — 9to5Mac](https://9to5mac.com/2026/01/29/apple-confirms-gemini-powered-siri-will-use-private-cloud-compute/)
- [Apple présente Siri AI bâti sur Gemini — SiliconANGLE](https://siliconangle.com/2026/06/08/apple-debuts-siri-ai-personal-assistant-built-gemini/)
- [Apple choisit Gemini pour le nouveau Siri — CNBC](https://www.cnbc.com/2026/01/12/apple-google-ai-siri-gemini.html)

Document d'origine : [`notes/macos27.md`](../notes/macos27.md) — non versionné,
issu de ChatGPT, largement exact, corrigé ici sur le point local/nuage.
