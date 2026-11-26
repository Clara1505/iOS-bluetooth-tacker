# ARCH-4 – Niveaux d'alerte et règle de suivi inter-balayages

> **Statut : proposition, à valider par le groupe.**
> Responsables : Rachel et Eva. Relecture : Clara.
> Dépend de : `modele-donnees.md` (ARCH-3), spike AirTag ARCH-6 (24/11), STRIDE (SEC-1).
> Règle de vérification (CLAUDE.md, section 5) : tout comportement non testé est marqué **[Hypothèse]**.
>
> **Modification du 25/11 (Rachel, à valider par le groupe)** : pour le MVP (IOS-5), le niveau alerte
> repose sur un seul balayage (« inconnu proche et resté là », §4). La règle sur deux balayages
> devient la règle de suivi d'IOS-6 (§5), à mettre en place après le spike ARCH-6.
> Raisons : elle dépend de Q1 et Q2, encore ouvertes, et de la stabilité des identifiants (H1), non vérifiée.

## 1. Rappel du besoin

- Tout appareil inconnu déclenche un avertissement à 3 niveaux : info, alerte, critique (CLAUDE.md, section 1).
- Le suivi se fait en comparant les balayages entre eux. Il n'y a pas de GPS continu.
- Le niveau critique n'est pas dans le MVP (P2, IOS-5). Ce document le décrit seulement pour mémoire.

## 2. État d'un contrôle, avant tout niveau

Chaque balayage a un résultat (`resultat` dans ARCH-3). Trois cas :

| Résultat | Signification | Affichage |
|---|---|---|
| `complet` | Le balayage s'est déroulé en entier | Liste des appareils, niveaux éventuels |
| `complet`, liste vide | Aucun appareil inconnu détecté | « Aucun appareil inconnu » |
| `controleImpossible` | Bluetooth coupé, permission refusée, interruption | « Contrôle impossible » |

Règle : **un contrôle impossible n'est jamais affiché comme « aucun traceur »** (D4). Un balayage `controleImpossible` n'entre pas dans la règle de suivi (voir §5). C'est une proposition : elle évite de faire baisser un niveau à cause d'un balayage incomplet.

## 3. Définitions

- **Appareil de confiance** : appareil présent dans la liste de confiance (TRU-1, TRU-2). Il ne déclenche jamais d'alerte.
- **Appareil inconnu** : appareil observé qui n'est pas dans la liste de confiance.
- **Même appareil** : critère de reconnaissance d'un appareil inconnu d'un balayage à l'autre. **Ce critère n'est pas encore défini.** Il dépend de ce qui se passe réellement avec les identifiants Bluetooth (H1), à vérifier avec l'AirTag (ARCH-6).
  - Hypothèse de travail : deux observations sont le même appareil si leur `idHache` est identique.
  - Conséquence assumée : si les identifiants changent (H1), un même traceur peut être compté comme plusieurs appareils. Le suivi sera alors moins fiable. C'est le risque résiduel RR2 du STRIDE.

## 4. Niveaux (proposition, modifiée le 25/11)

Un niveau n'est attribué qu'à partir d'un balayage `complet` (§2).

| Niveau | Condition (MVP, IOS-5) | Commentaire |
|---|---|---|
| **Info** | Appareil inconnu qui ne remplit pas la condition d'alerte. | Le cas le plus fréquent, et probablement sans danger (un voisin, un casque, un objet). |
| **Alerte** | Appareil inconnu **proche** (signal ≥ -60 dBm) et **resté là** (au moins 20 s entre sa première et sa dernière détection) pendant un même balayage complet de 30 s. | Seuils **[Hypothèse]**, à régler avec un vrai traceur (ARCH-6, IOS-9). Voir Q5. |
| **Critique** (P2) | À définir après ARCH-6. Non implémenté dans le MVP. | Pistes : détection d'un traceur de type Find My (IOS-4), ou appareil en alerte sur deux balayages (§5). |

Règle de priorité : le niveau le plus élevé qui s'applique l'emporte.

Pourquoi « proche et resté là » : un traceur caché sur l'utilisateur reste près de lui pendant tout le balayage, alors qu'un passant est plus loin ou n'apparaît que quelques secondes. La règle ne dépend pas de la stabilité des identifiants d'un balayage à l'autre (H1), et elle se vérifie en un seul contrôle.

Limites assumées :
- Elle signale un appareil inconnu proche, sans prouver qu'il suit l'utilisateur d'un lieu à l'autre : c'est le rôle de la règle de suivi (§5, IOS-6).
- Sans liste de confiance, les appareils de l'utilisateur (montre, casque) passent en alerte. La liste de confiance (TRU-1, TRU-2) les écarte.
- Un traceur qui émet rarement peut ne pas atteindre 20 s de présence **[Hypothèse]** (fréquence d'émission de l'AirTag à mesurer, ARCH-6).

