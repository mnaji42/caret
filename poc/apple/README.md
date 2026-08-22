# Ce que macOS 26 sait déjà faire

Quatre programmes, chacun éprouvant une question posée pendant le projet. Tous
mesurés sur M4 Pro, macOS 26.6, sans rien télécharger.

```bash
xcrun swiftc -O -parse-as-library stack.swift  -o /tmp/stack  && /tmp/stack
xcrun swiftc -O -parse-as-library clean.swift  -o /tmp/clean  && /tmp/clean
xcrun swiftc -O -parse-as-library stream.swift -o /tmp/stream && /tmp/stream
xcrun swiftc -O -parse-as-library guided.swift -o /tmp/guided && /tmp/guided
```

## `stack.swift` — l'œil et la tête

`Vision.RecognizeTextRequest` lit une capture d'écran : dix lignes sur dix sur
un faux mail, adresse, accents, « 12 400 € HT », dates.
`FoundationModels.SystemLanguageModel` est le modèle de langage du système.
Enchaînés, ils répondent à un mail lu à l'écran, budget compris.

```
./stack --chain mail.png "Réponds : j'accepte le mardi 9 à 14h30"
→ « Bonjour Claire, Je suis disponible le mardi 9 septembre à 14h30,
   et je confirme le budget de 12 400 € HT. »
```

## `clean.swift` — le texte nettoyé, sans CrisperWhisper

Sur trois dictées réelles du corpus : **2,5 à 3,9 s pour 40 mots**. La syntaxe
est redressée — « ben ça marche pas, enfin ça marche » devient « c'est qu'il ne
marche pas. Enfin, il marche » — et `useEffect`, `dependencies`,
`component React` passent intacts.

Ce qu'il ne fait pas, et ne peut pas faire : corriger une erreur de
transcription. Il ne voit pas l'audio. « Effects de fonctionnement » devient
« Les effets de fonctionnement » — mieux écrit, toujours faux.

## `stream.swift` — le flux ne sauve pas la latence

Premier fragment à **2,1 s**, texte complet à 4,4 s. Le flux montre le texte
plus tôt mais ne raccourcit pas l'attente du premier mot : c'est le coût du
préremplissage, pas du décodage. À savoir avant de compter dessus.

## `guided.swift` — la sortie structurée, elle, tient ses promesses

Avec une consigne en prose, le modèle range juste mais bavarde : « Le fichier
**"bugs.md"** contient des problèmes de sécurité. » Avec `@Generable`, il ne
*peut plus* répondre autre chose :

```
bugs      │ Le bouton de login plante lorsque le token expire.
idees     │ Ajouter un mode sombre automatique le soir pourrait améliorer…
reunions  │ Rendez-vous avec Claire mardi 9h30
```

Trois notes en 5,4 s. Le routage est juste les trois fois. La troisième perd
« 14h30 » — un modèle de cette taille lâche les détails, et il faut le savoir
avant de lui confier un agenda.
