# Planning – Projet iOS tracker Bluetooth anti-traçage

> **Mise à jour du 26/11 (PM-11)** : le projet passe à Xcode 16.2 et iOS 15 minimum, et tout se compile sur le MacBook Air de Clara. Les Macs prêtés ne servent plus : « Mac prêté » désigne ici le Mac qui héberge la centrale (désormais celui de Clara), dont les règles « sans état persistant » restent inchangées. Sur iPhone, « Face ID » se lit « biométrie (Face ID ou Touch ID) » et le mode `faceID` devient `biometrie` dans le code (valeur stockée inchangée). Voir `CLAUDE.md` §5 et §6.

> **Statut : proposition préparée avec Claude le 23/11/2026 (version 2), à relire et valider par Clara.**
> Les identifiants (ARCH-1, IOS-2, etc.) renvoient au fichier `BACKLOG.md`.

## 1. Contraintes connues (fournies par Clara)

- Le travail se fait **uniquement pendant les séances**.
- Les Macs sont **prêtés en séance et changent à chaque séance**.
- ~~Les Macs prêtés ont Xcode 27.2~~ **Remplacé le 26/11 (PM-11)** : les Macs prêtés ne peuvent pas connecter de compte iCloud, l'app n'y est pas installable. Le groupe utilise **Xcode 16.2 sur le MacBook Air de Clara**.
- ~~4 iPhones~~ **Mise à jour 26/11 (PM-11)** : seuls l'**iPhone 7 de Clara (iOS 15.8.7)** et l'iPhone 11 Pro Max (iOS 17.4.1, disponible de temps en temps) sont utilisables. Les iPhone 17, 17 Pro Max et 14 (iOS 27) sont exclus : leur iOS est trop récent pour Xcode 16.2 (hypothèse non testée).
- Choix techniques : SwiftUI, MVVM, Swift Testing, code en français.
- Équipe : **trois développeurs** (Rachel, Eva, Onur), Clara cheffe de projet **et red team** (rôle fixe, il ne tourne pas ; confirmé par le professeur), Aida architecte sécurité.
- Clara aura **un AirTag le 24/11**.
- La séance du **15/12 est consacrée à la démo** : aucun temps de développement.

## 2. Calendrier

| Séance | Jalon | Temps de travail |
|---|---|---|
| Jeudi 19/11, 9h-13h | J1 : cadrage | Passé, **non terminé** |
| **Lundi 23/11, 14h-18h** | J1 (clôture) et J2 : architecture | 4 h |
| Mardi 24/11, 9h-13h | J3 : MVP | 4 h |
| Mercredi 25/11, 14h-18h | J4 : audit croisé | 4 h, partagées entre l'audit, les correctifs et la suite du développement |
| Mardi 15/12, 9h-13h | J5 : soutenance | Démo et oral, pas de développement |

Il reste donc environ **12 heures de travail en séance** avant la démo, dont une partie pour clore le J1, concevoir l'architecture et auditer.

## 3. Périmètre proposé : trois niveaux (décision du groupe aujourd'hui)

Les 12 heures ne permettent pas de tout construire. Voici une proposition de découpage.

| Niveau | Contenu | Échéance |
|---|---|---|
| **Niveau 1 : MVP iPhone (indispensable)** | Balayage Bluetooth d'environ 30 s à la demande, liste des appareils, liste de confiance chiffrée avec biométrie, niveaux info et alerte (IOS-1 à IOS-3, IOS-5, TRU-1 à TRU-3, TRU-5, QA-1, QA-2, RT-1 à RT-3) | Fin du 24/11 |
| **Niveau 2 : chaîne sécurisée (objectif)** | App Mac (centrale), appairage par QR code, canal chiffré, événements signés, protections des données de l'iPhone, purge de la centrale en fin de séance (MAC-1 à MAC-4, MAC-7, TRU-4, QA-3, SEC-6, RT-4) | Fin du 25/11 |
| **Niveau 3 : si le temps le permet** | Niveau « critique » par détection d'un traceur type Find My, comparaison entre balayages, position au moment du balayage, hachage des identifiants et purge automatique, notifications locales (IOS-4, IOS-6 à IOS-9, TRU-6, MAC-5, MAC-6) | Seulement s'il reste du temps ; sinon présenté dans le dossier comme évolution prévue |

**Arbitrage à faire par le groupe.** Le suivi entre balayages et la détection d'AirTag sont le cœur de l'idée de départ. La chaîne sécurisée (canal chiffré, Secure Enclave, appairage) est le cœur de ce qu'on attend en cryptographie. Les deux ne tiennent pas en entier. Ma proposition : tenir les niveaux 1 et 2, et décider demain matin, après le test avec l'AirTag (ARCH-6), si une détection simple du niveau « critique » rentre dans le niveau 2.

**Composition de l'équipe.** Clara est cheffe de projet et red team. Elle ne code pas, pour rester indépendante de ce qu'elle attaque. Rachel (balayage et niveaux), Eva (liste de confiance et protections des données) et Onur (app Mac, appairage, canal chiffré, événements signés) développent. Aida relit le code crypto sans l'écrire, pour que l'auteur et le relecteur restent différents.

**Repli si la chaîne sécurisée prend du retard.** Onur porte seul cette chaîne : c'est le premier point à surveiller le 24/11. Réduire alors le niveau 2 à l'appairage par QR code et à un message chiffré et signé envoyé à une app Mac minimale, et présenter le reste dans le dossier sécurité comme évolution prévue.

## 4. Plan séance par séance

### Lundi 23/11, 14h-18h : clôture du J1 et J2

