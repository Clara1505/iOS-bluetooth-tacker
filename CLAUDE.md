# Projet iOS – Tracker Bluetooth anti-traçage (M2)

## 1. Contexte

Projet de groupe de Master 2 : concevoir, développer puis défendre une app iOS
qui transforme un iPhone en équipement de sécurité.

### Notre sujet
Application de détection de traceurs Bluetooth (type AirTag) pour un particulier.
- Un bouton « Contrôle de sécurité » lance un balayage BLE d'environ 30 s
  et liste les appareils environnants.
- Tout appareil inconnu déclenche un warning à 3 niveaux : info, alerte, critique.
- Le suivi se fait en comparant les balayages entre eux (aucun GPS continu).
- Architecture : iPhone = capteur, Mac = centrale (historique, alertes).
  Le Mac étant prêté, les fichiers de la centrale sont temporaires (appairage et données de démo refaits à chaque séance, supprimés en fin de séance).

### Principe directeur
L'IA propose, l'équipe décide.

## 2. Équipe et rôles

| Rôle | Membre | Responsabilités |
|---|---|---|
| Chef de projet | Clara SION SAUNIER | Planning, backlog, jalons, journal des prompts |
| Architecte sécurité | Aida GOUMBLE | Modèle de menaces STRIDE, choix crypto, relecture de tout code touchant à la crypto, tous les tests de sécurité |
| Développeur iOS | Rachel DIGNA | Code Swift, intégration iPhone ↔ Mac, tests |
| Développeur iOS | Eva DOUMBE NGANGUE | Code Swift, intégration iPhone ↔ Mac, tests |
| Développeur iOS | Onur GENC | Code Swift, intégration iPhone ↔ Mac, tests |
| Red team | Clara SION SAUNIER (en plus de son rôle de cheffe de projet) | Attaque l'app, rédige les rapports de failles, mène l'audit croisé avec Aida |

Règles communes :
- Chaque membre doit pouvoir expliquer l'ensemble du code à l'oral, quel que soit son rôle.
- Le rôle de red team est tenu par Clara pour tout le projet, en plus de son rôle de cheffe de projet : il ne tourne pas d'un jalon à l'autre (confirmé par le professeur).
- Tout code touchant à la crypto doit être relu par Aida avant fusion.

## 3. Règles d'usage de l'IA

### Autorisé
- Générer du code, des tests, de la documentation
- Refactoriser et expliquer du code
- Explorer une API inconnue
- Préparer un modèle de menaces

### Obligatoire
- Tenir le journal des prompts (voir section 4)
- Relire et comprendre chaque ligne générée
- Faire valider chaque fusion par un humain
- Tester tout code de sécurité

### Interdit
- Coller des secrets ou des données réelles dans un prompt
- Fusionner du code crypto non relu
- Ajouter une dépendance non vérifiée
- Rendre un travail que l'on ne sait pas expliquer

