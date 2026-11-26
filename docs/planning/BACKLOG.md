# Backlog – Projet iOS tracker Bluetooth anti-traçage

> **Mise à jour du 26/11 (PM-11)** : le projet passe à Xcode 16.2 et iOS 15 minimum, et tout se compile sur le MacBook Air de Clara. Les Macs prêtés ne servent plus : « Mac prêté » désigne ici le Mac qui héberge la centrale (désormais celui de Clara), dont les règles « sans état persistant » restent inchangées. Sur iPhone, « Face ID » se lit « biométrie (Face ID ou Touch ID) » et le mode `faceID` devient `biometrie` dans le code (valeur stockée inchangée). Voir `CLAUDE.md` §5 et §6.

> **Mise à jour du 26/11 (PM-11)** : le projet passe à Xcode 16.2 et iOS 15 minimum, et tout se compile sur le MacBook Air de Clara. Les Macs prêtés ne servent plus : « Mac prêté » désigne ici le Mac qui héberge la centrale (désormais celui de Clara), dont les règles « sans état persistant » restent inchangées. Sur iPhone, « Face ID » se lit « biométrie (Face ID ou Touch ID) » et le mode `faceID` devient `biometrie` dans le code (valeur stockée inchangée). Voir `CLAUDE.md` §5 et §6.

> **Statut : proposition préparée avec Claude le 23/11/2026 (version 2), à relire et valider par Clara.**
> Les responsables sont des propositions à confirmer avec le groupe.
> Colonne **Séance** : `23/11`, `24/11`, `25/11` (séances de travail), `15/12` (démo), `HS` (hors séance, sans Mac, seulement si le groupe est d'accord), `Continu`.
> Correspondance : 23/11 = J1 (clôture) et J2, 24/11 = J3, 25/11 = J4, 15/12 = J5.
> Priorités : **P1** indispensable, **P2** objectif, **P3** si le temps le permet.

## 1. Répartition des tâches proposée

| Membre | Rôle | Périmètre |
|---|---|---|
| Clara | Cheffe de projet et red team | Épopée PM (dépôt, jalons, journal, coordination), tests avec l'AirTag, dossier et soutenance ; épopée RT (attaque de l'app, rapports de failles), audit de l'app de l'autre groupe avec Aida |
| Aida | Architecte sécurité | Épopée SEC, relecture de toute PR touchant à la crypto, tests de sécurité (QA-3), appui à l'audit avec Clara |
| Rachel | Développeuse iOS | Balayage Bluetooth, détection et niveaux d'alerte (épopée IOS) |
| Eva | Développeuse iOS | Liste de confiance, biométrie (Face ID ou Touch ID), protections des données, interface (épopée TRU) |
| Onur | Développeur iOS | Côté Mac, appairage QR, canal chiffré et événements signés (épopée MAC), transport (ARCH-2) |

