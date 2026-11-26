# ARCH-2 – Choix et justification du transport iPhone ↔ Mac

> **Mise à jour du 26/11 (PM-11)** : le projet passe à Xcode 16.2 et iOS 15 minimum, et tout se compile sur le MacBook Air de Clara. Les Macs prêtés ne servent plus : « Mac prêté » désigne ici le Mac qui héberge la centrale (désormais celui de Clara), dont les règles « sans état persistant » restent inchangées. Sur iPhone, « Face ID » se lit « biométrie (Face ID ou Touch ID) » et le mode `faceID` devient `biometrie` dans le code (valeur stockée inchangée). Voir `CLAUDE.md` §5 et §6.

> **Statut : proposition décidée le 24/11/2026, à valider par le groupe.**
> Responsable : Onur. Relecture : Aïda (sécurité et protocole), Clara (côté attaquant, RT-1 / RT-2).
> Références : `docs/securite/STRIDE.md` (SEC-1), `docs/securite/CHOIX_CRYPTO.md` (SEC-3, section 3.7).
> Règle de vérification (CLAUDE.md, section 5) : tout comportement non encore vérifié sur les appareils est marqué **[Hypothèse]**.

## 1. Décision retenue

- **Framework de transport** : **`Network.framework`** (API native Apple, disponible depuis iOS 12 et macOS 10.14, donc compatible avec la cible iOS 15 (la mention « iOS 17+ » était erronée)) en **TCP** (`NWParameters.tcp`), avec **`NWListener`** côté Mac (centrale) et **`NWConnection`** côté iPhone (capteur).
- **Découverte et adressage** : annonce du service sur le réseau local via **Bonjour / mDNS** (`NWListener.Service`, type `_antitracker._tcp`) et/ou connexion directe par `hôte:port` transmis dans le QR code d'appairage (`MAC-2`).
- **Topologie réseau en séance et démo** : utilisation d'un **partage de connexion (hotspot Wi-Fi) depuis un iPhone du groupe** auquel se connectent le Mac prêté et l'iPhone capteur, afin de contourner l'isolation des clients (*client isolation*) fréquente sur les réseaux Wi-Fi de campus.
- **Principe de sécurité** : conformément à `CLAUDE.md` (section 6) et `STRIDE.md` (frontière `F3`), **le transport est considéré comme non fiable**. Toute la sécurité (authentification, confidentialité, intégrité, anti-rejeu) est assurée au niveau applicatif par notre protocole CryptoKit (`MAC-2`, `MAC-3`, `MAC-4`).

## 2. Justification et comparaison des options

Trois options natives Apple ont été évaluées :

| Critère | `Network.framework` (TCP) — **Retenu** | `MultipeerConnectivity` — Écarté | `CoreBluetooth` (BLE GATT) — Écarté |
|---|---|---|---|
| **Recommandation Apple** | Recommandé par Apple pour tout nouveau développement réseau local (note technique TN3213). | Ancien framework ; Apple recommande de migrer vers `Network.framework`. | Conçu pour des capteurs à très bas débit, pas pour un canal riche iPhone ↔ Mac. |
| **Maîtrise et auditabilité** | Contrôle total des octets envoyés et reçus ; facile à expliquer à l'oral et à instrumenter. | Boîte noire : négociation interne opaque, chiffrement interne impossible à justifier dans le dossier sans certificats (non protégé contre S1). | Fragmentation manuelle complexe (MTU BLE limitée à quelques centaines d'octets). |
| **Tests Red Team (`RT-2`, `RT-4`)** | Très simple d'envoyer des trames malformées, rejouées ou en flood vers le port TCP du Mac. | Difficile d'injecter des trames arbitraires sans réécrire un pair `MultipeerConnectivity`. | Nécessite un émetteur BLE dédié pour injecter des trames GATT. |
| **Interférence avec le scan BLE (`IOS-2`)** | Aucune : passe exclusivement par le Wi-Fi (hotspot). | **[Hypothèse]** Active AWDL et le Bluetooth en arrière-plan, risque d'interférer avec le balayage de 30 s. | Partage la pile BLE de l'iPhone pendant le balayage de détection. |
| **Fiabilité et ordre des messages** | TCP garantit l'ordre et la remise sans perte, ce qui évite de désynchroniser le compteur anti-rejeu (`MAC-4`). | Mode `.reliable` disponible, mais gestion de session moins prévisible. | Risque élevé de perte ou de troncature sur des charges utiles signées + chiffrées. |

