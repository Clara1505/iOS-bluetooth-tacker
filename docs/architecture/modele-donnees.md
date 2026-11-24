# ARCH-3 – Modèle de données (appareil observé, balayage, alerte, historique)

> **Statut : proposition, à valider par le groupe.**
> Responsables : Rachel et Eva. Relecture : Clara (côté attaquant), Aida (champs touchant aux données personnelles).
> Référence : `docs/securite/STRIDE.md` (SEC-1), section 11 « Décisions ».
> Règle de vérification (CLAUDE.md, section 5) : tout comportement non testé est marqué **[Hypothèse]**.

## 1. Principes

- **Aucun identifiant Bluetooth brut n'est stocké.** Seul son HMAC-SHA256 est conservé, avec une clé secrète en Keychain « ThisDeviceOnly » (I5, A8).
- **Aucune position continue.** La position n'est relevée qu'au moment d'un balayage (A7), et seulement si le niveau 3 est retenu (IOS-7).
- **Observations purgées après 72 h** (I5). La durée de purge concerne les observations, pas la liste de confiance (voir question Q2).
- **Stockage iPhone** : fichiers chiffrés AES-GCM, protection « Complete » (TRU-4). **Stockage Mac** : aucune persistance durable (ARCH-7, MAC-1).

## 2. Entités

### 2.1 Observation (iPhone)

Un appareil vu lors d'un balayage. Une observation par appareil et par balayage.

| Champ | Type | Remarque |
|---|---|---|
| `idHache` | Data (32 octets) | HMAC-SHA256 de l'identifiant Bluetooth. Jamais l'identifiant brut. |
| `vuLe` | Date | Horodatage de l'observation. |
| `idBalayage` | UUID | Renvoie au balayage d'origine. |
| `estDeConfiance` | Bool | Calculé à partir de la liste de confiance au moment du balayage. |

Rétention : 72 h, puis suppression (test prévu dans STRIDE I5).

### 2.2 Balayage (iPhone)

Un « Contrôle de sécurité » d'environ 30 s.

| Champ | Type | Remarque |
|---|---|---|
| `id` | UUID | |
| `debut` | Date | |
| `duree` | Durée | Environ 30 s. |
| `resultat` | enum : `complet`, `controleImpossible` | **Un balayage interrompu ou sans Bluetooth n'est jamais `complet`** (D4). |
| `position` | latitude, longitude, optionnel | Présent seulement si le niveau 3 est retenu (IOS-7). |

Rétention : 72 h, comme les observations.

### 2.3 Appareil de confiance (iPhone)

Un appareil que l'utilisateur a nommé lui-même lors de l'enrôlement (TRU-1).

| Champ | Type | Remarque |
|---|---|---|
| `nom` | String | Saisi par l'utilisateur. Donnée personnelle, stockée chiffrée. |
| `idHache` | Data (32 octets) | Même calcul que pour l'observation. |
| `ajouteLe` | Date | |

La liste est stockée chiffrée (AES-GCM, clé en Keychain, TRU-2). Son accès est conditionné à Face ID, avec repli sur le code de l'iPhone (décision STRIDE, E1 et RR6).

### 2.4 Historique des modifications de la liste (iPhone)

Traçabilité demandée par R2.

| Champ | Type | Remarque |
|---|---|---|
| `date` | Date | |
| `action` | enum : `ajout`, `suppression` | |
| `nomAppareil` | String | |
| `modeAuth` | enum : `faceID`, `code` | Une entrée `code` est signalée à la prochaine ouverture. |

Limité aux 20 dernières entrées. Chiffré avec la liste. Non supprimable depuis l'interface (STRIDE, R2).

### 2.5 Alerte (iPhone, puis transmise au Mac)

| Champ | Type | Remarque |
|---|---|---|
| `id` | UUID | |
| `niveau` | enum : `info`, `alerte`, `critique` | Règles détaillées dans `niveaux-alerte.md` (ARCH-4). |
| `idHache` | Data (32 octets) | Appareil concerné. |
| `balayagesRefs` | [UUID] | Balayages ayant servi à la décision. |
| `date` | Date | |

Une alerte transmise au Mac est un événement signé avec compteur et nonce (MAC-4, T2). Le Mac ne la recalcule pas.

### 2.6 Historique de la centrale (Mac)

Liste des alertes reçues pendant la séance, **en mémoire uniquement**. Elle est purgée en fin de séance (MAC-7, I4). Aucune persistance durable (ARCH-7).

## 3. Relations

- Un balayage contient plusieurs observations (1 à N).
- Une alerte renvoie à un appareil (par `idHache`) et à un ou plusieurs balayages.
- Un appareil de confiance correspond à zéro ou une observation par balayage.

## 4. Questions ouvertes (à trancher par le groupe, pas par ce document)

- **Q1 – Renouvellement de la clé HMAC.** La clé est renouvelée à chaque purge (STRIDE, section 11). Or les `idHache` dépendent de cette clé. Après une purge, un appareil de confiance enregistré avant ne correspond plus à ses nouvelles observations. Cela touche directement S3 et TRU-1. Options à présenter à Aida :
  - (a) ne pas renouveler la clé tant que la liste de confiance existe ;
  - (b) recalculer les `idHache` de la liste à chaque purge ;
  - (c) demander un nouvel enrôlement après chaque purge.
- **Q2 – La liste de confiance est-elle soumise à la purge de 72 h ?** Hypothèse de ce document : non, puisqu'elle contient des choix de l'utilisateur. À confirmer.
- **Q3 – Identifiant TRU-7.** Le STRIDE cite TRU-7 pour l'historique des modifications (R2), mais le backlog ne prévoit que TRU-1 à TRU-6. Faut-il créer TRU-7 ou intégrer l'historique à TRU-3 ?

## 5. Menaces et contre-mesures liées

| Menace | Contre-mesure dans ce modèle |
|---|---|
| I5 | `idHache` au lieu de l'identifiant brut ; purge à 72 h |
| I2 | Aucun champ de position ou d'identifiant brut dans les logs (à vérifier en relecture) |
| I6 | Fichiers en protection « Complete » |
| R2 | Historique des modifications, 20 entrées, non supprimable |
| T3 | Liste chiffrée, échec de déchiffrement = verrouillage |

## 6. Tests prévus

- Relecture du modèle par Clara (vérification côté attaquant) et par Aida (données personnelles).
- Tests unitaires sur données fictives, à écrire avec IOS-3 et QA-2 (Swift Testing) :
  - suppression des observations plus anciennes que 72 h ;
  - historique limité à 20 entrées ;
  - aucun identifiant brut présent dans les structures sérialisées.
- Test de purge de la centrale en fin de séance (MAC-7), à faire sur le Mac prêté.
