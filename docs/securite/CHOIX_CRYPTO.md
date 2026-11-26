# Choix cryptographiques – Tracker Bluetooth anti-traçage

> **Mise à jour du 26/11 (PM-11)** : le projet passe à Xcode 16.2 et iOS 15 minimum, et tout se compile sur le MacBook Air de Clara. Les Macs prêtés ne servent plus : « Mac prêté » désigne ici le Mac qui héberge la centrale (désormais celui de Clara), dont les règles « sans état persistant » restent inchangées. Sur iPhone, « Face ID » se lit « biométrie (Face ID ou Touch ID) » et le mode `faceID` devient `biometrie` dans le code (valeur stockée inchangée). Voir `CLAUDE.md` §5 et §6.

> Ce document justifie chaque choix crypto et le relie aux menaces de `STRIDE.md`.
> Règle de vérification (CLAUDE.md, section 5) : **aucun de ces choix n'est encore implémenté ni testé**.
> Les comportements non vérifiés sont marqués **[Hypothèse]**. Le format exact des messages relève de la
> spécification du protocole (tâche proposée, `docs/securite/PROTOCOLE.md`).

## 1. Principes

- **CryptoKit uniquement** : aucune primitive cryptographique écrite par l'équipe, aucune dépendance tierce.
- **Le réseau n'est pas de confiance**, quel que soit le transport : chaque message est chiffré et authentifié
  par notre protocole.
- **Échouer en sécurité** : toute erreur de vérification, de déchiffrement ou de format entraîne le rejet
  ou le verrouillage, jamais une ouverture.
- **Authentification liée à une clé** : conformément au principe du MASTG (test MASTG-TEST-0266),
  l'authentification de l'utilisateur est imposée par une clé protégée par le système, et non par une simple
  condition dans le code de l'app.
- **Aléa** : uniquement celui de CryptoKit (génération de clés, nonces) ou de `SecRandomCopyBytes`.
- **Clés** : jamais dans le code, jamais dans le dépôt, jamais dans les logs.

## 2. Récapitulatif

| Usage | Choix | Statut | Menaces couvertes |
|---|---|---|---|
| Signature des événements | P-256 ECDSA, clé Secure Enclave non exportable | Décidé | S2, R1, T1 |
| Appairage | QR code contenant l'empreinte SHA-256 de la clé d'identité du Mac, code court confirmé par l'utilisateur | Décidé | S1, S4, E2 |
| Échange de clés | P-256 ECDH éphémère, clés éphémères signées par les clés d'identité | Décidé | S1, I1 |
| Dérivation de clés | HKDF-SHA256, une clé par sens | Décidé | I1 |
| Chiffrement du canal | AES-256-GCM | Décidé | T1, I1 |
| Anti-rejeu | Compteur par session, nonce, horodatage (tolérance 60 s) | Décidé | T2 |
| Transport | Network framework avec Bonjour recommandé (Multipeer Connectivity en alternative) | Recommandation, décision d'Onur (ARCH-2) | – (transport non fiable) |
| Hachage des identifiants | HMAC-SHA256, clé secrète stable en Keychain « ThisDeviceOnly » | Décidé | I5 |
| Durée de purge | 72 h, purge glissante | Décidé | I5 |
| Confidentialité de la liste de confiance | AES-256-GCM, clé en Keychain « ThisDeviceOnly » | Décidé | I6 |
| Intégrité de la liste de confiance | Signature par une clé Secure Enclave dédiée, protégée par `userPresence`, avec numéro de version | Décidé | T3, E1 |
| Modification de la liste | Biométrie (Face ID ou Touch ID) avec repli sur le code de l'iPhone, historique des modifications | Décidé | E1, R2 (risques résiduels RR6, RR8) |

## 3. Justification détaillée

### 3.1 Signatures : P-256 ECDSA avec clé Secure Enclave

**Décision.** Chaque iPhone possède une clé d'identité de signature P-256 générée dans la Secure Enclave
(`SecureEnclave.P256.Signing.PrivateKey`). Elle signe les clés éphémères lors de l'échange et chaque événement
envoyé au Mac.

**Pourquoi.**
- La Secure Enclave ne gère que la courbe P-256 : c'est le seul moyen d'avoir une clé **non exportable**,
  qui ne quitte jamais la puce, même si l'app ou le système de fichiers est compromis.
