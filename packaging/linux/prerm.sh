#!/bin/sh
# Au moment de retirer le paquet, on defait la mise a jour des caches : sans
# cela l'icone du jeu reste dans le cache GTK et le menu garde une entree
# fantome qui ne demarre plus.
set -e

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi

exit 0