### Pourquoi le partage de connexion (hotspot) ?

- Les réseaux Wi-Fi d'entreprise ou d'école appliquent souvent une **isolation des clients** (*AP client isolation*) ou filtrent le multicast (mDNS/Bonjour), empêchant deux appareils sur le même Wi-Fi de s'établir une connexion TCP directe.
- En connectant le Mac prêté au point d'accès personnel (hotspot) d'un téléphone du groupe, l'iPhone et le Mac se trouvent sur un sous-réseau local maîtrisé permettant la communication directe.
- **[Hypothèse]** À confirmer dès le premier test entre l'iPhone et le Mac prêté (`MAC-1`) : vérifier que le hotspot iOS autorise la visibilité Bonjour et les connexions TCP directes entre le téléphone (ou un second iPhone connecté au même hotspot) et le Mac.
  - *Repli prévu si l'iPhone émetteur du hotspot filtre Bonjour* : utiliser le hotspot d'un deuxième téléphone du groupe sur lequel se connectent l'iPhone capteur et le Mac, ou passer directement l'adresse `IP:port` du Mac dans le QR code d'appairage (`MAC-2`).

## 3. Fonctionnement technique et cadrage des trames (*Framing*)

### 3.1 Rôles réseau

1. **Centrale Mac (`NWListener`)** :
   - Démarre un serveur TCP (`NWParameters.tcp`) sur le réseau local.
   - Annonce le service Bonjour `_antitracker._tcp` (et affiche son point de terminaison / identifiant dans le QR code d'appairage `MAC-2`).
   - À chaque connexion entrante (`newConnectionHandler`), reçoit un objet `NWConnection` dédié à ce client.
2. **Capteur iPhone (`NWConnection`)** :
   - Découvre le service ou lit les coordonnées du Mac lors du scan du QR code (`MAC-2`).
   - Ouvre une connexion TCP (`NWConnection`) vers la centrale Mac.

### 3.2 Découpage des messages sur le flux TCP (*Length-Prefix Framing*)

TCP étant un flux continu d'octets (*byte stream*) et non un protocole orienté messages, un appel à `send` peut être fragmenté ou concaténé à la réception. Pour garantir que CryptoKit (`AES.GCM.open` et vérification de signature ECDSA) reçoive toujours un message complet et exact, chaque message sur le fil suit le format suivant :

```text
+------------------------------------+--------------------------------------------------+
| En-tête : Taille N (4 octets)      | Charge utile : Message du protocole (N octets)   |
| UInt32 en Big-Endian (réseau)      | Données d'appairage ou événement chiffré/signé   |
+------------------------------------+--------------------------------------------------+
```

**Algorithme de lecture côté récepteur (sans `!`, `try!` ni `fatalError`) :**
1. Lire exactement **4 octets** via `connection.receive(minimumIncompleteLength: 4, maximumLength: 4)`.
2. Décoder la taille `N` (`UInt32` big-endian).
3. **Validation de sécurité immédiate (contre `D2` et `D3`)** :
   - Vérifier que `1 <= N <= TAILLE_MAX_MESSAGE` (plafond fixé à **64 Ko**, soit `65_536` octets, largement supérieur à la taille d'une alerte signée et chiffrée).
   - Si `N == 0` ou `N > TAILLE_MAX_MESSAGE`, ou si la connexion se ferme prématurément : **rejeter immédiatement et fermer la connexion** (`connection.cancel()`), sans allouer de tampon mémoire de taille `N`.
4. Lire exactement **`N` octets** via `connection.receive(minimumIncompleteLength: Int(N), maximumLength: Int(N))`.
5. Transmettre les `N` octets au module du protocole sécurisé (`MAC-2`, `MAC-3`, `MAC-4`), puis relancer la lecture de l'en-tête suivant.

## 4. Permissions et configuration Xcode requises

Conformément au principe de moindre privilège (`CLAUDE.md`, section 5) :

- **Côté iPhone (`Info.plist`)** :
  - `NSLocalNetworkUsageDescription` : explication claire affichée à l'utilisateur au moment de la première connexion au Mac.
  - `NSBonjourServices` : `["_antitracker._tcp"]` (si la découverte Bonjour est activée).
  - Interdiction de l'interface cellulaire sur la connexion locale (`parametres.prohibitedInterfaceTypes = [.cellular]`) pour garantir que le trafic ne sort jamais du réseau local.
- **Côté Mac (`Entitlements` / App Sandbox)** :
  - `com.apple.security.network.server` (`Incoming Connections`) pour autoriser `NWListener`.
  - `com.apple.security.network.client` (`Outgoing Connections`).

## 5. Menaces STRIDE visées et contre-mesures au niveau transport

Le transport traverse la frontière **`F3` (Réseau local iPhone ↔ Mac)** définie dans `STRIDE.md`.

| Menace | Description dans `STRIDE.md` | Rôle du transport et des couches supérieures |
|---|---|---|
| **S1, S2** | Faux Mac lors de l'appairage ou faux iPhone émettant des alertes sur le réseau local | Le transport TCP n'authentifie personne : tout pair non appairé via le QR code (`MAC-2`) ou tout message non signé par la clé Secure Enclave (`MAC-4`) est rejeté. |
| **I1, T1** | Écoute ou altération du trafic sur le hotspot / réseau local | Le transport est considéré comme public : confidentialité et intégrité assurées par ECDH éphémère + HKDF-SHA256 + AES-256-GCM (`MAC-3`) et signature ECDSA (`MAC-4`). |
| **T2** | Rejeu d'un paquet TCP capturé | Bloqué au-dessus du transport par les clés de session éphémères (`MAC-3`), le compteur strictement croissant, le nonce et l'horodatage à ±60 s (`MAC-4`). |
| **D2, E2** | Flood de connexions ou de messages vers la centrale par un appareil du réseau local | Plafond de taille de trame à 64 Ko dès les 4 premiers octets ; limitation du nombre de connexions simultanées ; fermeture rapide de toute connexion qui n'envoie pas un message authentifié valide (`MAC-6`). |
| **D3** | Trame tronquée ou malformée envoyée sur le port TCP pour faire planter l'app | Validation stricte de la taille `N` et du format avant décodage ; aucun `!`, `try!` ni `fatalError` sur les octets reçus du réseau. |
| **D5** | Centrale Mac injoignable (coupure Wi-Fi / hotspot) | Échec géré proprement sur l'iPhone (délai d'expiration / état déconnecté) : l'alerte reste toujours affichée localement sur l'iPhone (`IOS-8`), le Mac n'étant pas le seul canal. |

## 6. Tests prévus

- **Test de connectivité réelle (`MAC-1`)** : établir la connexion TCP iPhone ↔ Mac prêté via le hotspot d'un téléphone et vérifier la réception d'une alerte de test.
- **Tests de robustesse du cadrage (`QA-3` / `SEC-6` / `RT-2`)** :
  - Envoi d'un en-tête de taille `0` ou supérieure à `64 Ko` (ex. `0xFFFFFFFF`) → la centrale ferme la connexion sans planter ni allouer la mémoire.
  - Envoi d'une trame tronquée (connexion fermée au milieu des `N` octets) → rejet propre sans blocage.
  - Envoi d'octets aléatoires non valides → échec de vérification/déchiffrement et rejet en sécurité.
- **Test de perte réseau (`D5`)** : couper la connexion au Mac pendant un contrôle → l'app iPhone ne plante pas et conserve l'affichage local de l'alerte.
