#!/bin/sh
# Lanceur de Cubecraft. Le jeu vit dans /opt/cubecraft ; ce script n'est la
# que pour qu'un utilisateur tape `cubecraft` et pas un chemin de 40 caracteres.
#
# Les arguments sont transmis tels quels : c'est ce qui permet de lancer le jeu
# en choosesant sa graine (`cubecraft --seed=1234`) ou de reprendre une partie.
set -e
exec /opt/cubecraft/Cubecraft.x86_64 "$@"
