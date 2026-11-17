# Essayer SpektraLR dans le vrai Lightroom, sans cliquer

Un petit module Lightroom Classic, `SpektraLR (essai)`, qui exécute des commandes déposées dans un fichier. C'est ce qui
m'a servi à vérifier les profils et le module sur des copies virtuelles de mes photos : copie, presets, lecture des
réglages, exports, tirage du module.

## Installer

```sh
sh outils/essai-lr/installer.sh            # copie le module dans ~/Library/Application Support/Adobe/Lightroom/Modules/
sh outils/essai-lr/installer.sh --retirer  # le met à la corbeille
```

Puis relancer Lightroom. Le module dort jusqu'au premier lien `lightroom://com.thomashammoudi.spektralr.essai/…`, que
`pilote.py` ouvre tout seul s'il ne répond pas.

## Commandes

```sh
python3 outils/essai-lr/pilote.py '{"action": "ping"}'
python3 outils/essai-lr/pilote.py '{"action": "presets", "dossier": "SpektraLR"}'
python3 outils/essai-lr/pilote.py '{"action": "copie", "chemin": "/chemin/du/RAW.RAF", "nom": "SpektraLR", "cle": "a", "collection": "SpektraLR (essai)"}'
python3 outils/essai-lr/pilote.py '{"action": "rendre", "cle": "a", "etapes": [{"preset": "Kodak Portra 400"}], "dossier": "/tmp", "nom": "a-portra", "export": {"format": "JPEG", "taille": 2400}}'
```

| Action | Ce qu'elle fait |
|---|---|
| `ping` | version de Lightroom et catalogue ouvert |
| `chercher` | les photos d'un nom de fichier, avec leurs principaux réglages |
| `presets` | les dossiers de presets et leurs noms |
| `copie` | une copie virtuelle de la photo, vérifiée (elle doit venir de la bonne photo maîtresse), rangée dans une collection |
| `rendre` | presets ou réglages appliqués à une copie, lecture des réglages, export JPEG sRGB ou TIFF ProPhoto 16 bits |
| `tirer` | le tirage du module SpektraLR (`Tirage.lua`) sur une copie |
| `inventaire`, `adopter` | les photos d'une collection ; reprendre une copie sous une clé, après un redémarrage |
| `retirer` | retirer du catalogue des copies virtuelles, ou les tirages du module (leur fichier reste sur le disque) |
| `relancer.py` (script à part) | redémarrer Lightroom (fermer, attendre la sauvegarde, relancer) ; le clic « Sauvegarder » reste à faire par computer-use |
| `rapide` | la collection rapide (touche B) : `{"op": "lister"}`, `"vider"`, `"ajouter"` avec `ids` (copies virtuelles seulement) |
| `lua` | un bout de Lua, pour le diagnostic |

Le module ne touche jamais une photo maîtresse : il ne travaille que sur les copies virtuelles qu'il a créées, et ne
retire du catalogue qu'une copie virtuelle ou un tirage qu'on lui nomme. Depuis le 14/11/2026 c'est un verrou dans le
code : `rendre`, `tirer` et `adopter` refusent toute photo qui n'est pas une copie virtuelle. Seule exception voulue :
`rapide` `vider` retire de la collection rapide ce qui s'y trouve (l'appartenance seulement, pas les réglages). Les copies restent d'un essai à l'autre dans
une même collection : on les reprend au lieu d'en refaire.

`comparer.py` compare l'export d'un profil par Lightroom à la table appliquée à la main (résultat dans
[la fabrication des profils](../../docs/fabrication-des-profils.md#les-contrôles)).

## Pièges

- **Ne jamais quitter Lightroom par `osascript … to quit` quand Thomas est absent** : la fenêtre « Sauvegarder le catalogue » s'ouvre et attend un clic (14/11/2026). Tant qu'elle est ouverte, l'écriture au catalogue passe (copies, réglages, collections), mais tout ce qui passe par l'interface reste sans effet : collection rapide, `retirer`.
  **Règle de Thomas (14/11/2026) : toujours « Sauvegarder », sans le déranger.** La sauvegarde est réglée « À chaque
  fermeture de Lightroom ». Les commandes de Claude n'ont pas l'accessibilité : System Events refusé (y compris dans un
  `.command` ouvert par Terminal.app, vérifié), touches et clics de `CGEventPostToPid` ignorés ; emprunter les droits
  d'une autre appli (workflow Alfred) est refusé par les permissions de Claude Code, à juste titre. Le seul clic
  possible est celui de l'outil computer-use (`app_click`), qui demande une autorisation affichée sur l'écran du Mac :
  refusée d'office quand Thomas est à distance. Donc : **ne fermer Lightroom que si ce clic est possible**, et préférer
  tout faire sans redémarrer. `python3 relancer.py` ferme, signale la fenêtre, attend la sauvegarde, relance et attend
  le pilote.
- Lightroom ne relit presets et modules externes qu'à son lancement : `relancer.py` après en avoir écrit.
- **Collection rapide** (touche B) : `catalog.kQuickCollectionIdentifier` pour l'afficher, `photo:addOrRemoveFromTargetCollection()` pour basculer une photo, **qui n'agit que si la photo est sélectionnée et cible** (sinon rien, sans erreur) : l'action `rapide` la montre dans une collection temporaire, la sélectionne, attend qu'elle soit la cible, puis bascule, une écriture par photo. La cible doit être la collection rapide (réglage par défaut de Lightroom).
- De nouveaux `.xmp` de presets ne sont vus qu'après un redémarrage de Lightroom.

## Sources

- Le [SDK Lightroom Classic](https://developer.adobe.com/lightroom-classic/) d'Adobe : `LrCatalog`, `LrPhoto`,
  `LrExportSession`, `LrDevelopPreset`.
- Le réveil par un lien `lightroom://` : la clé `URLHandler` d'`Info.lua`, comme le module Flickr livré avec Lightroom.
- La copie virtuelle vérifiée : sélectionner la photo, attendre qu'elle soit la cible, puis seulement créer la copie,
  comme le fait l'importeur Aperture/iPhoto livré avec Lightroom.
- Le retrait du catalogue : `LrPhoto` n'a pas de suppression, `LrSelection.removeFromCatalog` agit sur la sélection.
  Les photos sont montrées seules dans une collection temporaire, et la sélection vérifiée avant le retrait.
- L'idée d'un module qui interroge un point d'entrée local : [lightroom-py](https://github.com/drshy-org/lightroom-py)
  (MIT), qui passe par un serveur HTTP Python. Ici, un simple dossier, et rien à installer à côté de Lightroom.
