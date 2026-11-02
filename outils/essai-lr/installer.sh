#!/bin/sh
# Installe (ou met à jour) le module d'essai dans les modules de Lightroom : une vraie copie, hors de la synchro, avec
# les fichiers du module SpektraLR dont il se sert. Lightroom le charge à son prochain lancement.
#   sh outils/essai-lr/installer.sh            installer
#   sh outils/essai-lr/installer.sh --retirer  le mettre à la corbeille
set -e
ICI=$(cd "$(dirname "$0")" && pwd)
CIBLE="$HOME/Library/Application Support/Adobe/Lightroom/Modules/SpektraLR-Essai.lrplugin"
if [ "$1" = "--retirer" ]; then
  [ -d "$CIBLE" ] && mv "$CIBLE" "$HOME/.Trash/SpektraLR-Essai-$(date +%Y%m%d-%H%M%S).lrplugin"
  exit 0
fi
mkdir -p "$CIBLE"
cp "$ICI"/Info.lua "$ICI"/Init.lua "$ICI"/Arret.lua "$ICI"/Pilote.lua "$ICI"/Etat.lua "$ICI"/URLHandler.lua "$CIBLE"/
for f in Json Spektra Reglages Tirage; do cp "$ICI/../../SpektraLR.lrplugin/$f.lua" "$CIBLE"/; done
echo "installé : $CIBLE"
