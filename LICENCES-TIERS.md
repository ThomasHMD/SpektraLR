# Licences tierces

| Élément | Rôle dans SpektraLR | Source | Licence | Dans ce dépôt ? |
|---|---|---|---|---|
| spektrafilm (Andrea Volpato) | modèle de film : les 20 profils sont calculés avec lui | [github.com/andreavolpato/spektrafilm](https://github.com/andreavolpato/spektrafilm), version 0.3.4 (commit `3bb2c2d`) | code GPL-3.0 ; profils de films, LUT et dérivés directs CC BY-SA 4.0 (`SPEKTRAFILM_LICENSE.txt`) | non pour le code ; oui pour les tables dérivées (`presets/SpektraLR/Profils/`), sous CC BY-SA 4.0, avec `SPEKTRAFILM_LICENSE.txt` tel quel et le `CHANGELOG.txt` des modifications |
| SpektraLab (Hanze Qiu) | le module appelle sa commande `spektralab` pour les tirages | [github.com/JamesQiu2005/SpektraLab](https://github.com/JamesQiu2005/SpektraLab) | GPL-3.0-or-later ; profils et tables CC BY-SA 4.0 ; le nom et l'icône SpektraLab sont une marque, hors licence | non : à installer à part |
| DNG SDK d'Adobe 1.7.1 | format des tables des profils (`dng_big_table`), gamma 1,8 de ProPhoto, courbe de tons ACR3 et son application « RGBTone » | [Adobe, Digital Negative](https://helpx.adobe.com/camera-raw/desktop/dng-and-file-formats/digital-negative.html) | licence du SDK d'Adobe | non : `adobe_table.py` réécrit le format d'après le code ; la table de la courbe ACR3 est lue dans `dng_render.cpp`, fourni par l'utilisateur, et n'est pas redistribuée |
| RAWmakase, CUBE-to-XMP | documentation et écrivains publics du format des tables, pour vérifier | [pch/rawmakase](https://github.com/pch/rawmakase), [OwenWhw/CUBE-to-XMP](https://github.com/OwenWhw/CUBE-to-XMP) | MIT | non : rien n'est recopié |

Les photos des planches (`docs/figures/`) sont les miennes, prises au Fujifilm X-T4, et rendues par SpektraLab. Elles
et l'image d'aperçu sont © Thomas Hammoudi, tous droits réservés : ni la GPL-3.0 ni la CC BY-SA 4.0 ne s'y appliquent.
