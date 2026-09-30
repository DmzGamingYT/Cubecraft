#!/usr/bin/env bash
#
# Lance une suite de verifications et reessaie si elle echoue.
#
# Usage : run-suite.sh <libelle> <commande...>
# Env   : ATTEMPTS (defaut 3)
#
# Pourquoi un script et non une fonction exportee dans $GITHUB_PATH : ce
# mecanisme n'ajoute que des executables au PATH, il ne propage pas les
# fonctions shell d'une etape a l'autre. Une fonction ecritue ainsi existe
# seulement dans l'etape qui l'a definie, et l'etape suivante echoue sur
# « command not found » avant meme d'avoir lance Godot.
#
# Pourquoi reessayer : l'interface et le reseau sont sensibles au temps qui
# passe. Sous charge CPU -- deux tournees en parallele, ou un simple godot
# lance juste avant -- l'interface peut rater le controle des fissures de
# minage, et le reseau depasser son delai. Un echec isole la-dessus est du
# bruit, pas une regression. Seule une repetition fait tomber le build.

set -uo pipefail

label="${1:?usage : run-suite.sh <libelle> <commande...>}"
shift

attempts="${ATTEMPTS:-3}"
attempt=1

while [ "$attempt" -le "$attempts" ]; do
  echo "::group::$label — tentative $attempt/$attempts"
  if "$@"; then
    echo "::endgroup::"
    echo "$label : OK (tentative $attempt)"
    exit 0
  fi
  echo "::endgroup::"
  echo "$label : echec (tentative $attempt/$attempts)"
  attempt=$((attempt + 1))
  [ "$attempt" -le "$attempts" ] && sleep 5
done

echo "$label : echec sur $attempts tentatives"
exit 1
