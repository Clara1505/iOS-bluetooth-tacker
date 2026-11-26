# Fiche de tests manuels par PR et par fonctionnalité

> **Statut : proposition préparée avec Claude le 26/11/2026 (PM-11), à valider par Clara.**
> Rédigée **sans pouvoir compiler** : aucun résultat attendu ci-dessous n'a encore été vérifié.
> Tout « attendu » est une **hypothèse** jusqu'à la première exécution. Le résultat réel est noté dans la colonne « Résultat ».

## 1. À quoi sert cette fiche

Seule Clara compile et teste (MacBook Air 2018, Xcode 16.2, voir `CLAUDE.md` §5). Les autres écrivent le code sans le compiler.
Pour chaque PR, Clara déroule les tests de la section 3 puis ceux de la fonctionnalité concernée (section 4 ou 5).
Un test en échec est renvoyé au **responsable indiqué** avec : l'ID du test, le fichier concerné et ce qui a été observé
(message d'erreur Xcode copié tel quel, ou capture).

Règles pour ne pas fausser les résultats :
- Les résultats de balayages réels (noms d'appareils, identifiants) ne sont **ni commités, ni collés dans un prompt** (`CLAUDE.md` §5). Noter seulement « N appareils vus », jamais les identifiants.
- Un test réussi ne prouve pas que la fonction est sûre. Un test raté est un résultat utile : il est noté, pas corrigé en silence.

## 2. Appareils et préparation

| Appareil | Rôle | Remarque |
|---|---|---|
| iPhone 7 (iOS 15.8.7) | Appareil principal de test, Touch ID | Cible minimale. **Hypothèse non testée** : l'installation depuis Xcode 16.2 fonctionne. |
| iPhone 11 Pro Max (iOS 17.4.1) | Second appareil, Face ID | Disponible de temps en temps seulement. Les tests marqués « 11PM » le demandent. |
| MacBook Air 2018 (macOS 14.8.9, Xcode 16.2) | Compilation, tests unitaires, centrale Mac | |
| Traceur réel (AirTag ou équivalent) | Tests de suivi | Optionnel, à prêter si possible. Les tests marqués « traceur » sont à sauter sinon. |

Avant chaque série : Xcode > Product > Clean Build Folder, puis compiler. L'app expire après 7 jours : la réinstaller avant chaque démo (PM-8).

## 3. Tests communs à toutes les PR

| ID | Étapes | Attendu (hypothèse) | Si KO : fichier et responsable |
|---|---|---|---|
| COM-1 | Ouvrir `IOSBluetoothTracker.xcodeproj` dans Xcode 16.2, choisir le schéma `IOSBluetoothTracker`, Product > Build | Compilation sans erreur | Fichier cité par Xcode ; auteur de la PR |
| COM-2 | Regarder les avertissements (triangle jaune) | Aucun avertissement nouveau par rapport à `dev`. Un avertissement « deprecated » sur `disableAutocorrection` est connu et toléré | Auteur de la PR |
| COM-3 | Product > Test (Cmd+U) sur un simulateur iOS 15 ou 17 | **96 tests** Swift Testing passent (80 avant PM-11 + 16 ajoutés). Le total de la PR peut être plus grand. Aucun test supprimé sans explication | Test en échec : auteur du test ; si c'est du code de sécurité : Aida |
| COM-4 | Si COM-3 ne lance aucun test Swift Testing (0 test exécuté, ou erreur « module Testing introuvable ») | **Hypothèse à confirmer** : Swift Testing n'est pas utilisable avec une cible iOS 15. Noter le message exact, puis décision de repli sur XCTest (issue #50 QA-1) | Clara et Aida |
| COM-5 | Brancher l'iPhone 7, le choisir comme destination, Product > Run | L'app s'installe et s'ouvre sans plantage. Si « Untrusted Developer » : Réglages > Général > Gestion des appareils | Clara (signature) |
| COM-6 | Idem sur l'iPhone 11 Pro Max (11PM) | Idem | Clara |
| COM-7 | Rechercher dans le diff de la PR les API interdites (liste `CLAUDE.md` §7 : `@Observable`, `NavigationStack`, `Task.sleep(for:`, `.autocorrectionDisabled`...) | Aucune occurrence | Auteur de la PR |
| COM-8 | Rechercher `print(`, `!` sur donnée externe, `try!`, `fatalError`, secret en dur | Aucun cas sur donnée sensible ou externe | Auteur ; Aida si crypto |
| COM-9 | Mettre l'app en arrière-plan puis ouvrir le sélecteur d'applications | L'aperçu est masqué (pas de contenu lisible) | Fichier `ProtectionDonnees.swift` ; auteur de TRU-4 |

## 4. Tests par fonctionnalité iPhone

**Point important constaté sur `dev` (à confirmer à l'exécution) :** `IOSBluetoothTrackerApp` n'affiche que l'écran « Contrôle de sécurité ».
Les écrans d'enrôlement (TRU-1) et de liste de confiance (TRU-5) ne sont **pas atteignables** depuis l'app tant que le hacheur HMAC (TRU-6) n'est pas branché :
leur comportement ne se vérifie donc que par les tests unitaires et les aperçus Xcode (`#Preview`). Tout appareil est alors traité comme inconnu.

### IOS-2 – Balayage Bluetooth de 30 s (responsable : Rachel)

| ID | Étapes | Attendu (hypothèse) | Si KO : fichier et responsable |
|---|---|---|---|
| IOS2-1 | Premier lancement sur iPhone 7, appuyer sur « Contrôle de sécurité » | La demande de permission Bluetooth apparaît avec le texte du projet. Après « Autoriser », le balayage démarre (« Balayage en cours… ») | `ServiceBalayageBluetooth.swift`, `project.pbxproj` (clé `NSBluetoothAlwaysUsageDescription`) ; Rachel |
| IOS2-2 | Laisser finir le balayage | Il dure environ 30 s, le bouton est grisé pendant ce temps, puis un résultat s'affiche | `ServiceBalayageBluetooth.swift` (`Attente.dormir`), `BalayageVueModele.swift` ; Rachel |
| IOS2-3 | **Test de la migration** : pendant un balayage, vérifier que l'app ne plante pas à l'arrivée des premières annonces | Aucun plantage. **Hypothèse non testée** : `MainActor.assumeIsolated` fonctionne sur iOS 15. S'il plante : noter le message Xcode (probablement dans `ServiceBalayageBluetooth.swift`), repli prévu avec `Task { @MainActor in }` | Rachel et Clara |
| IOS2-4 | Refuser la permission (Réglages > Confidentialité > Bluetooth) puis relancer un contrôle | Message « l'accès au Bluetooth est refusé », **jamais** « Aucun appareil détecté » (D4) | `BalayageVue.swift` ; Rachel |
| IOS2-5 | Éteindre le Bluetooth (Centre de contrôle) puis lancer un contrôle | Message « le Bluetooth est éteint », jamais une liste vide (D4) | Idem |
| IOS2-6 | Éteindre le Bluetooth **pendant** un balayage | Message « le balayage a été interrompu » à la fin, jamais une liste vide (D4) | `ServiceBalayageBluetooth.swift` ; Rachel |
| IOS2-7 | Appuyer sur le bouton plusieurs fois très vite | Un seul balayage à la fois (le bouton est désactivé), pas de plantage | `BalayageVueModele.swift` ; Rachel |

### IOS-3 – Liste des appareils (responsable : Rachel)

| ID | Étapes | Attendu (hypothèse) | Si KO : fichier et responsable |
|---|---|---|---|
| IOS3-1 | Lancer un contrôle dans un endroit avec des appareils Bluetooth (téléphones, casques...) | La liste « N appareil(s) détecté(s) » s'affiche. L'écran **ne montre pas** d'identifiant, seulement le nom (ou « Appareil sans nom ») et le signal en dBm | `BalayageVue.swift` ; Rachel |
| IOS3-2 | Défiler la liste | Les appareils sont triés : niveau le plus grave d'abord, puis signal le plus fort | `ReglesAlerte.swift` ; Rachel |
| IOS3-3 | Faire un contrôle dans un lieu sans aucun appareil Bluetooth (rare) | « Aucun appareil détecté » seulement si le balayage a abouti | `BalayageVue.swift` ; Rachel |
| IOS3-4 | Vérifier l'affichage sur iPhone 7 (petit écran) | Rien de coupé, liste lisible, bouton visible | `BalayageVue.swift` ; Rachel |

### IOS-5 – Niveaux info / alerte (responsable : Rachel)

| ID | Étapes | Attendu (hypothèse) | Si KO : fichier et responsable |
|---|---|---|---|
| IOS5-1 | Contrôle avec au moins un appareil détecté (liste de confiance non branchée) | Bandeau « Appareils inconnus à proximité… » (info) ou « Alerte : un appareil inconnu est resté près de vous… » selon la durée de présence. **Aucun appareil n'est marqué « Confiance »** (échec en sécurité) | `ReglesAlerte.swift`, `BandeauNiveauVue` ; Rachel |
| IOS5-2 | Rester à proximité d'un même appareil (ex. un second téléphone posé près de l'iPhone 7) pendant tout le balayage | L'appareil passe en « Alerte ». **Hypothèse** : les identifiants vus par iOS peuvent changer, donc ce test peut échouer sans que le code soit en cause | Clara (à noter pour RR2) ; Rachel |
| IOS5-3 | Lancer deux contrôles de suite, sans bouger | Aucun plantage ; le résultat du second remplace celui du premier | `BalayageVueModele.swift` ; Rachel |
| IOS5-4 | Traceur : activer un AirTag à proximité, faire un contrôle | À noter **tel qu'observé** (visible ou non, nom affiché ou non). Ne présenter aucun résultat comme acquis avant le test (règle de vérification) | Clara ; Rachel et Aida |

### TRU-1 à TRU-5 – Liste de confiance (responsable : Eva, crypto : Aida)

Ces fonctions sont couvertes par les tests unitaires (COM-3). Tests manuels possibles **seulement si l'écran est branché** :

| ID | Étapes | Attendu (hypothèse) | Si KO : fichier et responsable |
|---|---|---|---|
| TRU-A | Dans Xcode, ouvrir l'aperçu (`#Preview`) des vues d'enrôlement et de liste | Les écrans s'affichent avec des données fictives ; texte « biométrie (Face ID ou Touch ID) » dans les réglages | `EnrolementVue.swift`, `ListeConfianceVue.swift`, `ReglesVue.swift` ; Eva |
| TRU-B | Vérifier les tests `ListeDeConfianceTests`, `ModificateurListeTest`, `EnrolementTests`, `ListeConfianceVueModeleTests` dans COM-3 | Tous passent, y compris avec le mode `.biometrie` | Eva ; Aida (sécurité) |
| TRU-C | Test `MigrationIOS15Tests` « format sérialisé » | Le mode biométrie reste écrit `"faceID"` | `Modele.swift` ; Aida (format signé) |
| TRU-D (11PM, iPhone 7) | **Dès que l'écran sera branché (TRU-6)** : ajouter puis retirer un appareil, en annulant l'authentification une fois | Annulation : liste inchangée et message d'erreur. **Hypothèse non testée** : Touch ID sur iPhone 7 déclenche bien `userPresence`. Voir RT2-23 | Eva ; Aida |

## 5. Tests de la centrale Mac (responsable : Onur, crypto : Aida)

**État constaté sur la pile de PR d'Onur (à confirmer) :** 32 tests sur 36 passent avec Xcode 16.2 ; 4 sont en échec de façon intermittente. Les causes suspectées (non prouvées) :
(A) exécution hors du thread principal, (B) précision des dates dans l'historique, (C) arrondi différent des horodatages dans les données signées.
Ces points seront traités **après** la migration, dans les PR d'Onur ; le code crypto est relu par Aida.

| ID | Étapes | Attendu (hypothèse) | Si KO : fichier et responsable |
|---|---|---|---|
| MAC-T1 | Dans un terminal : `cd CentraleMac` puis `swift build` | « Build complete » | `Package.swift` ; Onur |
| MAC-T2 | `swift test` (répéter 5 fois) | 36 tests. **Les 4 échecs connus ne sont pas à corriger dans la PR de migration.** Noter lesquels échouent, à chaque fois | `CentraleMacViewModel.swift`, `ServiceHistoriqueChiffreCrypto.swift`, `ServiceEvenementsSignesCrypto.swift` ; Onur puis Aida |
| MAC-T3 | `swift run CentraleMacApp` | La fenêtre de la centrale s'ouvre | `App/CentraleMacApp.swift` ; Onur |
| MAC-T4 (MAC-2) | Afficher le QR code d'appairage | Le QR s'affiche avec une empreinte courte lisible | `GenerateurQRCode.swift`, `CentraleMacView.swift` ; Onur |
| MAC-T5 (MAC-7) | Fermer la centrale et chercher des fichiers d'historique ou de clés sur le disque | Aucune donnée d'historique ni clé laissée sur le disque (règle ARCH-7 conservée sur le Mac de Clara) | Onur ; Aida |
| MAC-T6 | Vérifier que `Package.swift` déclare `.iOS(.v17)` | **Décision en attente** : ce réglage ne concerne que la bibliothèque, pas l'app iPhone. Ne pas le modifier sans décision de l'équipe | Onur et Aida |

## 6. Tests de la migration PM-11 (cette PR)

| ID | Étapes | Attendu (hypothèse) | Si KO |
|---|---|---|---|
| MIG-1 | COM-1 à COM-3 | Voir section 3 | Clara me renvoie les messages d'erreur |
| MIG-2 | Les tests `AttenteTests` et `MigrationIOS15Tests` (16 tests) | Tous passent | Idem |
| MIG-3 | IOS2-1 à IOS2-7 sur iPhone 7 | Comportement identique à celui de `dev` avant migration | Idem |
| MIG-4 | Écrans « Liste » et « Réglages » en aperçu (TRU-A) | Navigation en pile, titre visible, pas de double colonne | `ListeConfianceVue.swift`, `ReglesVue.swift` |

## 7. Suivi des bugs trouvés

Remplir au fil des tests (aucun identifiant d'appareil réel).

| N° | Test | Observé | Fichier | Responsable | État |
|---|---|---|---|---|---|
| | | | | | |