- Une signature prouve l'origine du message (S2) et apporte la non-répudiation (R1), ce que le chiffrement
  symétrique seul ne fait pas : les deux côtés partagent la même clé de session.

**Options écartées.**
- Ed25519 (`Curve25519.Signing`) : moderne et rapide, mais non disponible dans la Secure Enclave, donc clé exportable.
- HMAC seul sur les événements : authentifie le canal, mais ne prouve pas quel appareil a signé.

**Côté Mac.** La centrale tourne sur un Mac prêté sans état persistant (ARCH-7) : sa clé d'identité est générée
au lancement, gardée en mémoire et perdue en fin de séance. L'appairage est donc refait à chaque séance.

### 3.2 Canal iPhone ↔ Mac : protocole maison avec CryptoKit

**Décision.** Protocole conçu par l'équipe, assemblé à partir de primitives CryptoKit.

**Étapes (principe, détail dans `PROTOCOLE.md`).**
1. **Appairage.** Le Mac affiche un QR code qui contient l'empreinte SHA-256 de sa clé d'identité publique
   et l'information de connexion (selon le transport retenu, voir 3.7). L'iPhone vérifie que la clé reçue du Mac
   correspond à cette empreinte. Un code court est affiché sur les deux écrans et confirmé par l'utilisateur,
   ce qui authentifie aussi la clé de l'iPhone auprès du Mac.
2. **Échange de clés.** À chaque session, chaque côté génère une paire ECDH éphémère
   (`P256.KeyAgreement.PrivateKey`) et **signe sa clé publique éphémère avec sa clé d'identité**.
   Chaque côté vérifie la signature de l'autre avant de poursuivre.
3. **Dérivation.** Le secret partagé est dérivé avec HKDF-SHA256 en clés AES de 256 bits. Le champ `info`
   contient un libellé de version du protocole et les clés publiques échangées, pour lier les clés dérivées
   à cette session précise.
4. **Chiffrement.** Chaque message est chiffré avec AES-GCM (`AES.GCM.seal`), nonce généré par CryptoKit.

**Pourquoi.**
- **Clés éphémères** : la compromission ultérieure d'une clé d'identité ne permet pas de déchiffrer les
  sessions passées (confidentialité persistante, I1).
- **Signature des clés éphémères** : un échange ECDH non authentifié est vulnérable à l'homme du milieu (S1).
  C'est ce lien entre clé éphémère, clé d'identité et empreinte du QR code qui rend l'appairage utile.
- **HKDF** : un secret ECDH brut ne doit pas servir directement de clé ; HKDF en extrait des clés uniformes
  et permet d'en dériver plusieurs.
- **AES-GCM** : chiffrement authentifié, toute modification d'un octet fait échouer le déchiffrement (T1).

**Options écartées.**
- **TLS 1.3 via Network framework avec clé pré-partagée** : plus éprouvé, mais montre moins la maîtrise des
  mécanismes, ce qui est un objectif du projet. Le risque est assumé (RR7 dans `STRIDE.md`) et compensé par
  une documentation étape par étape et les tests QA-3.
- **ChaChaPoly** : aussi sûr qu'AES-GCM et disponible dans CryptoKit ; AES-GCM est retenu pour être accéléré
  matériellement sur les appareils Apple et pour utiliser la même primitive que le stockage local.

**Règles d'implémentation (décidées le 23/11).**
- Dériver **deux clés distinctes**, une par sens (iPhone → Mac et Mac → iPhone), avec deux valeurs de `info`
  différentes, pour qu'un message ne puisse pas être renvoyé à son émetteur.
- Ne jamais fournir de nonce fixe à `AES.GCM.seal` : laisser CryptoKit le générer.
- Fixer le sel HKDF et le libellé `info` dans `PROTOCOLE.md`, et ne plus les changer sans revue.

### 3.3 Anti-rejeu

**Décision.** Chaque message signé contient un compteur, un nonce et un horodatage.
- **Compteur** strictement croissant par session : mécanisme principal. Tout message dont le compteur est
  inférieur ou égal au dernier accepté est rejeté.
- **Nonce** unique : identifie le message.
- **Horodatage** : rejet si l'écart avec l'horloge du Mac dépasse 60 s.

**Pourquoi.** Les clés de session étant éphémères, un message d'une ancienne session ne se déchiffre plus :
le compteur suffit à bloquer le rejeu dans la session en cours. L'horodatage est un garde-fou, avec une
tolérance large parce que l'horloge d'un Mac prêté peut être décalée ; une tolérance trop courte provoquerait
de faux rejets pendant la démo.

