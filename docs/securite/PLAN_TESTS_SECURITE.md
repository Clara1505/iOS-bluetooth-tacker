# Plan de tests de sécurité – Tracker Bluetooth anti-traçage

> **Mise à jour du 26/11 (PM-11)** : le projet passe à Xcode 16.2 et iOS 15 minimum, et tout se compile sur le MacBook Air de Clara. Les Macs prêtés ne servent plus : « Mac prêté » désigne ici le Mac qui héberge la centrale (désormais celui de Clara), dont les règles « sans état persistant » restent inchangées. Sur iPhone, « Face ID » se lit « biométrie (Face ID ou Touch ID) » et le mode `faceID` devient `biometrie` dans le code (valeur stockée inchangée). Voir `CLAUDE.md` §5 et §6.

> Références : `STRIDE.md` (menaces), `CHOIX_CRYPTO.md` (mécanismes), CLAUDE.md section 7 (tests).
> Règle de vérification (CLAUDE.md, section 5) : un test qui passe ne prouve pas que la fonction est sûre.
> Chaque test cherche à **casser** le mécanisme, pas seulement à vérifier qu'il fonctionne.

## 1. Objectif et périmètre

Ce plan couvre les quatre familles de l'issue SEC-5 :

| Famille | Menaces visées |
|---|---|
| Rejeu | T2, T3 (ancienne version de la liste) |
| Falsification | S1, S2, S4, T1, T3, E2 |
| Flood | D1, D2 |
| Entrées malformées | T4, T5, D3 |

Les autres tests de sécurité (authentification, confidentialité, échec en sécurité, purge) sont listés en
section 7 pour mémoire ; ils relèvent d'autres tâches.

## 2. Principes

- **Chaque test cite la menace STRIDE qu'il vise.** Une menace élevée sans test est un trou à signaler.
- **Résultat attendu = comportement sûr**, défini en section 3, et pas seulement « ça ne plante pas ».
- **Tests unitaires d'abord** pour tout ce qui peut être simulé (crypto, parsing, règles de rejet) :
  ils sont rapides, rejouables, et ne dépendent ni du Mac prêté ni du réseau de l'école.
- **Tests sur appareil** pour ce qui ne se simule pas : comportement Bluetooth réel, Secure Enclave,
  biométrie (Face ID ou Touch ID), réseau local.
- **Pas d'outil tiers sans validation de l'équipe** : l'attaquant réseau est un petit client de test écrit en
  Swift dans le projet (section 4), pas un outil téléchargé.
- **Aucune donnée réelle** dans les jeux de test : identifiants, noms et positions sont fictifs.

## 3. Ce que « réussi » veut dire

Un test de sécurité est réussi si **toutes** ces conditions sont remplies :

1. L'entrée malveillante est **rejetée**.
2. L'app **ne plante pas** et reste utilisable.
3. L'**état est inchangé** : compteur, liste de confiance, historique, clés.
4. **Aucune donnée sensible** n'apparaît dans les logs (identifiants, positions, clés).
5. Le message d'erreur est **générique** : il ne dit pas à l'attaquant ce qui a échoué (signature, compteur,
   format), pour ne pas lui servir d'indice.
6. En cas de doute, l'app **verrouille** au lieu d'ouvrir (échec en sécurité).

## 4. Moyens de test

| Code | Type | Moyen |
|---|---|---|
| U | Unitaire | Framework de test du projet (**à définir**, QA-1) ; fonctions de crypto et de parsing appelées directement avec des données construites |
| C | Client attaquant | Petite cible de test Swift qui se connecte à la centrale et envoie des messages construits à la main (rejoués, modifiés, malformés, en masse) |
| A | Appareil | iPhones, Mac prêté, AirTag ; manipulation manuelle, résultat noté dans le compte rendu |

**[Hypothèse]** Le flood Bluetooth réel est difficile à produire sans matériel dédié. Pistes à valider par
l'équipe : plusieurs iPhones qui émettent en même temps, ou une app d'émulation BLE sur un téléphone de test.
À défaut, le test reste unitaire (données simulées) et la limite est notée dans le dossier.

## 5. Tests

Colonnes : **Type** (U, C, A, voir section 4), **Prio** (P1 indispensable, P2 objectif, P3 si le temps le permet).
Les tests réseau (C) dépendent du format des messages, à fixer dans `PROTOCOLE.md`.

### 5.1 Rejeu

