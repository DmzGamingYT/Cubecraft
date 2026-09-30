#!/usr/bin/env python3
"""Construit le `.dmg` de Cubecraft, celui qu'un utilisateur de macOS voit.

Godot sait produire un `.dmg`, mais il n'y met que le `.app` : pas de fond,
pas de fleche, pas de lien vers `Applications`. A la lecture, le volume est
vide. C'est `create-dmg` (libre, https://github.com/create-dmg/create-dmg)
qui arrange les icones et dessine la fleche ; le fond, lui, est produit ici.

Le fond est genere plutot que livre en PNG pour une raison concrete : il porte
les coordonnees des icones. Si l'une bouge, le fond doit bouger avec, sinon la
fleche ne pointe plus sur `Applications`. Les deux sont donc calcules depuis
les memes constantes.

Usage :  python3 packaging/make_dmg.py build/macos/Cubecraft.zip build/macos/Cubecraft.dmg
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Geometrie de la fenetre du `.dmg`, en points. Tout le reste s'en deduit.
WINDOW = (660, 400)
ICON_SIZE = 128
APP_CENTER = (180, 186)      # ou pose le .app
LINK_CENTER = (480, 186)     # ou pose le lien vers Applications
SCALE = 2                    # rendu retina

SKY_TOP = (74, 159, 216)
SKY_BOTTOM = (31, 100, 160)
INK = (255, 255, 255)

FONT_CANDIDATES = (
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial.ttf",
)


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def make_background(path: str) -> None:
    """Fond degrade + fleche + deux lignes d'explication."""
    w, h = WINDOW[0] * SCALE, WINDOW[1] * SCALE
    image = Image.new("RGB", (w, h), SKY_TOP)
    draw = ImageDraw.Draw(image)

    for y in range(h):
        t = y / max(1, h - 1)
        draw.line(
            (0, y, w, y),
            fill=tuple(round(SKY_TOP[i] + (SKY_BOTTOM[i] - SKY_TOP[i]) * t) for i in range(3)),
        )

    # Geometrie, en pixels de la planche 2x. Tout ce qui suit se deduit d'ici.
    ax, ay = APP_CENTER[0] * SCALE, APP_CENTER[1] * SCALE
    lx, ly = LINK_CENTER[0] * SCALE, LINK_CENTER[1] * SCALE
    half = (ICON_SIZE * SCALE) / 2

    # L'icone du jeu est bleu clair : sur un fond clair elle disparaissait.
    # Le fond est donc volontairement sombre, et tout ce qu'on y ecrit est
    # blanc. C'est le contraste qui fait lire l'icone, pas sa taille.
    #
    # Une lueur derriere l'icone pour la detacher du fond, facon les fonds
    # de `.dmg` qui Background Composer vend au pixel.
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse(
        (ax - half * 1.5, ay - half * 1.5, ax + half * 1.5, ay + half * 1.5), fill=58
    )
    glow = glow.filter(ImageFilter.GaussianBlur(w // 14))
    image = Image.composite(Image.new("RGB", (w, h), (255, 255, 255)), image, glow)
    # `image` vient d'etre remplace : le crayon doit etre recree, sinon tout
    # ce qui suit (fleche, textes) part sur l'ancienne image, perdue.
    draw = ImageDraw.Draw(image)

    # La fleche part du bord droit de l'icone et finit avant le lien, pour
    # qu'elle ne touche ni l'un ni l'autre. On la dessine sur trois fois la
    # taille puis on reduit : une pointe de triangle sans anti-aliasing se
    # voit a plein ecran, et c'est la seule forme du fond qui attire l'oeil.
    start_x, end_x = ax + half + 34, lx - half - 34
    mid = (start_x + end_x) / 2
    aa = 3
    shaft = 11 * SCALE
    head = 26 * SCALE
    arrow = Image.new("RGBA", (int(end_x - start_x) + 2 * SCALE, int(2 * head)), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arrow)
    local_end = arrow.width - 2 * SCALE
    ad.line((0, arrow.height // 2, local_end - head, arrow.height // 2), fill=INK + (255,), width=shaft)
    ad.polygon(
        (
            (local_end, arrow.height // 2),
            (local_end - head, arrow.height // 2 - head),
            (local_end - head, arrow.height // 2 + head),
        ),
        fill=INK + (255,),
    )
    arrow = arrow.resize(
        (arrow.width // aa, arrow.height // aa), Image.LANCZOS
    )
    image.paste(arrow, (int(start_x), int(ay - arrow.height / 2)), arrow)

    title = load_font(28 * SCALE)
    hint = load_font(16 * SCALE)
    anchor_y = ay + half + 46 * SCALE

    draw.text((mid, anchor_y), "Installer Cubecraft", font=title, fill=INK, anchor="mm")
    draw.text(
        (mid, anchor_y + 34 * SCALE),
        "Glissez l'icone dans Applications pour l'installer.",
        font=hint,
        fill=(214, 236, 252),
        anchor="mm",
    )

    image.save(path)


def build(zip_path: str, dmg_path: str, work_dir: str) -> None:
    if not os.path.exists(zip_path):
        raise SystemExit(f"introuvable : {zip_path}")
    os.makedirs(work_dir, exist_ok=True)

    # Le `.app` est decompresse hors du projet, volontairement. Godot
    # emballe dans le jeu toutes les ressources qu'il trouve sur le disque,
    # y compris les dossiers ignores par git : un `.app` de 170 Mo posé dans
    # `build/` se retrouveva dans le PCK du joueur. Le repertoire de travail
    # est donc un dossier temporaire, hors du depot.
    stage = tempfile.mkdtemp(prefix="cubecraft-dmg-")
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(stage)

    apps = [d for d in os.listdir(stage) if d.endswith(".app")]
    if len(apps) != 1:
        raise SystemExit(f"un seul .app attendu dans l'archive, trouve : {apps}")
    app = apps[0]
    if app != "Cubecraft.app":
        os.rename(os.path.join(stage, app), os.path.join(stage, "Cubecraft.app"))
        app = "Cubecraft.app"

    background = os.path.join(work_dir, "dmg-background.png")
    make_background(background)

    # Chemins absolus : le dossier du projet peut contenir un espace
    # ("Games Godoot"), et create-dmg fait un `cd` sur le dossier source.
    app_abs = os.path.abspath(os.path.join(stage, app))
    dmg_abs = os.path.abspath(dmg_path)
    background_abs = os.path.abspath(background)

    subprocess.run(
        [
            "create-dmg",
            "--volname", "Cubecraft",
            # Deux arguments distincts, pas "660,400" : le handler de
            # create-dmg 1.3.0 decale trois fois et mange l'option suivante
            # si les deux dimensions arrivent en un seul mot.
            "--window-size", str(WINDOW[0]), str(WINDOW[1]),
            "--icon-size", str(ICON_SIZE),
            "--icon", app, str(APP_CENTER[0]), str(APP_CENTER[1]),
            "--app-drop-link", str(LINK_CENTER[0]), str(LINK_CENTER[1]),
            "--background", background_abs,
            "--no-internet-enable",
            dmg_abs,
            app_abs,
        ],
        check=True,
    )
    shutil.rmtree(stage, ignore_errors=True)
    print(f"  {dmg_path}  {os.path.getsize(dmg_path):,} octets")


def main(argv: list[str]) -> int:
    zip_path = argv[1] if len(argv) > 1 else "build/macos/Cubecraft.zip"
    dmg_path = argv[2] if len(argv) > 2 else "build/macos/Cubecraft.dmg"
    work_dir = argv[3] if len(argv) > 3 else "build/macos"

    os.makedirs(os.path.dirname(dmg_path) or ".", exist_ok=True)
    build(zip_path, dmg_path, work_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