**Option écartée.** Horodatage seul : dépend de la synchronisation des horloges, et laisse rejouer un message
pendant toute la fenêtre de tolérance.

### 3.4 Hachage des identifiants : HMAC-SHA256

**Décision.** Les identifiants des appareils observés sont stockés sous la forme
`HMAC-SHA256(clé secrète, identifiant)`. La clé (256 bits) est générée sur l'iPhone et stockée dans le Keychain
en « ThisDeviceOnly ». Elle est **stable** : générée au premier lancement après installation, elle n'est renouvelée
que lors d'une réinitialisation des données de l'app (voir 3.8).

**Pourquoi.**
- Un hachage simple (SHA-256) d'un identifiant connu peut être recalculé par n'importe qui pour vérifier si un
  appareil donné a été vu. Avec une clé secrète, le haché n'a de sens que sur cet iPhone, y compris pour les
  données envoyées au Mac prêté.
- Le haché reste identique tant que la clé ne change pas, ce qui permet la comparaison entre balayages (IOS-6).
- La clé n'est pas renouvelée périodiquement : la purge glissante supprime déjà toute donnée de plus de 72 h,
  et la centrale est purgée en fin de séance. Il ne reste donc pas d'ancienne donnée à rendre non reliable ;
  la minimisation est assurée par la purge, pas par la clé.
- Un renouvellement périodique couperait la comparaison entre balayages : un traceur vu juste avant et juste
  après le renouvellement ne serait pas relié (faux négatif sur A1).

**Options écartées.**
- SHA-256 simple : réversible par recalcul si l'identifiant est connu ou prévisible.
- Renouvellement de la clé toutes les 72 h avec purge globale : crée un faux négatif à chaque renouvellement.
- Deux clés en chevauchement : pas de rupture, mais trop complexe à coder, tester et expliquer pour un gain faible.

**[Hypothèse]** L'identifiant à hacher (identifiant fourni par iOS ou champ d'une annonce Find My) dépend du
spike ARCH-6.

### 3.5 Durée de purge : 72 h, purge glissante

**Décision.** Purge glissante : chaque identifiant haché, résultat de balayage et position est supprimé
72 h après sa collecte.

**Pourquoi.**
- Un suivi se joue sur des heures ou quelques jours : 24 h risquerait de casser la comparaison entre balayages.
- Les données concernent surtout des appareils de **tiers** (voisins, passants) : 7 jours les conserverait
  plus longtemps que nécessaire (minimisation, RGPD).
- Sur le Mac prêté, tout est de toute façon purgé en fin de séance (MAC-7).

**Exception.** L'historique des modifications de la liste de confiance (R2) concerne les appareils de
l'utilisateur lui-même : il conserve les 20 dernières entrées, sans limite de durée.

### 3.6 Liste de confiance : stockage, intégrité et modification

**Décidé.**
- Modification soumise à la biométrie (Face ID ou Touch ID) avec repli sur le code de l'iPhone (E1).
- Historique des modifications (R2) : date, action, appareil, mode d'authentification ; 20 dernières entrées ;
  non supprimable depuis l'interface ; toute modification faite avec le code est signalée à la prochaine ouverture.