| Horaire | Activité | Tâches |
|---|---|---|
| 14h00-14h20 | Clôturer le J1 : Aida finalise STRIDE, Clara valide backlog et répartition | SEC-1, PM-5 |
| 14h20-14h50 | Décisions du groupe, création du dépôt, premier commit du CLAUDE.md. Fixer la version minimale d'iOS (après test de l'installation sur l'iPhone 11 Pro Max) | ARCH-5, PM-1, PM-2, PM-3 |
| 14h50-16h50 | Architecture : schéma, transport, modèle de données, niveaux d'alerte, choix crypto, et fonctionnement de la centrale sur un Mac prêté | ARCH-1 à ARCH-4, ARCH-7, SEC-3, RT-1 |
| 16h50-18h00 | Lancer le code : projet Xcode iPhone, squelette de l'app Mac, journaux des prompts. Pousser sur Git | IOS-1, MAC-1 (début), PM-4, PM-9 |

### Mardi 24/11, 9h-13h : J3, MVP

| Horaire | Activité | Tâches |
|---|---|---|
| 9h00-9h45 | Test avec l'AirTag sur un iPhone : ce que le Bluetooth expose réellement | ARCH-6 |
| 9h00-12h30 | En parallèle : Rachel (balayage et niveaux), Eva (liste de confiance, biométrie), Onur (app Mac et appairage), Aida (plan de tests, relecture), Clara (scénarios et outils d'attaque) | IOS-2, IOS-3, IOS-5, TRU-1 à TRU-3, MAC-1, MAC-2, SEC-5, RT-2 |
| 12h30-13h00 | Intégration, vérification que le MVP tourne, attaque du MVP par Clara, push, journaux, déconnexion des Macs | PM-9, RT-3 |

### Mercredi 25/11, 14h-18h : J4, audit croisé

| Horaire | Activité | Tâches |
|---|---|---|
| 14h00-14h20 | Réinstaller l'app sur les iPhones depuis un Mac prêté | PM-8 |
| 14h20-15h50 | Audit de l'app de l'autre groupe, mené par Clara avec Aida (grille préparée avant la séance) | SEC-7, SEC-8 |
| 14h20-17h00 | En parallèle, suite du développement : canal chiffré puis événements signés (Onur), protections des données (Eva), niveau critique si le spike le permet (Rachel), tests crypto (Aida), attaque de la chaîne sécurisée (Clara) | MAC-3, MAC-4, TRU-4, QA-3, RT-4 |
| 17h00-17h45 | Correctifs des failles remontées sur notre app | SEC-9 |
| 17h45-18h00 | Vidéo de secours de la démo, tag Git, push, purge de la centrale, journaux | PM-10, MAC-7, PM-9 |

### Mardi 15/12, 9h-13h : J5, démo

- **Arriver en avance** : l'app installée le 25/11 aura expiré (7 jours). La réinstaller depuis un Mac prêté avant la démo (PM-8).
- Démo en direct, avec la vidéo de secours (PM-10) en cas d'échec de l'installation.
- Oral individuel : chacun explique l'ensemble du code.

## 5. Travail possible hors séance (sans Mac)

À faire seulement si le groupe est d'accord, puisque le travail se fait en principe en séance. Ces tâches n'ont pas besoin de Xcode :

- Dossier sécurité : STRIDE et choix crypto (SEC-2)
- Grille d'audit MASVS (SEC-7, Clara), plan de tests de sécurité (SEC-5, Aida et Clara)
- Revue RGPD (SEC-10)
- Regroupement du journal des prompts (PM-6)
- Préparation de l'oral : relire le code de l'équipe (PM-7)

## 6. Risques et contraintes

| Risque | Conséquence | Mesure proposée |
|---|---|---|
| Un Mac différent à chaque séance | Rien ne persiste sur la machine : historique, clés d'appairage, comptes | Git comme seule mémoire du projet ; centrale sans état persistant (ARCH-7) ; tout est poussé sur Git (PM-9 ; les Macs prêtés ne servent plus) |
| MacBook de Clara non utilisé | Aucun Mac constant : tout le développement a lieu en séance | Le travail hors séance se limite aux tâches sans Mac (section 5) |
| Installation sur iPhone 7 (iOS 15.8.7) avec Xcode 16.2 non vérifiée ; un seul développeur peut compiler | Version minimale d'iOS 15 décidée le 26/11 ; l'iPhone 11 Pro Max sert de second appareil | Tester dès la première compilation (fiche `TESTS_PAR_PR.md`). **Hypothèse non testée** |
| Seulement 12 heures de développement | Périmètre trop large | Trois niveaux de priorité ; arbitrage aujourd'hui |
| Clara cumule cheffe de projet et red team | Surcharge, surtout le 25/11 (audit de l'autre groupe, attaque de notre chaîne, vidéo de secours, coordination) | Grille d'audit préparée hors séance (SEC-7) ; Aida épaule l'audit ; RT-4 (P2) sacrifiable ; PM-10 confiée à un développeur |
| Onur porte seul la chaîne sécurisée (MAC-1 à MAC-7) | Retard sur le canal chiffré et les événements signés | MAC-5 et MAC-6 en P3 ; repli du niveau 2 (section 3) ; Aida peut l'aider à concevoir, sans écrire le code |
| Séance du 25/11 trop chargée | L'audit consomme le temps de développement | Grille d'audit préparée avant la séance ; développement en parallèle |
| App expirée le 15/12 | Démo impossible sans réinstallation | PM-8 en arrivant ; vidéo de secours (PM-10) |
| Simulateur sans Bluetooth (hypothèse H3) | Aucun test BLE sans iPhone | 4 iPhones disponibles : limiter le risque |
| AirTag seulement le 24/11 | Pas de test réel avant | Le spike ARCH-6 est la première activité de la séance du 24/11 |
| Code crypto écrit vite | Erreurs de sécurité | Relecture d'Aida obligatoire, tests crypto (QA-3) |