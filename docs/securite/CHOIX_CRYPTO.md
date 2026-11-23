# Choix cryptographiques – Tracker Bluetooth anti-traçage

> Ce document justifie chaque choix crypto et le relie aux menaces de `STRIDE.md`.
> Règle de vérification (CLAUDE.md, section 5) : **aucun de ces choix n'est encore implémenté ni testé**.
> Les détails d'implémentation sont des propositions ; le format exact des messages relève de la
> spécification du protocole (tâche proposée, `docs/securite/PROTOCOLE.md`).

## 1. Principes

- **CryptoKit uniquement** : aucune primitive cryptographique écrite par l'équipe, aucune dépendance tierce.
- **Le réseau local n'est pas de confiance** : chaque message est chiffré et authentifié.
- **Échouer en sécurité** : toute erreur de vérification, de déchiffrement ou de format entraîne le rejet
  ou le verrouillage, jamais une ouverture.
- **Aléa** : uniquement celui de CryptoKit (génération de clés, nonces) ou de `SecRandomCopyBytes`.
- **Clés** : jamais dans le code, jamais dans le dépôt, jamais dans les logs.

## 2. Récapitulatif

| Usage | Choix | Menaces couvertes |
|---|---|---|
| Signature des événements | P-256 ECDSA, clé Secure Enclave non exportable | S2, R1, T1 |
| Appairage | QR code contenant l'empreinte SHA-256 de la clé d'identité du Mac, confirmation par l'utilisateur | S1, S4, E2 |
| Échange de clés | P-256 ECDH éphémère, clés éphémères signées par les clés d'identité | S1, I1 |
| Dérivation de clés | HKDF-SHA256 | I1 |
| Chiffrement du canal | AES-256-GCM | T1, I1 |
| Anti-rejeu | Compteur par session, nonce, horodatage (tolérance 60 s) | T2 |
| Hachage des identifiants | HMAC-SHA256, clé secrète en Keychain « ThisDeviceOnly » | I5 |
| Durée de purge | 72 h | I5 |
| Stockage de la liste de confiance | AES-256-GCM, clé en Keychain « ThisDeviceOnly » | T3, I6 |
| Modification de la liste | Face ID avec repli sur le code de l'iPhone, historique des modifications | E1, R2 (risque résiduel RR6) |

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
   (et l'adresse de connexion). L'iPhone vérifie que la clé reçue du Mac correspond à cette empreinte.
   Une empreinte courte est affichée sur les deux écrans et confirmée par l'utilisateur, ce qui authentifie
   aussi la clé de l'iPhone auprès du Mac.
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
- TLS 1.3 via Network.framework avec clé pré-partagée : plus éprouvé, mais montre moins la maîtrise des
  mécanismes, ce qui est un objectif du projet. Le risque est assumé (RR7, voir `STRIDE.md`).
- ChaChaPoly : aussi sûr qu'AES-GCM et disponible dans CryptoKit ; AES-GCM est retenu pour être accéléré
  matériellement sur les appareils Apple et pour utiliser la même primitive que le stockage local.

**Recommandations d'implémentation (propositions).**
- Dériver **deux clés distinctes**, une par sens (iPhone → Mac et Mac → iPhone), avec deux valeurs de `info`
  différentes.
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
en « ThisDeviceOnly ».

**Pourquoi.**
- Un hachage simple (SHA-256) d'un identifiant connu peut être recalculé par n'importe qui pour vérifier si un
  appareil donné a été vu. Avec une clé secrète, le haché n'a de sens que sur cet iPhone, y compris pour les
  données envoyées au Mac prêté.
- Le haché reste identique tant que la clé ne change pas, ce qui permet la comparaison entre balayages (IOS-6).
- Renouveler la clé rend les anciennes données impossibles à relier aux nouvelles (minimisation, RGPD).

**Option écartée.** SHA-256 simple : réversible par recalcul si l'identifiant est connu ou prévisible.

**[Hypothèse]** L'identifiant à hacher (identifiant fourni par iOS ou champ d'une annonce Find My) dépend du
spike ARCH-6.

### 3.5 Durée de purge : 72 h

**Décision.** Les identifiants hachés, les résultats de balayage et les positions sont supprimés après 72 h.

