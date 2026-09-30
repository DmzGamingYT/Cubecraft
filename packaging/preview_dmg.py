#!/usr/bin/env python3
"""Compose l'apercu du volume `.dmg`, pour relire le rendu a l'oeil.

Le fond, la fleche et le texte sont produits par `make_dmg.py` ; ce script
ajoute par-dessus les deux icones, exactement la ou create-dmg les placera,
puis encode le tout en base64 dans une page HTML autonome. L'apercu doit
marcher sans serveur ni chemin relatif : une image cassee ne dit rien du
rendu reel.

Usage :  python3 packaging/preview_dmg.py [dossier build/macos]
"""

from __future__ import annotations

import base64
import io
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_dmg import APP_CENTER, ICON_SIZE, LINK_CENTER, WINDOW  # noqa: E402


def applications_icon(size: int) -> Image.Image:
    """Dossier bleu avec une fleche blanche, comme celui de macOS."""
    scale = 8
    big = size * scale
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    top, bottom = (143, 208, 245), (168, 220, 248)
    body = (74, 159, 216)
    draw.rounded_rectangle(
        (big * 0.06, big * 0.26, big * 0.94, big * 0.80), radius=big * 0.06, fill=body
    )
    draw.rounded_rectangle(
        (big * 0.06, big * 0.26, big * 0.94, big * 0.52), radius=big * 0.06, fill=top
    )
    draw.rectangle((big * 0.06, big * 0.40, big * 0.94, big * 0.52), fill=top)
    # Languette du dossier.
    draw.rounded_rectangle(
        (big * 0.06, big * 0.18, big * 0.44, big * 0.30), radius=big * 0.03, fill=bottom
    )
    # Fleche vers le bas, centree.
    cx = big / 2
    draw.polygon(
        (
            (cx, big * 0.72),
            (cx - big * 0.11, big * 0.58),
            (cx + big * 0.11, big * 0.58),
        ),
        fill=(255, 255, 255, 235),
    )
    return image.resize((size, size), Image.LANCZOS)


def compose(build_dir: str) -> Image.Image:
    background = Image.open(os.path.join(build_dir, "dmg-background.png")).convert("RGBA")
    background = background.resize(WINDOW, Image.LANCZOS)

    icons = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "icons")
    app_icon = Image.open(os.path.join(icons, "cubecraft-rounded-128.png")).convert("RGBA")
    app_icon = app_icon.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
    apps_icon = applications_icon(int(ICON_SIZE * 0.82))

    for image, center in ((app_icon, APP_CENTER), (apps_icon, LINK_CENTER)):
        x = int(center[0] - image.width / 2)
        y = int(center[1] - image.height / 2)
        background.alpha_composite(image, (x, y))

    return background


def main(argv: list[str]) -> int:
    build_dir = argv[1] if len(argv) > 1 else "build/macos"
    out_html = argv[2] if len(argv) > 2 else os.path.join(build_dir, "preview.html")

    composed = compose(build_dir)
    buffer = io.BytesIO()
    composed.convert("RGB").save(buffer, format="PNG")
    payload = base64.b64encode(buffer.getvalue()).decode()

    html = f"""<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<title>Apercu Cubecraft.dmg</title>
<style>
 body {{ margin:0; background:#1b2733; color:#8fb8d8; display:flex; flex-direction:column;
        align-items:center; justify-content:center; height:100vh; margin:0;
        font-family:-apple-system,system-ui,sans-serif; }}
 h1 {{ font-size:15px; font-weight:600; margin:0 0 18px; letter-spacing:.3px; }}
 img {{ width:660px; height:400px; border-radius:6px; border:1px solid rgba(255,255,255,.16);
        box-shadow:0 22px 60px rgba(0,0,0,.55); }}
 p {{ color:#6f8ba3; font-size:12px; margin:20px 0 0; }}
</style></head>
<body>
<h1>Apercu du volume Cubecraft.dmg (660 x 400)</h1>
<img src="data:image/png;base64,{payload}" alt="Apercu du dmg">
<p>Fond, fleche, icones et positions : exactement ce qu'inscrit create-dmg dans le .dmg.</p>
</body></html>
"""
    with open(out_html, "w", encoding="utf-8") as handle:
        handle.write(html)
    print(f"  {out_html}  {os.path.getsize(out_html):,} octets")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
