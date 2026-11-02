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
| `inventaire`, `adopter`, `ecarter` | les photos d'une collection ; reprendre une copie après un redémarrage ; mettre de côté une copie ratée |
| `lua` | un bout de Lua, pour le diagnostic |

Le module ne touche jamais une photo maîtresse : il ne travaille que sur les copies virtuelles qu'il a créées.

`comparer.py` compare l'export d'un profil par Lightroom à la table appliquée à la main (résultat dans
[la fabrication des profils](../../docs/fabrication-des-profils.md#les-contrôles)).

## Sources

- Le [SDK Lightroom Classic](https://developer.adobe.com/lightroom-classic/) d'Adobe : `LrCatalog`, `LrPhoto`,
  `LrExportSession`, `LrDevelopPreset`.
- Le réveil par un lien `lightroom://` : la clé `URLHandler` d'`Info.lua`, comme le module Flickr livré avec Lightroom.
- La copie virtuelle vérifiée : sélectionner la photo, attendre qu'elle soit la cible, puis seulement créer la copie,
  comme le fait l'importeur Aperture/iPhoto livré avec Lightroom.
- L'idée d'un module qui interroge un point d'entrée local : [lightroom-py](https://github.com/drshy-org/lightroom-py)
  (MIT), qui passe par un serveur HTTP Python. Ici, un simple dossier, et rien à installer à côté de Lightroom.