### Pièges du code généré à repérer
- Secrets en dur (clés d'API, mots de passe dans le code source)
- Crypto obsolète (MD5, mode ECB, IV fixe, aléa non cryptographique)
- Dépendances fantômes (paquets inventés par l'IA)
- Entrées non validées (données réseau sans contrôle de format ni de taille)
- Logs bavards (jetons, identifiants ou positions dans la console)
- Fausse confiance : « ça compile » ne veut pas dire « c'est sûr »

## 4. Journal des prompts

Le journal est obligatoire. Il recense les prompts envoyés à l'IA par chaque membre.

### Où
- Pendant le projet : `docs/journal/<prenom>.md`, un fichier par membre (évite les conflits Git).
- Avant le rendu : regroupement dans un fichier unique `JOURNAL_PROMPTS.md`, qui précise en
  introduction que des fichiers individuels existent dans `docs/journal/`.

### Quand
Après chaque session de travail avec l'IA, avant le commit correspondant.

### Format d'une entrée
- **Date et heure** : AAAA-MM-JJ HH:MM
- **Auteur** : prénom
- **Prompt** : texte envoyé, sans secret ni donnée réelle

### Rôle de Claude
- En début de session, demander le prénom du membre s'il n'est pas connu.
- En fin de session, proposer les entrées du journal (date, heure, auteur, prompts envoyés)
  prêtes à coller dans le fichier du membre.
- Ne jamais recopier de secret ni de donnée réelle dans une entrée.

## 5. Contraintes techniques iOS

### Compte Apple gratuit
- L'app installée expire après 7 jours : la réinstaller depuis Xcode avant chaque démo.
- Disponible : Bluetooth Low Energy, localisation (y compris en arrière-plan), Keychain,
  Secure Enclave, Face ID, réseau local iPhone ↔ Mac, notifications locales.
- Indisponible : notifications push (APNs), iCloud / CloudKit, Core NFC.
  Les alertes passent donc par le réseau local et les notifications locales.

### Bluetooth sur iOS
- iOS masque l'adresse matérielle des appareils : les identifiants vus par l'app
  peuvent changer d'un balayage à l'autre. Le suivi doit être testé avec un vrai traceur.
- Le scan en arrière-plan est limité : balayage à la demande uniquement
  (bouton « Contrôle de sécurité », environ 30 s).
- Les résultats de balayages réels (identifiants, positions d'appareils de passants ou de
  proches) sont des données réelles : ni commités, ni collés dans un prompt. Les tests
  utilisent des données fictives.

### Localisation
- Pas de GPS en continu : la position n'est relevée qu'au moment d'un balayage.

### Permissions
- Ne demander que les permissions iOS vraiment utiles, au moment où on en a besoin.

### Environnement de travail
- Le travail se fait uniquement pendant les séances. Les Macs sont prêtés en séance et
  **changent à chaque séance** : Xcode 27.2 sur tous les Macs prêtés.
- Le groupe développe avec la version la plus récente de Xcode (27.2, celle des Macs prêtés).
  Le MacBook de Clara (Xcode 16.2) n'est pas utilisé pour le développement.
- iPhones du groupe : iPhone 17 (iOS 27.2.1), iPhone 17 Pro Max (iOS 27.2.1),
  iPhone 14 (iOS 27.0.1), iPhone 11 Pro Max (iOS 17.4.1).
- Le dépôt Git est la seule mémoire du projet : tout est poussé avant la fin
  de chaque séance, et chacun se déconnecte de son compte Apple et de GitHub avant de rendre le Mac.

### Environnement
- Xcode 27.2 et version de Swift livrée avec.
- Version minimale d'iOS : 17 (décidé le 23/11), pour inclure l'iPhone 11 Pro Max de Rachel (iOS 17.4.1).
  L'installation depuis Xcode 27.2 sur cet iPhone est à confirmer dès le premier essai.
  Le code n'utilise que des API disponibles depuis la version minimale retenue.
- Frameworks Apple uniquement (CoreBluetooth, CryptoKit, LocalAuthentication, CoreLocation,
  Security). Aucune dépendance tierce sans vérification et validation de l'équipe.

### Règle de vérification
Ni Claude ni aucune autre IA utilisée ne doit supposer qu'un comportement est fonctionnel
ou lisible tant qu'il n'a pas été testé (annonces Find My, identifiants Bluetooth,
rotation des adresses, etc.). Toute affirmation non testée est présentée comme une
hypothèse, jamais comme un fait.

## 6. Sécurité et cryptographie

### Principes
- Ne jamais inventer sa propre cryptographie : CryptoKit uniquement.
- Le réseau local n'est pas de confiance : chaque message est authentifié.
- Échouer en sécurité : en cas d'erreur ou de doute, l'app verrouille au lieu d'ouvrir.
- Toute fonctionnalité de sécurité part d'une exigence et de la menace STRIDE visée.
- Tout code touchant à la crypto est relu par Aida avant fusion.
  Aida est responsable de tous les tests de sécurité.

### Boîte à outils (choix finaux justifiés par Aida au jalon 2)
- AES-GCM : chiffrement authentifié
- SHA-256, HMAC : intégrité
- P-256 ECDSA : signatures, avec clé Secure Enclave non exportable
- P-256 ECDH + HKDF : échange et dérivation de clés

### Canal iPhone ↔ Mac
- Appairage par QR code, avec vérification d'une empreinte de clé.
- Clés éphémères à chaque session (confidentialité persistante).
- Événements signés et horodatés, avec nonce et compteur (anti-rejeu).

### Données
- Liste de confiance chiffrée, modification protégée par Face ID.
- Keychain en « ThisDeviceOnly », accès conditionné à Face ID.
- Fichiers en protection « Complete ».
- Presse-papiers local à l'appareil, avec expiration automatique.
- Aperçu multitâche masqué quand l'app passe en arrière-plan.
- Aucun secret ni donnée personnelle dans les logs.

### RGPD
- Identifiants hachés, purge automatique, données minimisées.
- Algorithme de hachage des identifiants : **à définir par Aida**
- Durée de purge : **à définir par Aida**

## 7. Conventions de code Swift et tests

### Code
- Langage : Swift. Respecter les Swift API Design Guidelines pour le nommage.
- Framework d'interface : SwiftUI.
- Architecture du code : MVVM (vues, vue-modèles, services). Chaque service (Bluetooth,
  liste de confiance, crypto, canal sécurisé) est derrière un `protocol`, pour pouvoir être
  remplacé par un faux dans les tests. Le code crypto est isolé dans un module à part,
  relu par Aida.
- Langue du code (noms, commentaires, messages) : français. Les noms des API Apple restent
  en anglais. Identifiants sans accents.
- `!` (force unwrap), `try!` et `fatalError` sont interdits sur toute donnée externe
  (Bluetooth, réseau, QR code, fichiers). Ils ne sont tolérés que pour une condition interne
  qui ne peut pas se produire, avec un commentaire qui justifie pourquoi.
  La relecture vérifie systématiquement qu'ils ne peuvent pas faire planter l'app.
- Pas de secret en dur, pas de `print` de données sensibles (identifiants, positions, clés).
- Toute donnée venant de l'extérieur (réseau, Bluetooth, QR code) est validée
  (format et taille) avant utilisation.
- Code simple et lisible : chaque membre doit pouvoir l'expliquer à l'oral.
- Code commenté de façon explicite, pour rester maintenable et compréhensible :
  chaque fonction a un commentaire de documentation (`///`) qui dit ce qu'elle fait,
  ses paramètres et ses cas d'erreur, et les blocs non évidents expliquent le pourquoi.
  Le code de sécurité (crypto, signatures, anti-rejeu) est commenté étape par étape.

### Tests
- Framework de test : Swift Testing.
- Tout code de sécurité est testé (tests écrits ou validés par Aida).
- Tests unitaires et cas limites obligatoires pour : la liste de confiance, les niveaux
  d'alerte (info / alerte / critique), la comparaison entre balayages, la signature et
  la vérification des messages, l'anti-rejeu.
- Un test qui passe ne prouve pas que la fonction est sûre : tenter aussi de la casser
  (entrées malformées, messages rejoués, valeurs extrêmes).
- Le comportement Bluetooth réel (identifiants, annonces) se vérifie avec un vrai appareil,
  pas seulement en simulation (voir la règle de vérification, section 5).

## 8. Workflow Git et revues

- Un dépôt Git unique. Aucun push direct sur `main`.
- Une branche par fonctionnalité ou correctif, intégrée par pull request.
- Un relecteur minimum valide chaque fusion, et le relecteur est différent de l'auteur du code.
  Une IA ne valide jamais une fusion et ne fusionne jamais.
- Tout code touchant à la crypto est relu par Aida avant fusion.
- L'historique de revues fait partie du livrable : les commentaires de revue sont conservés
  et les descriptions de pull request indiquent l'objectif, la menace STRIDE visée et
  les tests effectués.
- Le journal des prompts est mis à jour avant le commit (voir section 4).
- Jamais de secret, clé, certificat ou profil de signature dans le dépôt.
  Le `.gitignore` est adapté à Swift et Xcode.

### Conventions GitHub

Langue des messages, titres et descriptions : français.

**Jalons** : `J1 – Cadrage`, `J2 – Architecture`, `J3 – MVP`, `J4 – Audit croisé`, `J5 – Soutenance`.

**Étiquettes** : `epic:pm`, `epic:sec`, `epic:arch`, `epic:ios`, `epic:tru`, `epic:mac`, `epic:qa`, `epic:rt`,
`prio:P1`, `prio:P2`, `prio:P3`, `crypto` (relecture d'Aida obligatoire).

**Branches** : `<type>/<ID>-<description-courte>`, où `ID` est l'identifiant du backlog
(exemple : `feat/IOS-2-balayage-ble`). Types : `feat`, `fix`, `test`, `docs`, `refactor`,
`chore`, `sec`. Une branche par issue, créée à partir d'un `main` à jour.

**Commits** : `type(ID): résumé à l'impératif`, 72 caractères au maximum
(exemple : `feat(IOS-2): ajoute le balayage Bluetooth de 30 s`).
- Le corps, facultatif, explique le pourquoi et cite la menace STRIDE visée (exemple : `Menace : D4`).
- Petits commits cohérents, un sujet par commit.
- Jamais de secret, clé, certificat, profil de signature, ni de fichier généré par Xcode
  (`xcuserdata`, `DerivedData`).
- Avant de committer : le code compile, les tests passent, le journal des prompts du membre est à jour.

**Issues** : titre du backlog précédé de son identifiant ; corps selon le modèle
(Objectif, Menace STRIDE visée, Critères d'acceptation, Tests prévus) ; jalon, étiquettes
`epic:*` et `prio:*`, responsable renseignés.

**Pull requests** :
- Titre au format des commits. Petite PR, liée à une issue (`Closes #n`).
- Description : objectif, menace STRIDE visée, tests effectués.
- Checklist à cocher :
  - [ ] Relue par un membre différent de l'auteur
  - [ ] Relue par Aida (si crypto, étiquette `crypto`)
  - [ ] Journal des prompts à jour
  - [ ] Aucun secret ni donnée personnelle
  - [ ] Aucun `!`, `try!` ni `fatalError` sur une donnée externe
- Les commentaires de revue sont conservés et les conversations résolues avant la fusion.
- La fusion est faite par un humain, en fusion simple (merge commit) pour conserver
  l'historique des commits.

## 9. Rôle de Claude

- Claude propose, l'équipe décide. Il présente les options et leurs compromis, et ne prend
  pas à la place de l'équipe une décision d'architecture, de cryptographie ou de périmètre.
- Règle de vérification (section 5) : ne rien présenter comme fonctionnel tant que ce
  n'est pas testé. Une affirmation non testée est annoncée comme une hypothèse.
- Dire explicitement quand il ne sait pas, et signaler les failles ou limites de ses
  propres propositions, même si cela contredit la demande.
- Après avoir généré du code non trivial, l'expliquer assez clairement pour que chaque
  membre puisse le défendre à l'oral. Le code généré par Claude respecte les règles de
  commentaires de la section 7.
- Crypto : CryptoKit uniquement, aucune cryptographie inventée. Signaler tout code touchant
  à la crypto pour qu'Aida le relise.
- Signaler toute nouvelle dépendance avant de l'ajouter.
- Vérifier dans le code généré les pièges listés en section 3 (secrets en dur, crypto
  obsolète, entrées non validées, logs bavards...).
- Rester dans le périmètre de la demande : ne pas modifier d'autres fichiers sans le dire.
- Ne jamais committer, pousser ni fusionner : ces actions restent humaines.
- Workflow GitHub : à la demande d'un membre, le guider selon la section 8 (nom de branche,
  message de commit, description de PR, checklist de relecture), sans exécuter lui-même
  commit, push ni fusion. Il signale ce qui manque : journal non à jour, tests absents,
  secret apparent, menace STRIDE non indiquée, code crypto sans relecture d'Aida.
- Avertir si un prompt contient un secret ou une donnée réelle.
- Journal des prompts : voir section 4.
- Répondre en français.

## 10. Hors périmètre

- Suivi GPS continu : la position n'est relevée qu'au moment d'un balayage.
- Scan Bluetooth en arrière-plan : balayage à la demande uniquement.
- Fonctions réservées aux comptes Apple payants : notifications push, iCloud / CloudKit, Core NFC.
- Cible autre qu'un particulier.

## Points en attente de décision

| Point | Qui décide | Quand |
|---|---|---|
| Algorithme de hachage des identifiants, durée de purge | Aida et le groupe | Après le STRIDE (séance du 23/11) |
| Choix crypto définitifs (boîte à outils) | Aida et le groupe | Après le STRIDE (séance du 23/11) |