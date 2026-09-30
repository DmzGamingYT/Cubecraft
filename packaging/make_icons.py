#!/usr/bin/env python3
"""Fabrique les icones des installeurs a partir du dessin de `icon.svg`.

`icon.svg` fait 128x128 : c'est assez pour l'icone de l'editeur, pas pour
un installeur. Un `.dmg` montre l'icone en 128, un `.ico` Windows en 256, et
les vignettes Linux en 512. Agrandir le SVG donnerait un bord flou.

Le dessin n'est fait que d'un rectangle et de trois polygones, on le redessine
donc a la taille voulue avec Pillow, en supersample puis reduction : le trait
reste net a toutes les tailles, ce qu'un redimensionnement n'aurait pas donne.

Sorties (dans `assets/icons/`) :
    PNG de 16 a 1024, `cubecraft.icns` (macOS), `cubecraft.ico` (Windows),
    et le jeu d'icones hicolor pour Linux.

Usage :  python3 packaging/make_icons.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

# Le dessin d'origine, en coordonnees du viewBox 128x128 de icon.svg.
SKY = (127, 199, 245, 255)
TOP = (106, 176, 76, 255)
LEFT = (122, 82, 48, 255)
RIGHT = (141, 95, 54, 255)

# Points des trois faces du bloc, isometrique : dessus, flanc gauche, flanc droit.
FACES = (
    (TOP, ((64, 20), (106, 42), (64, 64), (22, 42))),
    (LEFT, ((22, 42), (64, 64), (64, 108), (22, 86))),
    (RIGHT, ((106, 42), (64, 64), (64, 108), (106, 86))),
)

DESIGN = 128.0          # taille du viewBox d'origine
SUPERSAMPLE = 4         # facteur de surechantillonnage avant reduction
PNG_SIZES = (16, 32, 48, 64, 128, 256, 512, 1024)
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)


def rounded_mask(size: int, radius_ratio: float) -> Image.Image:
    """Masque arrondi. Le ratio reproduit le carre arrondi de macOS."""
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=int(size * radius_ratio), fill=255
    )
    return mask


def draw_icon(size: int, *, rounded: bool) -> Image.Image:
    """Dessine l'icone a `size` pixels, avec ou sans fond arrondi."""
    big = size * SUPERSAMPLE
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    if rounded:
        draw.rounded_rectangle(
            (0, 0, big - 1, big - 1), radius=int(big * 0.2237), fill=SKY
        )
    else:
        draw.rectangle((0, 0, big - 1, big - 1), fill=SKY)

    # Le dessin d'origine occupe toute la largeur. On le laisse respirer :
    # dans une icone d'installeur, un bloc colle aux bords parait tronque.
    inner = big * (0.80 if rounded else 0.94)
    scale = inner / DESIGN
    offset = (big - inner) / 2.0

    for colour, points in FACES:
        moved = [(offset + x * scale, offset + y * scale) for x, y in points]
        draw.polygon(moved, fill=colour)

    if rounded:
        # Le masque arrondi est applique apres : le bloc deborde legerement du
        # carre, comme sur l'icone de Boot Camp.
        image.putalpha(rounded_mask(big, 0.2237))
        image = image.resize((size, size), Image.LANCZOS)
    else:
        image = image.resize((size, size), Image.LANCZOS)

    return image


def write_pngs(out_dir: str) -> list[int]:
    written = []
    for size in PNG_SIZES:
        draw_icon(size, rounded=False).save(os.path.join(out_dir, f"cubecraft-{size}.png"))
        written.append(size)
    # Version arrondie pour macOS et pour le menu des applications Linux.
    for size in PNG_SIZES:
        draw_icon(size, rounded=True).save(
            os.path.join(out_dir, f"cubecraft-rounded-{size}.png")
        )
    return written


def write_icns(out_dir: str) -> None:
    """`iconutil` ne lit qu'un dossier d'icones nommees `icon_<n>.png`."""
    with tempfile.TemporaryDirectory() as tmp:
        names = []
        for size in (16, 32, 64, 128, 256, 512, 1024):
            name = f"icon_{size}.png"
            draw_icon(size, rounded=True).save(os.path.join(tmp, name))
            names.append(name)
        iconset = os.path.join(tmp, "cubecraft.iconset")
        os.makedirs(iconset, exist_ok=True)
        for name in names:
            with open(os.path.join(tmp, name), "rb") as src:
                payload = src.read()
            with open(os.path.join(iconset, name), "wb") as dst:
                dst.write(payload)
        subprocess.run(
            ["iconutil", "-c", "icns", iconset, "-o", os.path.join(out_dir, "cubecraft.icns")],
            check=True,
        )


def write_ico(out_dir: str) -> None:
    base = draw_icon(256, rounded=False)
    base.save(
        os.path.join(out_dir, "cubecraft.ico"),
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
    )


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "icons")
    os.makedirs(out_dir, exist_ok=True)

    sizes = write_pngs(out_dir)
    write_icns(out_dir)
    write_ico(out_dir)

    for name in sorted(os.listdir(out_dir)):
        path = os.path.join(out_dir, name)
        print(f"  {name:34s} {os.path.getsize(path):>9,} octets")
    print(f"\n{len(sizes)} tailles de PNG, plus cubecraft.icns et cubecraft.ico")
    return 0


if __name__ == "__main__":
    sys.exit(main())