**Décidé le 23/11 (solution B, avec les remarques d'Eva, qui porte TRU-2 et TRU-3).**

*Confidentialité.* La liste **et** son historique sont chiffrés ensemble avec AES-256-GCM. La clé AES est stockée
dans le Keychain en « accessible quand l'iPhone est déverrouillé, ThisDeviceOnly », sans exigence
d'authentification, pour pouvoir lire la liste à chaque balayage. Fichiers en protection « Complete ».

*Intégrité.* Une **seconde clé**, de signature P-256, est créée dans la Secure Enclave, distincte de la clé
d'identité du canal. Son contrôle d'accès est `userPresence` : la Secure Enclave exige la biométrie (Face ID ou Touch ID) ou le code de
l'iPhone avant chaque signature. Le bloc qui représente cette clé et sa clé publique sont stockés dans le
Keychain en « ThisDeviceOnly », jamais à côté du fichier : sinon un attaquant pourrait remplacer le fichier et
la clé publique ensemble.

*Données signées.* La signature porte, dans cet ordre, sur : un libellé fixe (`liste-confiance-v1`), le numéro
de version, puis le bloc chiffré complet produit par AES-GCM (nonce, données chiffrées, étiquette). Ainsi,
ni la version ni le contenu ne peuvent être modifiés séparément, et une signature produite pour un autre usage
ne peut pas être réutilisée ici.

*Numéro de version.* Il est inclus dans les données signées et recopié dans le Keychain après chaque
modification. À la lecture, une liste dont la version est inférieure à celle du Keychain est refusée : cela
empêche de remettre en place une ancienne liste correctement signée. Une version supérieure, avec une
signature valide, est acceptée et recopiée dans le Keychain (cas d'une interruption entre l'écriture du
fichier et la mise à jour du Keychain).

*Lecture (à chaque balayage).* Déchiffrer, vérifier la signature avec la clé publique du Keychain, vérifier la
version. Aucune authentification n'est demandée. En cas d'échec, aucun appareil n'est considéré comme de
confiance et l'utilisateur est prévenu (échec en sécurité).

*Modification.* Ajouter l'entrée d'historique, rechiffrer, incrémenter la version, signer (la Secure Enclave
demande la biométrie ou le code), écrire le fichier, puis mettre à jour la version dans le Keychain.

**Pourquoi.**
- La protection ne repose pas sur une condition dans le code de l'app : sans biométrie ni code, il est impossible
  de produire une liste valide. Une authentification par LocalAuthentication seule (`evaluatePolicy`) se
  contourne par instrumentation (MASTG-TEST-0266).
- Une clé **asymétrique** est nécessaire : avec une clé symétrique (HMAC), la même clé sert à créer et à
  vérifier ; si elle exige la biométrie pour signer, elle l'exige aussi pour vérifier, donc à chaque balayage.

**Choix du contrôle d'accès : `userPresence` plutôt que `biometryCurrentSet` (décidé le 23/11).**
`biometryCurrentSet` invaliderait la clé si un visage ou un doigt est ajouté, mais seul il exige la biométrie
sans repli sur le code, ce qui contredit E1. Et puisque E1 autorise le code, une personne qui connaît le code
peut déjà signer : `biometryCurrentSet` ne la gênerait pas davantage, tout en imposant un parcours de
recréation de la clé. `userPresence` est donc cohérent avec E1.

**Options écartées.**
- Solution A (une seule clé AES et `evaluatePolicy` avant modification) : authentification contournable par
  instrumentation.
- Solution C (biométrie à chaque ouverture de l'app) : gêne l'usage principal, un contrôle rapide.

**Limites et risques résiduels.**
- **RR6** : une personne qui connaît le code peut modifier la liste ; l'historique le rend visible, sans l'empêcher.
- **RR8** : sur un iPhone déverrouillé, la liste est lisible sans biométrie (I7). La signature empêche la
  falsification, pas la lecture ; la liste ne révèle que les noms des appareils de l'utilisateur.
- Sur un iPhone jailbreaké, la vérification elle-même peut être contournée (hors modèle, H3).
- Le MASTG prévoit un test sur les API qui autorisent un repli vers une authentification non biométrique :
  la red team pourra relever le repli sur le code. Justification : RR6 et l'historique R2.

**[Hypothèses à tester].**
- Comportement d'une clé Secure Enclave protégée par `userPresence` : invite biométrique (Face ID ou Touch ID) au moment de signer,
  repli sur le code.
- Lecture de la clé publique sans authentification.
- Moyen fiable de savoir si l'utilisateur s'est authentifié par la biométrie ou par le code, pour l'historique R2.
  Piste : évaluer d'abord la biométrie seule avec un `LAContext`, puis le code en cas d'échec, et transmettre
  ce contexte à l'opération de signature. Le mode enregistré dépend alors de la logique de l'app.

### 3.7 Transport (recommandation sécurité ; décision d'Onur en ARCH-2)

**Recommandation.** Network framework, avec découverte par Bonjour : le Mac annonce un service, l'iPhone s'y
connecte. C'est la voie recommandée par Apple, avec plus de contrôle et un débogage plus simple.

**Alternative acceptable.** Multipeer Connectivity, à condition de considérer son chiffrement comme
inexistant dans notre modèle.
- Apple recommande désormais Network framework (note technique TN3213 sur la migration).
- Il active toujours le Wi-Fi direct entre appareils, ce qui peut ralentir le réseau.
- Son fonctionnement est peu documenté : sa sécurité ne peut pas être justifiée dans le dossier ; sans
  certificats, son chiffrement ne protège pas contre l'homme du milieu.
- **[Hypothèse]** S'il utilise le Bluetooth, il pourrait interférer avec le balayage BLE.
- Menaces supplémentaires : nom annoncé visible par les appareils proches (utiliser un nom aléatoire),
  invitations en masse (rejet et limitation de débit), pair connecté non appairé (seul l'appairage QR donne
  le statut de pair de confiance).

**Dans les deux cas.** Le transport est traité comme non fiable : notre protocole (3.2, 3.3) s'applique
intégralement par-dessus.

**[Hypothèse à tester en priorité le 24/11]** Le Wi-Fi de l'école laisse-t-il l'iPhone et le Mac prêté
communiquer ? Les réseaux de campus isolent souvent les appareils entre eux.

### 3.8 Premier lancement après installation

**Décision.** Au premier lancement après installation, l'app supprime **tous** ses éléments du Keychain
(clé AES de la liste, clé HMAC, bloc de la clé Secure Enclave de la liste, clé publique associée, numéro de
version, clé d'identité si elle est conservée) puis repart d'une liste de confiance vide.

**Pourquoi.**
- **[Hypothèse]** Les éléments du Keychain peuvent survivre à la désinstallation de l'app, alors que les
  fichiers sont supprimés. Sans ce nettoyage, d'anciennes clés et un ancien numéro de version resteraient
  sans les données correspondantes.
- Perdre la liste va dans le sens de la sécurité : une liste vide signifie que tous les appareils sont inconnus,
  donc plus d'alertes, pas moins. Un attaquant qui réinstallerait l'app pour effacer l'historique R2 effacerait
  aussi son traceur de la liste.

## 4. Algorithmes et pratiques interdits

| Interdit | Raison |
|---|---|
| MD5, SHA-1 | Collisions connues |
| Mode ECB | Laisse apparaître la structure des données |
| IV ou nonce fixe | Avec AES-GCM, réutiliser un nonce casse la confidentialité et l'authenticité |
| Aléa non cryptographique (`random()`, `Int.random` pour des clés) | Prévisible |
| Clé ou secret en dur | Exposé dans le binaire et le dépôt |
| Secret ECDH utilisé directement comme clé | Doit passer par HKDF |
| Authentification par `evaluatePolicy` seule pour protéger une donnée | Contournable par instrumentation |
| Clé publique de vérification stockée à côté des données signées | Remplaçable en même temps que les données |

## 5. Points ouverts

| Point | Pourquoi c'est à trancher | Qui |
|---|---|---|
| Transport | Recommandation en 3.7 | Onur (ARCH-2) |
| Identifiant Bluetooth à hacher | Dépend du spike | Après ARCH-6 |
| Format exact des messages, sel et `info` HKDF | À fixer dans `PROTOCOLE.md` | Aïda et Onur |

**Hypothèses à vérifier sur les iPhones** : persistance du Keychain après désinstallation ; comportement de
`userPresence` sur une clé Secure Enclave ; lecture de la clé publique sans authentification ; détection du mode
d'authentification (biométrie ou code) ; communication iPhone ↔ Mac sur le Wi-Fi de l'école.

## 6. Tests associés (QA-3, SEC-6)

| Choix | Tests à écrire |
|---|---|
| Signatures | Signature valide acceptée ; message signé par une autre clé rejeté ; signature tronquée ou vide rejetée |
| Appairage | Clé du Mac différente de l'empreinte du QR : refus ; QR malformé : rejet sans plantage |
| Canal | Un octet modifié : déchiffrement refusé ; message chiffré avec la clé de l'autre sens : refusé |
| Anti-rejeu | Message rejoué, compteur inférieur ou égal, horodatage hors tolérance : rejet |
| Transport | Pair connecté mais non appairé : aucune donnée acceptée ; tentatives de connexion en masse : centrale utilisable |
| Hachage | Même identifiant, même clé : même haché ; clé différente : haché différent |
| Purge | Donnée de plus de 72 h : supprimée ; donnée de moins de 72 h : conservée |
| Premier lancement | Après installation : nouvelles clés, liste vide, aucun ancien élément du Keychain |
| Liste de confiance | Fichier modifié : refus et aucun appareil de confiance ; ancienne version correctement signée remise en place : refus ; signature par une autre clé : refus ; annulation de la biométrie et du code : modification impossible ; modification avec le code : signalée à la prochaine ouverture |