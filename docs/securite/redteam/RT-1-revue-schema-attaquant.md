# RT-1 – Revue du schéma d'architecture côté attaquant

> **Mise à jour du 26/11 (PM-11)** : le projet passe à Xcode 16.2 et iOS 15 minimum, et tout se compile sur le MacBook Air de Clara. Les Macs prêtés ne servent plus : « Mac prêté » désigne ici le Mac qui héberge la centrale (désormais celui de Clara), dont les règles « sans état persistant » restent inchangées. Sur iPhone, « Face ID » se lit « biométrie (Face ID ou Touch ID) » et le mode `faceID` devient `biometrie` dans le code (valeur stockée inchangée). Voir `CLAUDE.md` §5 et §6.

> **Statut : proposition préparée avec Claude le 24/11/2026, à relire par Clara (red team), puis par Aïda et Onur.**
> Responsable : Clara (red team). Relecture : Aïda (sécurité), Onur (architecture et transport).
> Menaces visées : toutes celles des frontières F1 à F5 de `docs/securite/STRIDE.md`, avec un accent sur S1, S4, E2, D2, D3, T2, I4.
> Documents relus : `docs/architecture/schema-architecture.md` (ARCH-1, PR #64), `docs/architecture/transport.md` (ARCH-2),
> `docs/securite/CHOIX_CRYPTO.md` (SEC-3), `docs/securite/STRIDE.md` (SEC-1). `niveaux-alerte.md` n'a été consulté que sur D4.
>
> **Portée de cette revue.** C'est une relecture de documents. Aucun code n'existe encore et rien n'a été exécuté.
> Les constats ci-dessous sont des **points à vérifier**, pas des failles prouvées (règle de vérification, CLAUDE.md, section 5).
> Les gravités sont des **propositions** à confirmer par Aïda.

## 1. Scénarios d'attaque par frontière

| Frontière | Acteur | Scénarios d'attaque | Menaces | Exécution | Matériel |
|---|---|---|---|---|---|
| **F1** Bluetooth → iPhone | M1, M3 | Annonces en grand nombre ; annonces malformées (champs vides, tailles extrêmes) ; imitation d'un appareil de confiance ; Bluetooth coupé ou permission refusée | D1, T5, D3, S3, D4 | RT-3 (24/11) | iPhone + app ; un émetteur BLE (à identifier) ; sinon tests unitaires du parseur |
| **F2** QR code → iPhone | M2, M6 | QR d'un autre Mac ; QR vide, trop long, mauvais format ; second client qui se connecte pendant l'appairage ; confirmation du code court avec des codes différents | S1, S4, T4, E2 | RT-4 (25/11) | iPhone + Mac ; les QR de test se génèrent sur n'importe quel ordinateur |
| **F3** Réseau local iPhone ↔ Mac | M2 | Écoute du trafic ; modification d'un octet ; rejeu d'un message valide ; message signé par une autre clé ; en-tête de taille 0 ou 0xFFFFFFFF ; trame tronquée ; flood de connexions et de messages ; client non appairé ; coupure réseau | I1, T1, T2, S2, D3, D2, E2, D5 | RT-2 prépare (24/11), RT-4 exécute (25/11) | Un poste sur le même réseau que le Mac (voir §4) + la centrale qui tourne |
| **F4** Mac prêté | M5 | Données restant sur le disque après la purge ; logs console ; comptes ou secrets laissés ouverts | I4, I2, E3 | Fin de séance du 25/11 | Le Mac prêté lui-même |
| **F5** Utilisateur → iPhone | M4 | Biométrie annulée ou échouée ; modification avec le code (signalement) ; fichier de la liste corrompu ; ancienne liste correctement signée remise en place ; aperçu multitâche ; fichiers lisibles iPhone verrouillé | E1, R2, T3, I3, I6 | RT-3 / RT-4 | iPhone + app installée |

## 2. Constats

### C1 – L'authentification de l'iPhone auprès du Mac repose entièrement sur une comparaison humaine
- **Source** : `schema-architecture.md` §3 (phase 1) et §4 (F2) ; `CHOIX_CRYPTO.md` §3.2.
- **Constat** : d'après le schéma, le QR code contient l'empreinte SHA-256 de la clé du Mac et des informations de connexion, donc aucun secret partagé. Seul le code court confirmé par l'utilisateur lie la clé de l'iPhone à la session. S4 et E2 dépendent donc entièrement de H4 (l'utilisateur compare vraiment).
- **Non spécifié dans les documents** : longueur et dérivation du code court, nombre d'essais, durée de la fenêtre d'appairage, comportement du Mac si un second client se connecte pendant l'appairage. `PROTOCOLE.md` est annoncé mais n'existe pas dans le dépôt.
- **Gravité proposée** : élevée. **À valider par** : Aïda. **Test** (RT-4) : connexion d'un faux client pendant la fenêtre d'appairage ; confirmation tentée avec des codes différents ; deux clients simultanés.

### C2 – Surface avant authentification, et garde-fous qui reposent sur une tâche P3
- **Source** : `transport.md` §5 ; `schema-architecture.md` §4 (F3) ; `BACKLOG.md` (MAC-6).
- **Constat** : l'appairage et l'échange de clés sont acceptés avant toute authentification : c'est la plus grande surface d'attaque réseau. Or le rejet rapide, la limitation du nombre de connexions et la limitation de débit sont rattachés à MAC-6, une tâche **P3** (« si le temps le permet »). Les documents d'architecture les présentent pourtant comme des garde-fous acquis. Seul le plafond de 64 Ko par trame est décrit comme acquis dès MAC-1.
- **Non spécifié** : délai d'attente côté centrale pour une connexion qui envoie l'en-tête puis s'arrête (le délai d'expiration cité dans `transport.md` concerne l'iPhone, pour D5). Plusieurs connexions de 64 Ko peuvent aussi occuper beaucoup de mémoire. **[Hypothèse]** : dépend de l'implémentation, rien n'est encore écrit.
- **Gravité proposée** : moyenne (D2 est de niveau Moyen dans le STRIDE), mais l'écart entre la priorité (P3) et la description est à lever. **À valider par** : Aïda et Onur. **Test** (RT-2 / RT-4) : en-têtes 0, 0xFFFFFFFF, 64 Ko puis silence ; trame tronquée ; nombreuses connexions ; flood de messages.

### C3 – « Aucune persistance sur disque » ne veut pas dire « aucune trace » sur le Mac prêté
- **Source** : `schema-architecture.md` §1, §3 (phase 4), §4 (F4).
- **Constat** : le schéma affirme que clés et historique ne vivent qu'en RAM. **[Hypothèse non vérifiée]** : la mémoire d'un processus peut être écrite sur disque par le système (échange mémoire, mise en veille prolongée), et des traces peuvent rester ailleurs (rapports de plantage, logs console, fichiers de build si l'app est lancée depuis Xcode). Par ailleurs la purge de fin de séance est une action déclenchée par l'utilisateur (phase 4) : si elle est oubliée, il reste l'historique jusqu'à la fermeture de l'app.
- **Gravité proposée** : moyenne (I4 est de niveau Élevé dans le STRIDE ; les données de démo sont fictives). **À valider par** : Aïda. **Test** (fin de séance du 25/11) : placer dans les données de démo une valeur marqueur fictive, puis la chercher sur le disque du Mac après la purge. Nécessite d'avoir encore accès au Mac.

### C4 – Contenu exact de la signature des clés éphémères à préciser
- **Source** : `CHOIX_CRYPTO.md` §3.2.
- **Constat** : le texte dit que chaque côté « signe sa clé publique éphémère avec sa clé d'identité ». Il ne précise pas si la signature couvre aussi l'identité du pair, un défi fourni par le pair ou un identifiant de session. Le libellé `info` et le sel HKDF sont renvoyés à `PROTOCOLE.md`, non écrit. C'est une question de conception, pas une faille constatée ; RR7 (protocole maison) la couvre au niveau du risque.
- **Gravité** : à évaluer par Aïda **avant** MAC-3. **Test** (QA-3, RT-4) : rejeu d'une poignée de main enregistrée ; signature valide mais liée à une autre session.

### C5 – Des garde-fous reposent sur des hypothèses non encore testées
Ce ne sont pas des failles. Ce sont les points qui peuvent faire changer la conception, à tester en premier :

| Hypothèse | Ce qu'elle conditionne | Où |
|---|---|---|
| H1 / H2 : identifiants BLE, annonces Find My (ARCH-6) | S3, hachage des identifiants, comparaison entre balayages, IOS-4 | `STRIDE.md` §6 |
| Hotspot iPhone : Bonjour et TCP entre iPhone et Mac | Tout le canal (MAC-1) | `transport.md` §2 |
| `userPresence` sur clé Secure Enclave, lecture de la clé publique sans authentification | TRU-2, TRU-3, E1 | `CHOIX_CRYPTO.md` §3.6 |
| Keychain conservé après désinstallation | Nettoyage du premier lancement | `CHOIX_CRYPTO.md` §3.8 |
| Détection biométrie ou code | Historique R2 | `CHOIX_CRYPTO.md` §3.6 |

### C6 – Incohérences entre issues et documents (à corriger côté backlog)
- **IOS-2 (#29)** vise « E3 », qui dans le STRIDE désigne l'accès aux secrets de l'équipe via le Mac prêté. La menace pertinente pour IOS-2 semble être **D4** (contrôle impossible affiché comme « aucun traceur ») : à confirmer par Aïda. Le critère D4 n'est pas écrit dans le corps de l'issue.
- Les critères d'acceptation et les tests prévus sont encore « À compléter » sur IOS-2, MAC-1 et sur les issues RT-1 à RT-4.
- **TRU-7** (historique des modifications de la liste, R2) est « proposée » dans le STRIDE mais n'existe pas comme issue.
- **Mention à relativiser** : M6 (red team de l'autre groupe) et RR7 / RR8 sont bien définis dans le STRIDE actuel.

## 3. Questions à poser

**À Aïda**
1. Longueur et dérivation du code court, nombre d'essais autorisés, durée de la fenêtre d'appairage ? (C1)
2. Que signe exactement chaque côté lors de l'échange de clés éphémères ? PROTOCOLE.md sera-t-il écrit avant MAC-3 ? (C4)
3. La menace de IOS-2 est-elle D4 plutôt qu'E3 ? (C6)

**À Onur**
4. Le Mac accepte-t-il plusieurs connexions pendant l'appairage ? Que se passe-t-il pour un second client ? (C1, C2)
5. Y a-t-il un délai d'attente côté centrale pour une connexion silencieuse ? Un nombre maximal de connexions dès MAC-1, sans attendre MAC-6 ? (C2)
6. La purge se déclenche-t-elle aussi à la fermeture de l'app, pas seulement sur action de l'utilisateur ? (C3)

## 4. Besoins matériels

- **Sans Mac** : cette revue, le catalogue de scénarios (RT-2), le plan de tests (SEC-5), la grille MASVS (SEC-7), les modèles de rapport de failles, la préparation des QR et des trames de test.
- **Avec un iPhone et l'app installée** (donc après un build depuis un Mac prêté) : D4, E1, T3, I3, I6 et les scénarios F1 / F5.
- **Avec la centrale qui tourne sur un Mac prêté** : les scénarios F2 et F3. L'envoi de trames TCP vers la centrale peut venir d'un autre ordinateur du même réseau, **[Hypothèse]** si le hotspot autorise la connexion directe entre appareils (déjà l'hypothèse de `transport.md`). Tout script d'attaque est un outil de test, pas une dépendance de l'app ; il est signalé à l'équipe avant d'être ajouté au dépôt.
- **Le Mac prêté lui-même** : le scénario F4 (C3).
- **Données** : uniquement fictives dans les scénarios, les prompts et le dépôt.

## 5. Critères d'acceptation proposés pour l'issue RT-1 (#53)

- [ ] Chaque frontière F1 à F5 a au moins un scénario d'attaque rattaché à RT-2, RT-3 ou RT-4 (tableau du §1).
- [ ] Les constats C1 à C6 sont transmis à Aïda et Onur et leur suivi est tracé (issue ou commentaire).
- [ ] Les questions du §3 ont reçu une réponse ou une décision.
- [ ] Le schéma est relu côté attaquant : aucune frontière de confiance sans contre-mesure documentée.