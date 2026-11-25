# Grille d'audit OWASP MASVS – Audit croisé de l'app de l'autre groupe (SEC-7)

> Responsables : Clara (pilote, domaines PLATFORM, CODE, RESILIENCE, PRIVACY, règles d'audit) et
> Aïda (domaines STORAGE, CRYPTO, AUTH, NETWORK). Utilisée pendant l'audit SEC-8.
> Références : `STRIDE.md` §10 (correspondance MASVS ↔ menaces), `PLAN_TESTS_SECURITE.md` (SEC-5).
>
> Version de MASVS utilisée : v2.1.0
> Les identifiants de contrôles (`MASVS-STORAGE-1`, etc.) viennent de MASVS v2 et doivent être
> vérifiés sur cette version.

## 1. Règles d'audit (proposition, à valider par Clara)

- On n'audite que le périmètre accepté par l'autre groupe (app, appareils, réseau). Toute action
  hors de ce périmètre (capture réseau, modification de fichiers, outil d'attaque) est demandée avant.
- Données fictives uniquement : dans la grille, le rapport, les captures et les prompts envoyés à une IA.
  Une capture qui montre un identifiant réel, une position ou une clé est floutée ou refaite.
- Tout outil utilisé (analyseur réseau, script) est un outil de test, pas une dépendance : il est
  signalé à l'équipe et à l'autre groupe avant usage.
- Chaque résultat « Non conforme » ou « Partiel » s'appuie sur une **preuve** : extrait de code
  (fichier et ligne), capture d'écran, ou étapes pour reproduire.
- Un contrôle « Conforme » ne prouve pas que l'app est sûre : il dit seulement que le test mené
  n'a rien trouvé (CLAUDE.md, section 7).
- Les gravités sont des propositions, discutées avec l'autre groupe avant le rapport final.

## 2. Légende

**Méthode**
- `Code` : lecture du code source (si l'autre groupe le fournit).
- `Appareil` : manipulation de l'app installée sur un iPhone.
- `Réseau` : observation du trafic sur le même réseau local (uniquement si autorisé).

Chaque contrôle prévoit si possible deux méthodes, pour rester utilisable sans le code source.

**Résultat** : `Conforme` · `Partiel` · `Non conforme` · `Non testable` (préciser pourquoi) · `N/A` (justifier).

**Gravité** (même échelle que `STRIDE.md`) : `Faible` · `Moyen` · `Élevé`.

## 3. App auditée

| Champ | Valeur |
|---|---|
| Groupe audité | |
| Sujet de l'app | |
| Version ou commit audité | |
| Appareil(s) et version d'iOS | |
| Accès au code source | Oui / Non |
| Périmètre accepté par le groupe | |
| Date, heure, auditeurs | |

---

## 4. Domaines rédigés par Aïda

### 4.1 MASVS-STORAGE – Stockage des données

Menaces liées dans notre STRIDE : T3, I2, I3, I5, I6, I7.

| N° | Contrôle | Ce qu'on vérifie | Méthode | Résultat | Preuve | Gravité |
|---|---|---|---|---|---|---|
| STO-01 | STORAGE-1 | Les fichiers contenant des données sensibles sont écrits avec une protection de fichier `complete` (`.completeFileProtection` à l'écriture ou attribut `FileProtectionType.complete`). | Code : rechercher `write(to:`, `FileManager`, `FileProtectionType`. | | | |
| STO-02 | STORAGE-1 | Aucune donnée sensible (identifiant, position, clé, jeton, liste d'appareils) dans `UserDefaults` ni dans un fichier `.plist` en clair. | Code : rechercher `UserDefaults`, `@AppStorage`, `PropertyListEncoder`. | | | |
| STO-03 | STORAGE-1 | Les secrets sont en Keychain avec une accessibilité `…ThisDeviceOnly` (par exemple `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), et jamais `kSecAttrAccessibleAlways`. | Code : rechercher `kSecAttrAccessible`, `SecItemAdd`. | | | |
| STO-04 | STORAGE-1 | Les données sensibles stockées sont chiffrées en plus de la protection iOS, si l'app le revendique. | Code ; demander au groupe où sont stockées les données. | | | |
| STO-05 | STORAGE-2 | Aucune donnée sensible dans les journaux : `print`, `NSLog`, `os_log`, `Logger`. | Code : rechercher ces appels. Appareil : lancer l'app depuis Xcode et lire la console pendant un parcours complet. | | | |
| STO-06 | STORAGE-2 | L'aperçu multitâche ne montre pas de donnée sensible (écran masqué ou flouté en arrière-plan). | Appareil : ouvrir un écran sensible, passer au sélecteur d'apps, faire une capture. | | | |
| STO-07 | STORAGE-2 | Les données sensibles ne sont pas copiables dans le presse-papiers général, ou l'app limite cet usage. | Appareil : tenter de copier ; Code : rechercher `UIPasteboard`. | | | |
| STO-08 | STORAGE-2 | Les données sensibles sont exclues des sauvegardes locales (Finder), ou rendues inutilisables hors de l'appareil (`ThisDeviceOnly`). | Code : rechercher `isExcludedFromBackup`, accessibilité Keychain. | | | |
| STO-09 | STORAGE-2 | Les champs de saisie sensibles désactivent l'autocorrection et la mémorisation clavier, si l'app en a. | Appareil ; Code : rechercher `autocorrectionDisabled`, `textContentType`. | | | |

### 4.2 MASVS-CRYPTO – Cryptographie

Menaces liées dans notre STRIDE : T1, T2, I1.

| N° | Contrôle | Ce qu'on vérifie | Méthode | Résultat | Preuve | Gravité |
|---|---|---|---|---|---|---|
| CRY-01 | CRYPTO-1 | Aucun algorithme obsolète : MD5, SHA-1 (pour la sécurité), DES, 3DES, RC4, mode ECB. | Code : rechercher `Insecure.MD5`, `Insecure.SHA1`, `CC_MD5`, `CC_SHA1`, `kCCAlgorithmDES`, `kCCOptionECBMode`. | | | |
| CRY-02 | CRYPTO-1 | Pas d'IV ou de nonce fixe, réutilisé ou dérivé d'un compteur mal géré pour AES-GCM ou ChaChaPoly. | Code : examiner chaque `seal(` et ce qui est passé en `nonce:`. | | | |
| CRY-03 | CRYPTO-1 | L'aléa des clés, nonces et jetons est cryptographique : CryptoKit ou `SecRandomCopyBytes`, jamais `random()`, `arc4random` pour une clé, `Int.random` ou `UUID()` comme secret. | Code : rechercher `random`, `UUID()`, `SecRandomCopyBytes`. | | | |
| CRY-04 | CRYPTO-1 | Pas de cryptographie maison (XOR, chiffrement « fait main », encodage base64 présenté comme du chiffrement). | Code : lire le module crypto. | | | |
| CRY-05 | CRYPTO-1 | Le chiffrement est authentifié (AES-GCM, ChaChaPoly, ou chiffrement + HMAC vérifié), et un échec d'authentification fait refuser la donnée. | Code ; Appareil ou Réseau : modifier un octet d'un message ou d'un fichier et observer le refus. | | | |
| CRY-06 | CRYPTO-2 | Aucune clé, mot de passe ou secret en dur dans le code ou les ressources (`Info.plist`, fichiers JSON). | Code : rechercher les longues chaînes base64 ou hexadécimales, `key`, `secret`, `password`. | | | |
| CRY-07 | CRYPTO-2 | Les clés sont générées sur l'appareil et stockées en Keychain ou en Secure Enclave, pas dans un fichier ni en mémoire persistante. | Code : rechercher `SecureEnclave`, `SecItemAdd`, `rawRepresentation`. | | | |
| CRY-08 | CRYPTO-2 | Une clé par usage (pas la même clé pour chiffrer et signer, ou pour deux protocoles différents) ; dérivation par HKDF avec un `info` distinct si plusieurs clés viennent d'un même secret. | Code. | | | |
| CRY-09 | CRYPTO-2 | Longueurs de clé suffisantes (AES 128 bits minimum, P-256 ou mieux pour les courbes). | Code. | | | |

### 4.3 MASVS-AUTH – Authentification

Menaces liées dans notre STRIDE : R2, E1.

| N° | Contrôle | Ce qu'on vérifie | Méthode | Résultat | Preuve | Gravité |
|---|---|---|---|---|---|---|
| AUT-01 | AUTH-1 | Si l'app parle à un serveur ou à un pair : l'authentification se fait côté serveur ou par clé, pas par une simple valeur envoyée par le client. Sinon : N/A, à justifier. | Code ; demander au groupe. | | | |
| AUT-02 | AUTH-2 | Face ID ou Touch ID ne repose pas sur le seul booléen renvoyé par `LAContext.evaluatePolicy` (contournable par instrumentation), mais protège un élément Keychain ou une clé avec `SecAccessControl` (`.userPresence`, `.biometryCurrentSet`). Voir MASTG-TEST-0266 cité dans notre STRIDE. | Code : rechercher `evaluatePolicy`, `SecAccessControlCreateWithFlags`. | | | |
| AUT-03 | AUTH-2 | Annuler ou échouer Face ID refuse l'action (échec en sécurité), sans contournement par un retour arrière ou un changement d'écran. | Appareil : annuler l'invite, échouer, revenir en arrière, relancer l'app. | | | |
| AUT-04 | AUTH-2 | Le comportement de repli (code de l'iPhone) est connu et assumé ; l'ajout d'une nouvelle empreinte ou d'un nouveau visage est pris en compte si l'app l'exige (`.biometryCurrentSet`). | Code ; Appareil. | | | |
| AUT-05 | AUTH-3 | Les opérations sensibles de l'app (à lister avec le groupe : modification de liste, suppression, export, appairage) exigent une authentification au moment de l'action, pas seulement à l'ouverture de l'app. | Appareil : laisser l'app ouverte, poser l'iPhone, tenter l'opération. | | | |
| AUT-06 | AUTH-3 | Les opérations sensibles sont tracées (historique, signalement) si l'app le revendique. | Appareil ; Code. | | | |

### 4.4 MASVS-NETWORK – Communications

Menaces liées dans notre STRIDE : S1, S2, I1, D2, E2.

| N° | Contrôle | Ce qu'on vérifie | Méthode | Résultat | Preuve | Gravité |
|---|---|---|---|---|---|---|
| NET-01 | NETWORK-1 | Pas d'exception ATS globale : pas de `NSAllowsArbitraryLoads` à `true` dans `Info.plist` ; toute exception est limitée et justifiée. | Code : lire `Info.plist`. | | | |
| NET-02 | NETWORK-1 | Tout le trafic sensible est chiffré, y compris sur le réseau local (pas de TCP ou UDP en clair). | Code : rechercher `NWConnection`, `URLSession`, `http://`. Réseau : capture, si autorisée. | | | |
| NET-03 | NETWORK-1 | Un message modifié en transit est refusé. | Réseau ou outil de test : modifier un octet et observer le refus. Code : vérification du tag ou de la signature. | | | |
| NET-04 | NETWORK-1 | Un message valide rejoué est refusé (compteur, nonce, horodatage ou équivalent). | Réseau ou outil de test : renvoyer un message capturé. Code : mécanisme anti-rejeu. | | | |
| NET-05 | NETWORK-1 | Les messages reçus sont validés en format et en taille avant usage (pas d'allocation selon une taille annoncée non bornée, pas de `!` ni `try!` sur les données reçues). | Code : lire le code de réception. Outil de test : message vide, tronqué, géant. | | | |
| NET-06 | NETWORK-2 | L'identité du pair est vérifiée : TLS avec épinglage pour un serveur du groupe, ou appairage avec clé ou empreinte pour un pair local. | Code ; Appareil : tenter un appairage avec un autre pair. | | | |
| NET-07 | NETWORK-2 | Un client non appairé, ou présentant une autre clé, est refusé. | Outil de test ou second appareil, si autorisé. | | | |
| NET-08 | NETWORK-1 | Une coupure réseau ne fait pas afficher un état faussement rassurant et ne bloque pas les fonctions locales de sécurité. | Appareil : couper le Wi-Fi pendant l'usage. | | | |

---

## 5. Domaines rédigés par Clara

### 5.1 MASVS-PLATFORM – Interaction avec la plateforme

Menaces liées dans notre STRIDE : S4, T4, I3.

*À rédiger par Clara.*

### 5.2 MASVS-CODE – Qualité du code

Menaces liées dans notre STRIDE : T4, T5, D3.

*À rédiger par Clara.*

### 5.3 MASVS-RESILIENCE – Résistance à l'analyse et à la modification

Menaces liées dans notre STRIDE : RR3.

*À rédiger par Clara.*

### 5.4 MASVS-PRIVACY – Vie privée

Menaces et actifs liés dans notre STRIDE : I5, A7, A8.

*À rédiger par Clara.*

---

## 6. Synthèse (à remplir après l'audit)

| Domaine | Conformes | Partiels | Non conformes | Non testables / N/A | Constat le plus grave |
|---|---|---|---|---|---|
| STORAGE | | | | | |
| CRYPTO | | | | | |
| AUTH | | | | | |
| NETWORK | | | | | |
| PLATFORM | | | | | |
| CODE | | | | | |
| RESILIENCE | | | | | |
| PRIVACY | | | | | |

Les constats « Non conforme » et « Partiel » sont repris dans le rapport d'audit (SEC-8).
