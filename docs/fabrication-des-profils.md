# La fabrication des profils

Un profil créatif de Lightroom, c'est un fichier `.xmp` qui contient une table 3D : pour chaque couleur d'entrée, la
couleur de sortie. SpektraLR en calcule une par film avec spektrafilm. La difficulté est ailleurs : savoir ce que
Lightroom donne à cette table.

## Ce que reçoit la table

Une image **déjà rendue**, pas la lumière de la scène. Lightroom applique d'abord le profil de base, sa courbe de tons,
puis les réglages de tons, la courbe et le TSL. Ensuite seulement vient la table, en ProPhoto RGB, encodée en gamma 1,8
et bornée entre 0 et 1. L'étalonnage couleur passe après. C'est ce que montrent le rendu de référence du DNG SDK
d'Adobe et les mesures publiées par [RAWmakase](https://github.com/pch/rawmakase) sur Camera Raw 18.7.

Or spektrafilm attend une scène : une lumière linéaire, où le gris de 18 % vaut 0,18. Passer directement le rendu
d'Adobe dans le film empilerait deux courbes, celle d'Adobe puis celle du tirage, avec des ombres bouchées et un
contraste trop fort.

## La table de SpektraLR

Chaque profil impose sa base, **Adobe Standard**, comme le font les profils « Camera Matching » d'Adobe. La table sait
donc exactement ce qu'elle reçoit et peut le défaire. Pour chacun des 32 × 32 × 32 nœuds, elle :

1. décode le gamma 1,8 d'Adobe ;
2. défait la courbe de tons ACR3, celle d'Adobe Standard. La courbe s'applique au canal le plus fort et au plus faible,
   et le canal du milieu suit au même rapport pour garder la teinte. Son inverse est exacte ;
3. ramène le gris que Lightroom rend à L* 50 au gris de 18 % de la scène ;
4. passe la scène dans spektrafilm, en mode table (sans grain, sans halo, sans effet qui dépend des pixels voisins).
   Un négatif est tiré sur le papier qu'il conseille ; une diapositive est scannée ;
5. règle la luminosité sur le blanc du papier (le papier vierge sort à L* 100 et garde sa teinte), et décale
   l'exposition pour que le gris de 18 % sorte à 118/255 ;
6. réencode en gamma 1,8.

À Quantité 0 %, on retrouve Adobe Standard ; l'Exposition de Lightroom devient l'exposition du film.

## Le format du fichier

La table est un bloc binaire petit-boutiste. On y trouve un en-tête, puis 32³ triplets 16 bits stockés en écart à
l'identité, et enfin l'espace (ProPhoto), le gamma (1,8), le gamut et les bornes de la Quantité (0 à 200 %). Ce bloc
est compressé en zlib, puis codé en base 85 avec l'alphabet d'Adobe. Le nom de la table est l'empreinte MD5 du bloc,
en majuscules. Tout cela vient du DNG SDK d'Adobe (`dng_big_table.cpp`).

`outils/adobe_table.py` l'écrit et le relit. Pour le vérifier, je l'ai fait relire puis réécrire une table d'un
profil d'Adobe : le texte produit est identique, caractère pour caractère.

## Les contrôles

`tests/test_profils.py` relit chaque profil livré et vérifie que :
- l'empreinte correspond bien à la table ;
- l'en-tête est celui attendu ;
- un gris reste neutre ;
- chaque preset cite le bon profil.

Pendant le calcul, `fabriquer_profils.py` affiche pour chaque film où sort le gris d'Adobe : entre L* 49,1 et 49,3, pour
une cible à 49,6.

Dans le vrai Lightroom Classic (15.6), sur une copie virtuelle d'un RAW de mon X-T4, j'ai exporté le même cadrage deux
fois en TIFF ProPhoto 16 bits : en Adobe Standard, puis avec le profil. J'ai appliqué la table moi-même au premier export
(`outils/essai-lr/comparer.py`) et comparé le résultat au second. L'écart moyen est de ΔE 0,16 pour la Portra 400 et de
0,30 pour la Velvia 100 ; 95 % des pixels restent sous 0,6 et 1,2. Le profil, lui, déplace les couleurs de 3,3 et 5,1
en moyenne. Lightroom lit donc la table à l'étape, dans le codage et dans l'ordre des canaux prévus.

## Ce qui reste approché

- La courbe ACR3 est celle du SDK d'Adobe. Si Lightroom ajoutait une correction propre à un boîtier, l'inversion
  serait un peu décalée.
- Les curseurs Ombres et Hautes lumières agissent localement avant la table : ils changent un peu ce qu'elle reçoit.
- Au-delà du blanc rendu par Adobe, l'information est perdue. Le module, lui, part du RAW : il garde toute la latitude
  du film.
