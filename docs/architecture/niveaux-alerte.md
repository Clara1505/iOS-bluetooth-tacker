# ARCH-4 – Niveaux d'alerte et règle de suivi inter-balayages

> **Statut : proposition, à valider par le groupe.**
> Responsables : Rachel et Eva. Relecture : Clara.
> Dépend de : `modele-donnees.md` (ARCH-3), spike AirTag ARCH-6 (24/11), STRIDE (SEC-1).
> Règle de vérification (CLAUDE.md, section 5) : tout comportement non testé est marqué **[Hypothèse]**.

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

## 4. Niveaux (proposition)

| Niveau | Condition | Commentaire |
|---|---|---|
| **Info** | Appareil inconnu vu dans un seul balayage complet. | Le cas le plus fréquent, et probablement sans danger (un voisin, un casque, un objet). |
| **Alerte** | Même appareil inconnu vu dans au moins deux balayages complets, dans une fenêtre de temps F. | La fenêtre F est à fixer par le groupe après le spike (voir Q1). |
| **Critique** (P2) | À définir après ARCH-6. Non implémenté dans le MVP. | Possible seulement avec un signal plus fort, par exemple la détection d'un traceur de type Find My (IOS-4). |

Règle de priorité : le niveau le plus élevé qui s'applique l'emporte.

## 5. Règle de suivi inter-balayages (proposition)

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
| Appareil vu une seule fois | Info |
| Appareil vu deux fois, à plus de F d'intervalle | Info (pas d'alerte, car hors fenêtre) |
| Appareil absent d'un balayage intermédiaire | Compte comme absent, mais reste dans la fenêtre s'il est revu |
| Identifiant qui change entre deux balayages (H1) | Compté comme deux appareils, risque RR2 accepté et à mesurer |
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

## 9. Tests prévus

- Tests unitaires de chaque niveau et de chaque cas du §6 (QA-2, avec Rachel).
- Tests du contrôle impossible : Bluetooth coupé, permission refusée (D4, IOS-2).
- Tentatives de contournement, par Clara (RT-2) : identifiant qui change, balayages rapprochés, message rejoué.
- Vérification avec un vrai traceur (ARCH-6, puis IOS-9), pas seulement en simulation.