## 5. Règle de suivi inter-balayages (IOS-6, après ARCH-6)

Cette règle n'est pas dans le MVP. Elle sera ajoutée par IOS-6 si le spike ARCH-6 montre que l'identifiant d'un traceur reste le même d'un balayage à l'autre. Elle donnera alors un niveau alerte supplémentaire : même appareil inconnu vu dans au moins deux balayages complets, dans une fenêtre de temps F.

Après chaque balayage `complet` :

1. Relever les appareils inconnus du balayage.
2. Pour chacun, chercher les observations du même appareil dans les balayages `complet` qui tombent dans la fenêtre F.
3. Attribuer le niveau correspondant (§4).
4. Un appareil qui n'est plus observé pendant F sort de la surveillance. Son niveau retombe. L'alerte déjà affichée reste dans l'historique de la séance.

Les balayages `controleImpossible` sont ignorés par cette règle (§2).

Principe de sécurité : en cas de doute (balayage partiel, identifiant ambigu), on ne baisse pas le niveau de façon silencieuse. Le doute est affiché.

## 6. Cas limites

| Cas | Comportement proposé |
|---|---|
| Inconnu proche et présent ≥ 20 s | Alerte (MVP) |
| Inconnu proche mais vu brièvement | Info (MVP) |
| Inconnu présent tout le balayage mais lointain | Info (MVP) |
| Signal exactement à -60 dBm et présence exactement de 20 s | Alerte (seuils inclus, MVP) |
| RSSI indisponible (ramené à -127) | Info : jamais considéré comme proche (MVP) |
| Appareil vu deux fois, à plus de F d'intervalle | Pas d'alerte par la règle de suivi, car hors fenêtre (IOS-6) |
| Appareil absent d'un balayage intermédiaire | Compte comme absent, mais reste dans la fenêtre s'il est revu (IOS-6) |
| Identifiant qui change entre deux balayages (H1) | Compté comme deux appareils, risque RR2 accepté et à mesurer (IOS-6) |
| Liste vide | « Aucun appareil inconnu », pas d'alerte |
| Balayage interrompu ou Bluetooth coupé | « Contrôle impossible », pas de changement de niveau |
| Liste dépassant le plafond de sécurité (D1) | Plafond appliqué, affichage d'un avertissement, pas de plantage |
| Appareil de confiance qui apparaît | Aucune alerte, quel que soit le nombre de balayages |
| Message rejoué côté Mac (T2) | Rejeté par le compteur et le nonce (MAC-4). Le Mac ne recalcule jamais une alerte à partir d'un message ancien |
| Centrale injoignable (D5) | L'alerte reste affichée sur l'iPhone. Le Mac n'est pas le seul canal |

## 7. Menaces liées

| Menace | Lien avec cette règle |
|---|---|
| S3 | Un traceur imite un appareil de confiance. Le critère « même appareil » et la liste de confiance doivent résister à cela. Mise en garde : contre-mesure encore ouverte (spike ARCH-6). |
| D4 | « Contrôle impossible » distinct de « aucun traceur ». |
| D5 | L'alerte est visible sur l'iPhone, même sans Mac. |
| T2 | Anti-rejeu côté Mac. |
| RR1 | Un traceur qui n'émet pas pendant les 30 s du balayage n'est pas détecté. Conséquence du balayage à la demande. |
| RR2 | Identifiants qui changent : suivi moins fiable. |

## 8. Questions ouvertes (à trancher par le groupe)

- **Q1 – Fenêtre F.** Quelle durée ? La valeur doit être choisie après ARCH-6, et non avant.
- **Q2 – Critère « même appareil ».** Il dépend de H1 et de S3. Décision après ARCH-6.
- **Q3 – Retour au niveau inférieur.** La proposition du §5 fait redescendre un niveau à l'expiration de F. Le groupe doit confirmer ce choix, qui influe sur ce que l'utilisateur voit.
- **Q4 – Définition du niveau critique.** À définir après ARCH-6, et seulement si IOS-4 est retenu.
- **Q5 – Seuils de l'alerte MVP.** -60 dBm et 20 s sont des valeurs provisoires. Elles sont à ajuster après des mesures avec un vrai traceur posé près de l'iPhone puis éloigné (ARCH-6, IOS-9).

Q1, Q2 et Q3 concernent désormais la règle de suivi d'IOS-6 (§5), et non le MVP.

## 9. Tests prévus

- Tests unitaires de chaque niveau et de chaque cas du §6 (QA-2, avec Rachel). Les cas MVP sont couverts par `ReglesAlerteTests` (IOS-5).
- Tests du contrôle impossible : Bluetooth coupé, permission refusée (D4, IOS-2).
- Tentatives de contournement, par Clara (RT-2) : identifiant qui change, balayages rapprochés, message rejoué.
- Vérification avec un vrai traceur (ARCH-6, puis IOS-9), pas seulement en simulation.