**Pourquoi.**
- Un suivi se joue sur des heures ou quelques jours : 24 h risquerait de casser la comparaison entre balayages.
- Les données concernent surtout des appareils de **tiers** (voisins, passants) : 7 jours les conserverait
  plus longtemps que nécessaire (minimisation, RGPD).
- Sur le Mac prêté, tout est de toute façon purgé en fin de séance (MAC-7).

**Exception.** L'historique des modifications de la liste de confiance (R2) concerne les appareils de
l'utilisateur lui-même : il conserve les 20 dernières entrées, sans limite de durée.

### 3.6 Liste de confiance : stockage et modification

**Décision.**
- Liste et historique des modifications chiffrés avec AES-256-GCM, clé stockée dans le Keychain en
  « ThisDeviceOnly », fichiers en protection « Complete ».
- Modification soumise à Face ID avec repli sur le code de l'iPhone.
- Chaque modification est inscrite dans l'historique avec le mode d'authentification ; une modification faite
  avec le code est signalée à la prochaine ouverture.

**Pourquoi.** « ThisDeviceOnly » empêche la clé de quitter l'appareil (pas de sauvegarde ni de migration).
AES-GCM détecte toute altération du fichier (T3) ; en cas d'échec de déchiffrement, l'app ne considère aucun
appareil comme de confiance (échec en sécurité).

**Risque résiduel.** Un proche qui connaît le code peut modifier la liste (RR6). L'historique ne l'empêche pas,
mais le rend visible.

## 4. Algorithmes et pratiques interdits

| Interdit | Raison |
|---|---|
| MD5, SHA-1 | Collisions connues |
| Mode ECB | Laisse apparaître la structure des données |
| IV ou nonce fixe | Avec AES-GCM, réutiliser un nonce casse la confidentialité et l'authenticité |
| Aléa non cryptographique (`random()`, `Int.random` pour des clés) | Prévisible |
| Clé ou secret en dur | Exposé dans le binaire et le dépôt |
| Secret ECDH utilisé directement comme clé | Doit passer par HKDF |

## 5. Points ouverts

| Point | Pourquoi c'est à trancher | Qui |
|---|---|---|
| **Purge glissante ou par période** | Renouveler la clé HMAC « à chaque purge » suppose une purge globale toutes les 72 h. Avec une purge glissante (chaque donnée supprimée 72 h après sa collecte), il n'y a pas de moment unique pour changer la clé. Proposition : clé renouvelée toutes les 72 h et suppression de toutes les données hachées avec l'ancienne ; limite : un traceur vu juste avant et juste après le renouvellement n'est pas relié. | Aïda |
| **Lecture de la liste sans Face ID** | La liste doit être lue à chaque balayage, sans demander Face ID, mais sa modification doit l'exiger. Avec une seule clé de chiffrement, protéger la modification par le Keychain bloquerait aussi la lecture. Proposition : clé de chiffrement accessible quand l'iPhone est déverrouillé, et liste **signée** par une seconde clé Secure Enclave dont l'usage exige Face ID ou le code ; la signature est vérifiée à chaque lecture. Ainsi la protection ne repose pas seulement sur la logique de l'app. | Aïda, avec Eva (TRU-2, TRU-3) |
| Identifiant Bluetooth à hacher | Dépend du spike | Après ARCH-6 |
| Format exact des messages, sel et `info` HKDF | À fixer dans `PROTOCOLE.md` | Aïda et Onur |

## 6. Tests associés (QA-3, SEC-6)

| Choix | Tests à écrire |
|---|---|
| Signatures | Signature valide acceptée ; message signé par une autre clé rejeté ; signature tronquée ou vide rejetée |
| Appairage | Clé du Mac différente de l'empreinte du QR : refus ; QR malformé : rejet sans plantage |
| Canal | Un octet modifié : déchiffrement refusé ; message chiffré avec la clé de l'autre sens : refusé |
| Anti-rejeu | Message rejoué, compteur inférieur ou égal, horodatage hors tolérance : rejet |
| Hachage | Même identifiant, même clé : même haché ; clé différente : haché différent |
| Purge | Donnée de plus de 72 h : supprimée |
| Liste de confiance | Fichier modifié : refus et aucun appareil de confiance ; modification sans authentification : impossible |

