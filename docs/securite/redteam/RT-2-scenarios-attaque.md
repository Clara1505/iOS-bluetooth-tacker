# RT-2 – Scénarios et outils d'attaque (red team)

> **Mise à jour du 26/11 (PM-11)** : le projet passe à Xcode 16.2 et iOS 15 minimum, et tout se compile sur le MacBook Air de Clara. Les Macs prêtés ne servent plus : « Mac prêté » désigne ici le Mac qui héberge la centrale (désormais celui de Clara), dont les règles « sans état persistant » restent inchangées. Sur iPhone, « Face ID » se lit « biométrie (Face ID ou Touch ID) » et le mode `faceID` devient `biometrie` dans le code (valeur stockée inchangée). Voir `CLAUDE.md` §5 et §6.

> **Statut : proposition préparée avec Claude le 25/11/2026, à relire et valider par Clara (red team), puis à relire par Aïda.**
> Responsable : Clara. Issue : RT-2 (#54), jalon J3.
> Références : `docs/securite/STRIDE.md`, `docs/securite/PLAN_TESTS_SECURITE.md` (SEC-5), `docs/securite/redteam/RT-1-revue-schema-attaquant.md` (RT-1),
> `docs/architecture/schema-architecture.md`, `docs/architecture/transport.md`, `docs/architecture/niveaux-alerte.md` (§9), `docs/securite/CHOIX_CRYPTO.md`.
> Règle de vérification (CLAUDE.md, section 5) : **aucun de ces scénarios n'a été exécuté.** Tout comportement non testé est marqué **[Hypothèse]**.

## 1. Objet et lien avec le plan de tests SEC-5

- Le plan SEC-5 décrit des **tests** par mécanisme (unitaires, client attaquant, appareil). Ce document décrit les **scénarios d'attaque** vus du côté de l'attaquant, menés par la red team, de bout en bout et sur appareil.
- Pour ne pas dupliquer SEC-5, chaque scénario renvoie aux identifiants du plan (REJ-, FAL-, FLO-, MAL-) quand le même mécanisme y est déjà testé.
- RT-2 ajoute les scénarios que SEC-5 ne couvre pas : ceux issus de la revue RT-1 (constats C1 à C3), ceux que `niveaux-alerte.md` §9 confie à RT-2 (identifiant qui change, balayages rapprochés, message rejoué), et les scénarios d'appareil.
- Les scénarios sont **exécutés** par RT-3 (rapport de failles n°1, MVP iPhone) puis RT-4 (rapport n°2, chaîne sécurisée). Les failles sont décrites dans ces rapports, pas ici.

## 2. Règles d'engagement (proposition)

1. **Périmètre** : notre app, notre centrale, les appareils du groupe. Aucune attaque ni collecte visant des appareils de tiers (voisins, passants). Les observations Bluetooth de tiers sont des données réelles : ni commitées, ni collées dans un prompt (CLAUDE.md, section 5).
2. **Réseau** : les tests réseau (F3) se font sur le hotspot du groupe prévu dans `transport.md` §2, **jamais sur le Wi-Fi de l'école** pour du flood ou des trames malformées.
3. **Intensité progressive** pour les scénarios de saturation (D1, D2) : paliers croissants, durée courte, arrêt dès le premier signe de dégradation.
4. **Données fictives** pour tout jeu de test : identifiants, noms, empreintes, contenus de QR.
5. **Pas d'outil tiers sans validation de l'équipe** (SEC-5 §2). Tout outil est listé en §5 avec son statut.
6. **Accord préalable** de la personne concernée avant de tester sur son iPhone ou sur son code.
7. **Chaque exécution est notée** (date, commit testé, résultat, preuve) dans `docs/securite/RESULTATS_TESTS.md` (SEC-5 §9).
8. **Un test réussi ne prouve pas que la fonction est sûre** : on cherche aussi à la casser (CLAUDE.md, section 7).

## 3. Lecture du catalogue

- **Résultat attendu** = comportement sûr, au sens de SEC-5 §3 : entrée rejetée, pas de plantage, état inchangé, aucune donnée sensible dans les logs, message d'erreur générique, échec en sécurité.
- **Moyen** : `U` unitaire, `C` client attaquant (cible de test Swift, SEC-5 §4), `A` appareil (iPhone, Mac prêté, AirTag), comme dans SEC-5 §4. `Mac` signifie que le Mac prêté lui-même est nécessaire.
- **Prio** : P1 à exécuter avant l'audit croisé, P2 objectif, P3 si le temps le permet.
- **Bloqué** : le scénario dépend d'une décision ou d'un résultat qui n'existe pas encore.

## 4. Catalogue des scénarios

### 4.1 Frontière F1 : Bluetooth → iPhone

| ID | Menace | Scénario (ce que fait l'attaquant) | Résultat attendu | Réf. SEC-5 | Moyen | Prio |
|---|---|---|---|---|---|---|
| RT2-01 | D4 | Couper le Bluetooth avant le balayage, puis pendant ; refuser la permission ; quitter l'app, verrouiller l'écran ou passer en arrière-plan avant la fin des 30 s | « Contrôle impossible », jamais « Aucun appareil inconnu » ; aucun changement de niveau (`niveaux-alerte.md` §2, §6) | §7 (D4, IOS-2) | A | P1 |
| RT2-02 | D1 | Balayage dans un lieu très fréquenté, avec en plus les iPhones du groupe émettant des annonces génériques (identifiants fictifs) | Plafond appliqué avec avertissement, app utilisable, liste lisible | FLO-1 à FLO-3 | A | P2 |
| RT2-03 | T5, D3 | Annonces BLE aux champs vides, au nom très long, aux données tronquées | Ignorées ou traitées sans plantage ni log sensible | MAL-8 | U ; A si un émetteur est validé (§5) | P1 (U), P2 (A) |
| RT2-04 | H1, RR2 | Balayer deux fois de suite un même appareil du groupe (ex. l'AirTag de Clara, un iPhone), comparer les identifiants hachés vus d'un balayage à l'autre | **[Hypothèse]** Si l'identifiant change, un même traceur est compté comme plusieurs appareils et le suivi est contourné. Ici l'objectif est de **mesurer et documenter** RR2, pas de réussir ou d'échouer | – (spike ARCH-6) | A | P1 |
| RT2-05 | Suivi | Deux balayages d'un même appareil de test espacés juste en dessous, puis juste au-dessus, de la fenêtre F | Niveau « info » ou « alerte » conforme à la règle ; aucune baisse silencieuse de niveau (`niveaux-alerte.md` §5) | – | A | P2 |
| RT2-06 | S3 | Faire passer un appareil inconnu pour un appareil de la liste de confiance | **Bloqué** : dépend du critère « même appareil » (Q2 d'ARCH-4) et du spike ARCH-6 | – | A | À définir |

### 4.2 Frontière F2 : QR code et appairage

| ID | Menace | Scénario (ce que fait l'attaquant) | Résultat attendu | Réf. SEC-5 | Moyen | Prio |
|---|---|---|---|---|---|---|
| RT2-07 | S1, S4 | Présenter un QR dont l'empreinte est celle d'un autre Mac, ou une empreinte modifiée d'un octet | Appairage refusé ; codes courts différents sur les deux écrans | FAL-7, FAL-8 | A | P1 |
| RT2-08 | T4 | QR vide, très long, au format inattendu (texte libre, URL), à l'empreinte mal encodée, aux informations de connexion invalides | Rejet sans plantage, message générique, aucune tentative de connexion | MAL-1 à MAL-3 | U (P1) ; A (P2) | P1 |
| RT2-09 | S4, E2 | Confirmer l'appairage sur un seul écran, ou avec des codes courts qui ne correspondent pas | **[Hypothèse]** L'appairage n'aboutit pas sans confirmation concordante sur les deux écrans (`schema-architecture.md` §3, phase 1). Comportement exact à écrire dans `PROTOCOLE.md` | – (constat C1 de RT-1) | A | P1 |
| RT2-10 | S1, E2 | Pendant que l'iPhone légitime s'apparie, un second client (client attaquant) se connecte à la centrale, avant puis après l'iPhone | Seul le pair qui a scanné le QR et confirmé le code est apparié ; le second est rejeté sans gêner le premier | – (constat C1) | C + A | P1 |
| RT2-11 | S1 | Répéter les tentatives d'appairage et de confirmation pour voir si le nombre d'essais est limité | **[Hypothèse]** Limite d'essais ou code assez long pour résister ; à spécifier dans `PROTOCOLE.md` | – (constat C1) | C | P2 |

### 4.3 Frontière F3 : réseau local iPhone ↔ Mac

| ID | Menace | Scénario (ce que fait l'attaquant) | Résultat attendu | Réf. SEC-5 | Moyen | Prio |
|---|---|---|---|---|---|---|
| RT2-12 | T2 | Capturer un message valide, le renvoyer dans la session, après déconnexion, puis dans une nouvelle session | Rejet à chaque fois ; compteur inchangé ; l'alerte n'est pas dupliquée dans l'historique | REJ-1 à REJ-6 | C + A | P1 |
| RT2-13 | T2, S1 | Rejouer une poignée de main enregistrée (clé éphémère signée) vers la centrale, puis vers l'iPhone | Aucune session exploitable créée, pas de plantage. Dépend de `PROTOCOLE.md` | – (constat C4) | C | P2 |
| RT2-14 | T1, S2 | Modifier un octet d'un message, le niveau d'alerte, ou signer avec une autre clé ; signature vide ou tronquée ; clé éphémère non signée | Rejet, état inchangé | FAL-1 à FAL-6 | C | P1 |
| RT2-15 | D3 | En-tête de taille 0 puis 0xFFFFFFFF ; trame de plus de 64 Ko ; trame tronquée ; longueur annoncée différente de la longueur réelle ; version de protocole inconnue | Connexion fermée sans plantage et sans allocation excessive ; mémoire stable | MAL-4 à MAL-6, FLO-6 | C | P1 |
| RT2-16 | D2 | Ouvrir une connexion, envoyer l'en-tête puis plus rien ; ouvrir de nombreuses connexions de ce type | **[Hypothèse]** Délai d'attente ou limite de connexions ; la centrale reste utilisable pour l'iPhone légitime (constat C2 de RT-1 : non spécifié) | FLO-5 (P3 dans SEC-5) | C | P2 |
| RT2-17 | D2 | Envoi massif de messages non authentifiés, par paliers croissants | Rejet rapide ; la centrale reste utilisable et reçoit toujours les alertes légitimes | FLO-4 | C | P2 |
| RT2-18 | E2 | Client connecté mais jamais apparié, qui envoie des événements | Aucun événement accepté | FAL-9 | C | P1 |
| RT2-19 | D5 | Couper le réseau (hotspot) pendant une alerte | L'iPhone ne plante pas et garde l'alerte affichée localement (`transport.md` §5) | – | A | P2 |

### 4.4 Frontière F4 : Mac prêté

| ID | Menace | Scénario (ce que fait l'attaquant) | Résultat attendu | Réf. SEC-5 | Moyen | Prio |
|---|---|---|---|---|---|---|
| RT2-20 | I4 | Mettre une **valeur marqueur fictive** dans les données de démo, faire la purge de fin de séance, fermer l'app, puis chercher le marqueur sur le disque, dans les logs et dans les rapports de plantage **de notre séance uniquement** | Aucune occurrence. **[Hypothèse]** : la mémoire peut être écrite sur disque par le système (constat C3 de RT-1) | §7 (I4, MAC-7) | Mac | P1 |
| RT2-21 | I2 | Lire la console pendant un balayage et pendant un appairage | Aucun identifiant, position, clé ou jeton | MAL-11, §7 (I2) | A + Mac | P1 |
| RT2-22 | E3 | Après la séance, vérifier que les comptes Apple et GitHub sont déconnectés et qu'aucun secret ne reste dans le dépôt cloné | Checklist de fin de séance (PM-9) respectée | – | Mac | P1 |

### 4.5 Frontière F5 : utilisateur → iPhone

| ID | Menace | Scénario (ce que fait l'attaquant) | Résultat attendu | Réf. SEC-5 | Moyen | Prio |
|---|---|---|---|---|---|---|
| RT2-23 | E1 | Annuler la biométrie (Touch ID sur iPhone 7, Face ID sur iPhone 11 Pro Max) puis le code, ou échouer l'authentification, pour modifier la liste de confiance | Modification impossible | §7 (E1, TRU-3) | A | P1 |
| RT2-24 | R2, RR6 | Un proche qui connaît le code ajoute un traceur à la liste de confiance | Ajout possible (risque RR6 accepté) mais **signalé** à la prochaine ouverture et inscrit dans l'historique non supprimable. On vérifie aussi que le traceur ajouté ne déclenche plus d'alerte | §7 (R2) | A | P1 |
| RT2-25 | T3 | Fichier de la liste modifié, vide, aléatoire, ou ancienne version correctement signée remise en place | Refus, aucun appareil de confiance, utilisateur prévenu, pas de plantage | REJ-8, FAL-10 à FAL-13, MAL-9 | U (P1) ; A (P2, si l'accès au fichier est possible) | P1 |
| RT2-26 | I3, I6 | Passer en arrière-plan puis ouvrir le sélecteur d'apps ; vérifier la protection des fichiers de l'app | Aperçu masqué ; attribut de protection « Complete » présent | §7 (I3), TRU-4 | A + relecture | P2 |

## 5. Outils : besoins et statut

| ID | Besoin | Statut | Remarque |
|---|---|---|---|
| O1 | **Client attaquant réseau** : cible de test Swift qui se connecte à la centrale et envoie des messages construits à la main (rejoués, modifiés, malformés, en masse) | À créer | Prévu par SEC-5 §4. Écrit dans le projet, pas téléchargé. **Qui l'écrit ?** (voir §7). Le format des messages dépend de `PROTOCOLE.md`, qui n'existe pas encore |
| O2 | **Générateur de QR de test** : QR dont le contenu est fictif et volontairement invalide (RT2-07, RT2-08) | À valider | Un outil de génération de QR est un outil tiers : validation de l'équipe nécessaire avant usage |
| O3 | **Émetteur BLE de test** : plusieurs iPhones du groupe ou une app d'émulation BLE sur un téléphone de test (RT2-02, RT2-03) | À valider | SEC-5 §4 : « difficile sans matériel dédié ». À défaut, les tests restent unitaires et la limite est notée dans le dossier |
| O4 | **Valeur marqueur fictive** pour RT2-20 | À définir | Une chaîne sans signification, générée pour la séance, jamais réutilisée |
| O5 | **Compte rendu d'exécution** | Prévu | `docs/securite/RESULTATS_TESTS.md` (SEC-5 §9) |
| O6 | **Modèle de rapport de failles** | Hors RT-2 | À proposer avec RT-3 |

## 6. Ordre d'exécution proposé

| Quand | Scénarios | Condition |
|---|---|---|
| Dès que l'app est installable sur un iPhone | RT2-01, RT2-04, RT2-23, RT2-24, RT2-26 (P2) | App installée depuis le Mac de Clara (les Macs prêtés ne servent plus, PM-11) |
| Dès que la centrale reçoit des messages (MAC-1) et que `PROTOCOLE.md` existe | RT2-10, RT2-12, RT2-14, RT2-15, RT2-18 | Client attaquant (O1) |
| Quand MAC-2 existe | RT2-07, RT2-09, RT2-10 | Appairage QR |
| Fin de séance du 25/11 | RT2-20, RT2-21, RT2-22 | Mac prêté encore accessible, avant la déconnexion des comptes |
| Si le temps le permet | RT2-02, RT2-03 (A), RT2-05, RT2-11, RT2-13, RT2-16, RT2-17, RT2-19 | Matériel et priorités |

## 7. Décisions et points ouverts

| Point | À décider par |
|---|---|
| Qui écrit le client attaquant (O1) ? SEC-5 §8 cite Aïda et Onur ; la red team décrit les messages à envoyer, sans écrire le code | Aïda, Onur, Clara |
| Valider les outils O2 et O3 | L'équipe |
| Utiliser un hotspot du groupe dédié aux tests (règle 2) | L'équipe |
| Fenêtre F et critère « même appareil » (RT2-05, RT2-06) | Après ARCH-6 |
| Spécification du code court, des essais, de la fenêtre d'appairage (RT2-09 à RT2-11) | Aïda, dans `PROTOCOLE.md` |
| Le titre de l'issue RT-2 cite « D4 » pour les messages malformés ; dans le STRIDE, les messages malformés sont **D3** et D4 désigne le Bluetooth coupé | Clara (corriger le titre) |

## 8. Critères d'acceptation proposés pour l'issue RT-2 (#54)

- [ ] Chaque frontière F1 à F5 a des scénarios d'attaque avec résultat attendu.
- [ ] Chaque scénario renvoie aux tests de SEC-5 quand ils existent, sans les dupliquer.
- [ ] Les règles d'engagement et les outils nécessaires sont validés par Aïda.
- [ ] Les scénarios bloqués (RT2-06) sont identifiés avec ce dont ils dépendent.