Tous : participent à l'architecture, au journal et à l'oral (chacun explique l'ensemble du code).

Clara cumule cheffe de projet et red team (rôle fixe, confirmé par le professeur) et ne code pas, pour rester indépendante de ce qu'elle attaque. Le code crypto est écrit par Onur, puis relu par Aida (qui ne l'écrit pas, pour que l'auteur et le relecteur restent différents). Voir `PLANNING.md` pour le repli si la chaîne sécurisée prend du retard.
Chaque PR est relue par un membre différent de l'auteur, et par Aida si elle touche à la crypto.

## 2. Épopée PM : gestion de projet et usage de l'IA

| ID | Titre | Séance | Responsable | Prio |
|---|---|---|---|---|
| PM-1 | Créer le dépôt Git : `main` protégée, `.gitignore` Swift et Xcode, modèles d'issue et de PR | 23/11 | Clara | P1 |
| PM-2 | Ajouter `CLAUDE.md` à la racine du dépôt | 23/11 | Clara | P1 |
| PM-3 | Créer les jalons GitHub avec leurs dates | 23/11 | Clara | P1 |
| PM-4 | Créer `docs/journal/<prenom>.md` pour chaque membre et le tenir à jour en continu | 23/11 puis Continu | Tous | P1 |
| PM-5 | Valider la répartition des tâches (ce document) | 23/11 | Clara | P1 |
| PM-6 | Regrouper les journaux dans `JOURNAL_PROMPTS.md` avec mention des fichiers individuels | HS ou 25/11 | Clara | P1 |
| PM-7 | Préparer l'oral individuel : relire le code de toute l'équipe | HS | Tous | P1 |
| PM-8 | Réinstaller l'app depuis le Mac de Clara avant l'audit et avant la démo (expiration à 7 jours). Mise à jour PM-11 : Clara est la seule à pouvoir compiler | 25/11 et 15/12 (en arrivant) | Clara | P1 |
| PM-9 | Fin de chaque séance : tout est poussé sur Git. Mise à jour PM-11 : les Macs prêtés ne servent plus ; chacun se déconnecte de GitHub sur toute machine qui n'est pas la sienne | Continu | Tous | P1 |
| PM-11 | Passer à Xcode 16.2 et iOS 15 minimum : code, tests, documentation, fiche de tests manuels (`docs/qualite/TESTS_PAR_PR.md`) | 26/11 | Clara (avec Claude) | P1 |
| PM-10 | Vidéo de secours de la démo et tag Git de la version démontrée | 25/11 | Un développeur (Clara si disponible) | P1 |

## 3. Épopée SEC : sécurité (Aida)

| ID | Titre | Séance | Responsable | Prio |
|---|---|---|---|---|
| SEC-1 | Finaliser le modèle STRIDE à partir du brouillon `docs/securite/STRIDE.md` | 23/11 | Aida | P1 |
| SEC-2 | Rédiger le dossier sécurité (STRIDE et choix crypto) | HS ou 25/11 | Aida | P1 |
| SEC-3 | Justifier les choix crypto (canal, signatures, hachage des identifiants, durée de purge) et mettre à jour le CLAUDE.md | 23/11 | Aida | P1 |
| SEC-4 | Relire chaque PR touchant à la crypto | Continu | Aida | P1 |
| SEC-5 | Rédiger le plan de tests de sécurité (rejeu, falsification, flood, entrées malformées) | 24/11 ou HS | Aida et Clara | P2 |
| SEC-6 | Implémenter ou valider les tests de sécurité | 25/11 | Aida | P2 |
| SEC-7 | Préparer la grille d'audit OWASP MASVS (8 domaines) avant la séance d'audit | 24/11 ou HS | Clara (red team), avec l'appui d'Aida | P1 |
| SEC-8 | Auditer l'app de l'autre groupe et rédiger le rapport | 25/11 | Clara (pilote) et Aida | P1 |
| SEC-9 | Corriger les failles remontées par l'audit de notre app | 25/11 | Selon la faille | P1 |
| SEC-10 | Revue RGPD (hachage, purge, consentement, minimisation) | HS | Aida | P2 |

## 4. Épopée ARCH : architecture (J2)

| ID | Titre | Séance | Responsable | Prio |
|---|---|---|---|---|
| ARCH-1 | Schéma iPhone ↔ Mac avec frontières de confiance | 23/11 | Aida et Onur (relu côté attaquant par Clara, RT-1) | P1 |
| ARCH-2 | Choisir le transport iPhone ↔ Mac et le justifier | 23/11 | Onur | P1 |
| ARCH-3 | Définir le modèle de données (appareil observé, balayage, alerte, historique) | 23/11 | Rachel et Eva | P1 |
| ARCH-4 | Spécifier les niveaux d'alerte et la règle de suivi inter-balayages | 23/11 | Rachel et Eva (relu par Clara) | P1 |
| ARCH-5 | Trancher les points « à définir » restants du CLAUDE.md : version minimale d'iOS fixée à 17 le 23/11, **remplacée le 26/11 par iOS 15 et Xcode 16.2 (PM-11)** pour inclure l'iPhone 7 ; reste le hachage et la crypto (SwiftUI, MVVM et Swift Testing sont décidés, Swift Testing sur iOS 15 à confirmer) | 23/11 | Le groupe | P1 |
| ARCH-6 | Spike avec l'AirTag : vérifier sur l'iPhone ce que le Bluetooth expose réellement (identifiants, rotation, annonces Find My) | 24/11 (première activité) | Rachel et Clara | P1 |
| ARCH-7 | Centrale sur un Mac prêté : fichiers temporaires, appairage et données de démo recréés à chaque séance, supprimés en fin de séance (décidé le 23/11) | 23/11 | Aida, Onur, Clara | P1 |

## 5. Épopée IOS : balayage et détection (Rachel)

| ID | Titre | Séance | Responsable | Prio | Dépend de |
|---|---|---|---|---|---|
| IOS-1 | Créer le projet Xcode et la signature avec compte gratuit | 23/11 | Rachel | P1 | ARCH-5 |
| IOS-2 | Balayage Bluetooth à la demande (environ 30 s), bouton « Contrôle de sécurité », permission demandée au moment du besoin | 24/11 | Rachel | P1 | IOS-1 |
| IOS-3 | Liste des appareils détectés (déduplication, plafond de sécurité) | 24/11 | Rachel | P1 | IOS-2 |
| IOS-4 | Détection des traceurs type Find My (après le spike) | 25/11 | Rachel | P2 | ARCH-6 |
| IOS-5 | Niveaux info et alerte (MVP) ; niveau critique ensuite | 24/11 puis 25/11 | Rachel | P1 pour info et alerte, P2 pour critique | IOS-3, ARCH-4 |
| IOS-6 | Comparaison entre balayages (même inconnu sur 2 balayages) et escalade | 25/11 | Rachel | P3 | IOS-5 |
| IOS-7 | Position relevée uniquement au moment du balayage | 25/11 | Rachel | P3 | IOS-2 |
| IOS-8 | Notifications locales | 25/11 | Rachel | P3 | IOS-5 |
| IOS-9 | Test final avec l'AirTag, scénario de démo | 25/11 | Rachel et Clara | P2 | IOS-4 |

## 6. Épopée TRU : liste de confiance et protection des données (Eva)

| ID | Titre | Séance | Responsable | Prio | Dépend de |
|---|---|---|---|---|---|
| TRU-1 | Mode d'enrôlement : nommer ses propres appareils | 24/11 | Eva | P1 | IOS-3 |
| TRU-2 | Stockage chiffré de la liste (AES-GCM, clé en Keychain « ThisDeviceOnly ») | 24/11 | Eva | P1 | SEC-3 |
| TRU-3 | Biométrie (Face ID ou Touch ID) avec repli sur le code obligatoire pour modifier la liste | 24/11 | Eva | P1 | TRU-2 |
| TRU-4 | Fichiers en protection « Complete », aperçu multitâche masqué, presse-papiers limité, logs sans donnée personnelle | 25/11 (début) | Eva | P1 | TRU-2 |
| TRU-5 | Écrans : balayage, résultats, liste de confiance, réglages (version minimale) | 24/11 | Eva | P2 | IOS-3 |
| TRU-6 | Hachage des identifiants et purge automatique | 25/11 | Eva | P2 | SEC-3 |

## 7. Épopée MAC : centrale et canal chiffré (Onur)

| ID | Titre | Séance | Responsable | Prio | Dépend de |
|---|---|---|---|---|---|
| MAC-1 | App Mac : réception des alertes et affichage (historique sans persistance durable) | 23/11 (début) puis 24/11 | Onur | P1 | ARCH-2, ARCH-7 |
| MAC-2 | Appairage par QR code avec vérification d'empreinte | 24/11 puis 25/11 | Onur | P1 | ARCH-1, SEC-3 |
| MAC-3 | Canal chiffré (ECDH éphémère, HKDF, AES-GCM) | 25/11 | Onur | P1 | MAC-2 |
| MAC-4 | Événements signés par la Secure Enclave, horodatage, nonce et compteur, vérification côté Mac | 25/11 | Onur | P1 | MAC-3 |
| MAC-5 | Historique chiffré sur la centrale | 25/11 | Onur | P3 | MAC-1 |
| MAC-6 | Rejet rapide des messages non authentifiés et limitation de débit | 25/11 | Onur | P3 | MAC-4 |
| MAC-7 | Purger l'historique et les clés d'appairage de la centrale en fin de séance (Mac prêté) | 25/11 et 15/12 | Onur | P1 | MAC-1 |

## 8. Épopée QA : tests

| ID | Titre | Séance | Responsable | Prio |
|---|---|---|---|---|
| QA-1 | Mettre en place le framework de test | 24/11 | Rachel | P2 |
| QA-2 | Tests unitaires : niveaux d'alerte, liste de confiance | 24/11 puis 25/11 | Rachel et Eva | P2 |
| QA-3 | Tests crypto : signature, vérification, rejeu | 25/11 | Aida | P1 |

## 9. Épopée RT : red team (Clara)

| ID | Titre | Séance | Responsable | Prio |
|---|---|---|---|---|
| RT-1 | Revue du schéma d'architecture côté attaquant : scénarios d'attaque sur chaque frontière de confiance | 23/11 | Clara | P1 |
| RT-2 | Préparer les scénarios et outils d'attaque (annonces Bluetooth falsifiées pour D1, messages malformés pour D4, rejeu pour T2) | 24/11 | Clara | P1 |
| RT-3 | Attaquer le MVP et rédiger le rapport de failles n°1 | 24/11 (fin de séance) | Clara | P1 |
| RT-4 | Attaquer la chaîne sécurisée (rejeu, usurpation, flood) et rédiger le rapport de failles n°2 | 25/11 | Clara | P2 |

## 10. Conventions GitHub proposées

**Jalons** : `J1 – Cadrage` (clôture le 23/11), `J2 – Architecture` (23/11), `J3 – MVP` (24/11), `J4 – Audit croisé` (25/11), `J5 – Soutenance` (15/12).

**Étiquettes** : `epic:pm`, `epic:sec`, `epic:arch`, `epic:ios`, `epic:tru`, `epic:mac`, `epic:qa`, `epic:rt`, `prio:P1`, `prio:P2`, `prio:P3`, `crypto` (relecture Aida obligatoire).

**Modèle d'issue** :
```
## Objectif
## Menace STRIDE visée (ex. D4, ou « aucune »)
## Critères d'acceptation
## Tests prévus
```

**Modèle de PR** : objectif, menace STRIDE visée, tests effectués, case « relu par un autre membre », case « relu par Aida (si crypto) », case « journal des prompts à jour ».