| ID | Menace | Scénario | Résultat attendu | Type | Prio |
|---|---|---|---|---|---|
| REJ-1 | T2 | Renvoyer à l'identique un message valide déjà accepté | Rejet, compteur inchangé | U, C | P1 |
| REJ-2 | T2 | Message valide avec un compteur égal au dernier accepté | Rejet | U | P1 |
| REJ-3 | T2 | Message valide avec un compteur inférieur au dernier accepté | Rejet | U | P1 |
| REJ-4 | T2 | Message valide avec un horodatage décalé de +61 s, puis de −61 s | Rejet dans les deux cas | U | P1 |
| REJ-5 | T2 | Message valide avec un horodatage décalé de +59 s | Accepté (vérifie que la tolérance n'est pas trop stricte) | U | P2 |
| REJ-6 | T2 | Rejouer dans une nouvelle session un message capturé lors d'une session précédente | Échec du déchiffrement, rejet | U, C | P1 |
| REJ-7 | T1, T2 | Renvoyer à l'iPhone un message qu'il a lui-même émis (réflexion) | Rejet : la clé de l'autre sens ne le déchiffre pas | U | P2 |
| REJ-8 | T3 | Remettre en place une ancienne version de la liste de confiance, correctement signée | Refus, aucun appareil de confiance, utilisateur prévenu | U | P1 |
| REJ-9 | T3 | Liste de version supérieure à celle du Keychain, signature valide (interruption simulée) | Acceptée, version recopiée dans le Keychain | U | P2 |

### 5.2 Falsification

| ID | Menace | Scénario | Résultat attendu | Type | Prio |
|---|---|---|---|---|---|
| FAL-1 | T1 | Modifier un octet des données chiffrées d'un message | Échec du déchiffrement, rejet | U, C | P1 |
| FAL-2 | T1 | Modifier un octet de l'étiquette ou du nonce AES-GCM | Rejet | U | P1 |
| FAL-3 | T1 | Changer le niveau d'alerte (« critique » en « info ») puis re-signer avec une autre clé | Rejet : signature non reconnue | U | P1 |
| FAL-4 | S2 | Message signé par une clé différente de celle de l'iPhone appairé | Rejet | U, C | P1 |
| FAL-5 | S2 | Signature vide, tronquée ou de mauvaise longueur | Rejet sans plantage | U | P1 |
| FAL-6 | S1 | Clé éphémère non signée, ou signée par une autre clé d'identité | Arrêt de l'échange de clés | U, C | P1 |
| FAL-7 | S1 | Mac dont la clé d'identité ne correspond pas à l'empreinte du QR code | Refus de l'appairage | A | P1 |
| FAL-8 | S4 | Scanner le QR code d'un autre Mac | Codes courts différents sur les deux écrans, appairage non confirmé | A | P2 |
| FAL-9 | E2 | Client connecté au niveau réseau mais jamais appairé, qui envoie des événements | Aucun événement accepté | C | P1 |
| FAL-10 | T3 | Modifier un octet du fichier de la liste de confiance | Refus, aucun appareil de confiance | U | P1 |
| FAL-11 | T3 | Liste valide mais signée par une autre clé que la clé dédiée | Refus | U | P1 |
| FAL-12 | T3 | Remplacer la clé publique de vérification par une autre (simulé par injection dans le test) | Refus : la liste ne se vérifie plus | U | P2 |
| FAL-13 | T3 | Modifier séparément le numéro de version sans toucher au bloc chiffré | Refus : la version fait partie des données signées | U | P1 |

### 5.3 Flood

| ID | Menace | Scénario | Résultat attendu | Type | Prio |
|---|---|---|---|---|---|
| FLO-1 | D1 | Balayage simulé avec un très grand nombre d'appareils distincts (ex. 10 000) | Plafond appliqué, pas de plantage, temps de traitement acceptable | U | P1 |
| FLO-2 | D1 | Même appareil annoncé des milliers de fois pendant un balayage | Une seule entrée après déduplication | U | P1 |
| FLO-3 | D1 | Balayage réel dans un lieu très fréquenté (amphi, couloir) | L'app reste utilisable, la liste reste lisible | A | P2 |
| FLO-4 | D2 | Envoi massif de messages non authentifiés à la centrale | Rejet rapide, centrale utilisable, alertes légitimes toujours reçues | C | P2 |
| FLO-5 | D2 | Ouvertures de connexion répétées sans terminer l'échange de clés | Limitation de débit, centrale utilisable | C | P3 |
| FLO-6 | D2, D3 | Message annonçant ou contenant une taille très supérieure au maximum | Rejet avant tout traitement, mémoire stable | U, C | P1 |
| FLO-7 | D2 | Si Multipeer est retenu : invitations en masse depuis un appareil proche | Rejet, centrale utilisable | A | P3 |

### 5.4 Entrées malformées

| ID | Menace | Scénario | Résultat attendu | Type | Prio |
|---|---|---|---|---|---|
| MAL-1 | T4 | QR code vide, trop long, ou dans un format inattendu (texte libre, URL) | Rejet sans plantage, message générique | U | P1 |
| MAL-2 | T4 | QR code avec une empreinte de mauvaise longueur ou mal encodée | Rejet | U | P1 |
| MAL-3 | T4 | QR code avec une information de connexion invalide | Rejet, aucune tentative de connexion | U | P2 |
| MAL-4 | D3 | Message réseau vide, tronqué, ou avec des champs manquants | Rejet sans plantage | U, C | P1 |
| MAL-5 | D3 | Longueur annoncée différente de la longueur réelle | Rejet | U | P1 |
| MAL-6 | D3 | Version de protocole inconnue | Rejet | U | P2 |
| MAL-7 | D3 | Valeurs extrêmes : compteur à 0 et à sa valeur maximale, horodatage très ancien ou très lointain | Rejet ou traitement prévu, sans dépassement ni plantage | U | P1 |
| MAL-8 | T5 | Annonce BLE avec champs vides, nom très long, données tronquées | Ignorée ou traitée sans plantage | U | P1 |
| MAL-9 | T3, D3 | Fichier de la liste vide, tronqué, ou rempli d'octets aléatoires | Refus, aucun appareil de confiance, pas de plantage | U | P1 |
| MAL-10 | D3 | Fuzzing simple : quelques milliers d'entrées aléatoires passées aux parseurs (QR, réseau, BLE) | Aucun plantage | U | P2 |
| MAL-11 | D3 | Relecture de code : aucun `!`, `try!` ni `fatalError` sur une donnée externe | Aucune occurrence (règle du CLAUDE.md) | Relecture | P1 |

## 6. Couverture des menaces

| Menace | Tests | Remarque |
|---|---|---|
| S1 | FAL-6, FAL-7 | |
| S2 | FAL-4, FAL-5 | |
| S3 | – | En attente du spike ARCH-6 |
| S4 | FAL-8 | |
| T1 | FAL-1, FAL-2, FAL-3, REJ-7 | |
| T2 | REJ-1 à REJ-7 | |
| T3 | REJ-8, REJ-9, FAL-10 à FAL-13, MAL-9 | |
| T4 | MAL-1 à MAL-3 | |
| T5 | MAL-8 | |
| D1 | FLO-1 à FLO-3 | Flood BLE réel limité par le matériel (section 4) |
| D2 | FLO-4 à FLO-7 | |
| D3 | MAL-4 à MAL-11, FLO-6 | |
| E2 | FAL-9 | |

## 7. Autres tests de sécurité (hors SEC-5, pour mémoire)

| Menace | Test | Tâche |
|---|---|---|
| E1, R2 | Annuler la biométrie puis le code : modification impossible ; modification avec le code : signalée à la prochaine ouverture | TRU-3, QA-3 |
| D4 | Lancer un contrôle avec le Bluetooth coupé, puis avec la permission refusée : « contrôle impossible » affiché | IOS-2 |
| I1 | Capture du trafic : aucun contenu en clair | MAC-3 |
| I2 | Lecture de la console pendant un balayage : aucun identifiant ni position | TRU-4 |
| I3 | Passage en arrière-plan : aperçu masqué | TRU-4 |
| I4 | Après purge de fin de séance : aucune donnée ni clé sur le Mac | MAC-7 |
| I5 | Donnée de plus de 72 h supprimée ; premier lancement après installation : nouvelles clés | TRU-6 |

## 8. Planning proposé

| Séance | Tests | Qui |
|---|---|---|
| 24/11 | Choix du framework (QA-1) ; tests unitaires de parsing QR et BLE (MAL-1, MAL-2, MAL-8, FLO-1, FLO-2) dès que le code existe | Rachel, Aïda |
| 25/11 (début) | Tests unitaires crypto et anti-rejeu P1 (REJ, FAL, MAL-4 à MAL-7, MAL-9, FLO-6) | Aïda (QA-3, SEC-6) |
| 25/11 | Client attaquant et tests sur appareil P1 (FAL-7, FAL-9) ; puis P2 si le temps le permet | Aïda, Onur |
| Avant l'audit | Relecture MAL-11 sur tout le code | Aïda |

Les tests P1 doivent être passés avant l'audit croisé (SEC-8). Les tests non réalisés sont listés dans le dossier
comme limites.

## 9. Compte rendu d'exécution

Pour chaque test exécuté, noter dans `docs/securite/RESULTATS_TESTS.md` :

| ID | Date | Commit testé | Résultat (réussi / échoué / non réalisé) | Preuve (sortie du test, capture) | Remarque |
|---|---|---|---|---|---|

Un test échoué devient une issue `fix` avec l'étiquette `crypto` si besoin, et cite la menace visée.

## 10. Points ouverts

| Point | Dépend de |
|---|---|
| Framework de test | QA-1 (décision du groupe) |
| Format exact des messages, nécessaire aux tests C et MAL-4 à MAL-7 | `PROTOCOLE.md` (Aïda et Onur) |
| Transport, qui conditionne FLO-7 | ARCH-2 (Onur) |
| Moyen de produire un flood Bluetooth réel | Validation de l'équipe (section 4) |
| Tests de S3 | Spike ARCH-6 |

