#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10", "numpy>=1.24"]
# ///
"""fal-made art for the Portal Guns mod, layered on top of the procedural art from gen_assets.py.

Two steps:

    FAL_KEY=... uv run tools/gen_fal_assets.py generate [gun tech scorch ground]   # calls fal, needs a key
    uv run tools/gen_fal_assets.py build                                          # offline, no key

`generate` runs universal-modder's `um fal` CLI (`UM=/path/to/universal-modder/bin/um`, or `um` on PATH), keeps
the raw outputs in assets/fal/ (512 px, committed) and appends every call to docs/fal_manifest.jsonl. The key
is read by `um` from FAL_KEY or FAL_KEY_FILE; this script never sees or prints it.

`build` turns the raws into the files the prototypes load (same names and sizes as the procedural ones):
  - graphics/icons/portal-gun.png        64x64   the fal gun
  - graphics/technology/portal-gun.png  256x256  the fal gun between two portals
  - thumbnail.png                       144x144  the technology art on the fal ground texture (opaque)
  - graphics/entity/portal/portal-*-body.png    the procedural swirl over a fal scorch mark (same 4x4 x 192 px)
  - graphics/icons/portal-{blue,orange}.png     64x64 flattened first frame
A missing raw skips its outputs, so without assets/fal/ the procedural art stays as it is. The swirl itself
stays procedural: only maths loops seamlessly over 16 frames.

`preview` writes docs/media/fal-vs-procedural.png (both sets on grass) for review.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_assets as ga  # noqa: E402

ROOT = ga.ROOT
RAW = ROOT / "assets" / "fal"
MANIFEST = ROOT / "docs" / "fal_manifest.jsonl"
RAW_SIZE = 512

# Factorio's icons are small renders, not drawings: muted worn metals, soft light from the top left, a mild
# three-quarter view from above, a dark contour that keeps the silhouette readable at 32 px.
ICON_STYLE = ("in the style of a Factorio game item icon: a semi-realistic 3D-rendered object, muted industrial "
              "palette of worn gunmetal grey, dull steel, dark rubber and a little tarnished brass, soft key light "
              "from the top left with gentle ambient occlusion, slightly desaturated, a thin dark contour around "
              "the silhouette, mild three-quarter view from above, readable at 32 pixels, transparent background")

GUN = ("A handheld sci-fi portal device, seen from the side in a diagonal pose with the muzzle pointing to the "
       "upper right: a chunky boxy steel body with bolted panels and a few scratches, a short pistol grip wrapped "
       "in dark rubber, a thick cable loop along the underside, a stubby barrel ending in three angled metal "
       "prongs that hold a small glowing white-blue energy core, a narrow glass window on the side with a faint "
       "blue glow. " + ICON_STYLE)

TECH = ("Factorio technology icon: a handheld sci-fi portal device in the middle, muzzle pointing to the upper "
        "right, with a swirling blue energy portal ring behind it at the lower left and a swirling orange energy "
        "portal ring behind it at the upper right. The device: chunky boxy worn steel body with bolted panels, "
        "dark rubber pistol grip, three angled metal prongs around a small glowing core at the muzzle. "
        + ICON_STYLE + ", the portals glow but the metal stays muted")

SCORCH = ("Top-down orthographic view straight down onto the ground: a circular scorch mark burnt into dirt, a "
          "ring of charred black and dark brown earth with fine radial cracks and a few small scattered pebbles, "
          "darkest in a band around the middle, fading softly into transparency at the outer edge, the centre of "
          "the ring is plain dark soot. In the style of Factorio terrain decals: muted earthy colours, painterly "
          "realistic, soft even daylight from the top left. Perfectly round and centred, nothing else, "
          "transparent background, no text")

GROUND = ("Factorio style grass terrain seen straight from above: short dry olive-green grass with darker patches "
          "and a few tiny pebbles, muted natural colours, soft even daylight, no objects, no paths")

JOBS = {
    "gun": ["sprite", GUN, "--quality", "high", "--size", "square_hd"],
    "tech": ["sprite", TECH, "--quality", "high", "--size", "square_hd"],
    "scorch": ["sprite", SCORCH, "--quality", "high", "--size", "square_hd"],
    "ground": ["texture", GROUND, "--size", "square_hd"],
}


# --------------------------------------------------------------------------------------------- generate

def um_cmd() -> list[str]:
    um = os.environ.get("UM") or shutil.which("um")
    if not um:
        sys.exit("generate needs universal-modder's CLI: clone https://github.com/rehan-remade/universal-modder "
                 "and set UM=<clone>/bin/um (or put um on PATH)")
    return [um]


def generate(names: list[str]) -> None:
    if not (os.environ.get("FAL_KEY") or os.environ.get("FAL_KEY_FILE")):
        sys.exit("generate needs FAL_KEY (or FAL_KEY_FILE pointing at a file that holds it)")
    RAW.mkdir(parents=True, exist_ok=True)
    for name in names:
        recipe, prompt, *opts = JOBS[name]
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(um_cmd() + ["fal", recipe, prompt, "--out", tmp, "--name", name, *opts], check=True)
            pngs = sorted(Path(tmp).glob(f"{name}*.png"))
            if not pngs:
                sys.exit(f"{name}: fal returned no PNG")
            img = Image.open(pngs[0]).convert("RGBA")
            img.resize((RAW_SIZE, RAW_SIZE), Image.LANCZOS).save(RAW / f"{name}.png", optimize=True)
            with open(Path(tmp) / "fal_manifest.jsonl") as f, open(MANIFEST, "a") as m:
                for line in f:
                    rec = json.loads(line)
                    rec["files"] = [f"assets/fal/{name}.png"]
                    rec["raw_size"] = f"{img.size[0]}x{img.size[1]} (kept at {RAW_SIZE}x{RAW_SIZE})"
                    m.write(json.dumps(rec) + "\n")
        print(f"  assets/fal/{name}.png")


# --------------------------------------------------------------------------------------------- build helpers

def raw(name: str) -> Image.Image | None:
    p = RAW / f"{name}.png"
    return Image.open(p).convert("RGBA") if p.exists() else None


def trim(img: Image.Image, threshold: int = 10) -> Image.Image:
    box = img.getchannel("A").point(lambda a: 255 if a > threshold else 0).getbbox()
    return img.crop(box) if box else img


def fit_square(img: Image.Image, size: int, margin: float = 0.03) -> Image.Image:
    """Trim to the drawing, centre it on a square with a small margin, scale down in one LANCZOS step."""
    img = trim(img)
    side = int(max(img.size) * (1 + 2 * margin))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.alpha_composite(img, ((side - img.size[0]) // 2, (side - img.size[1]) // 2))
    out = sq.resize((size, size), Image.LANCZOS)
    if size <= 64:   # small icons lose their contour when downscaled; a light unsharp brings it back
        out = out.filter(ImageFilter.UnsharpMask(radius=0.8, percent=60, threshold=2))
    return out


def scorch_decal(size: int = ga.PORTAL_SIZE) -> Image.Image | None:
    """The fal scorch mark, centred on its alpha centroid, scaled so it reaches ~1.4x the portal radius and
    faded to nothing before the frame edge (frames are 192 px, the portal rim sits at 64 px)."""
    img = raw("scorch")
    if img is None:
        return None
    a = np.asarray(img, dtype=np.float64)[..., 3]
    ys, xs = np.nonzero(a > 24)
    w = a[ys, xs]
    cx, cy = (xs * w).sum() / w.sum(), (ys * w).sum() / w.sum()
    # radius that holds 97 % of the alpha mass = the visible extent of the mark
    d = np.hypot(xs - cx, ys - cy)
    order = np.argsort(d)
    extent = d[order][np.searchsorted(np.cumsum(w[order]) / w.sum(), 0.97)]
    target = ga.PORTAL_RADIUS * 1.42
    k = target / extent
    big = img.resize((round(img.size[0] * k), round(img.size[1] * k)), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(big, (round(size / 2 - cx * k), round(size / 2 - cy * k)))
    # force a clean round falloff so nothing is cut by the frame border, and tone the mark down to sit under
    # the swirl like a vanilla decal (they are subtle)
    dx, dy = ga.grid(size)
    r = np.hypot(dx, dy)
    fade = np.clip((size / 2 - 2 - r) / (size / 2 - 2 - target * 0.9), 0, 1) ** 1.5
    arr = np.asarray(out, dtype=np.float64)
    arr[..., 3] *= fade * 0.9
    return Image.fromarray(np.round(arr).astype(np.uint8), "RGBA")


def portal_frames(color: str, decal: Image.Image | None) -> list[tuple[Image.Image, Image.Image]]:
    frames = []
    for f in range(ga.PORTAL_FRAMES):
        body, glow = ga.portal_frame(color, f)
        if decal is not None:
            body = ga.over(body, decal)
        frames.append((body, glow))
    return frames


def portal_icon(color: str, size: int, decal: Image.Image | None, crop: int = 170) -> Image.Image:
    body, glow = portal_frames(color, decal)[0] if decal is not None else ga.portal_frame(color, 0)
    flat = ga.add_glow(glow, body)
    m = (ga.PORTAL_SIZE - crop) // 2
    return flat.crop((m, m, ga.PORTAL_SIZE - m, ga.PORTAL_SIZE - m)).resize((size, size), Image.LANCZOS)


def tech_art(gun: Image.Image) -> Image.Image:
    """Fallback technology art when there is no fal tech raw: the fal gun between two procedural portals."""
    tech = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    tech.alpha_composite(ga.portal_icon("blue", 132), (4, 118))
    tech.alpha_composite(ga.portal_icon("orange", 132), (120, 6))
    tech.alpha_composite(fit_square(gun, 220), (18, 22))
    return tech


def ground_tile(size: int) -> Image.Image | None:
    g = raw("ground")
    if g is None:
        return None
    return g.convert("RGB").resize((size, size), Image.LANCZOS)


def thumbnail(tech: Image.Image) -> Image.Image:
    size = 144
    ground = ground_tile(size)
    if ground is None:
        bg = Image.new("RGB", (size, size), (40, 44, 30))
    else:   # darken towards the corners so the art reads (vanilla thumbnails are calm, low-contrast)
        dx, dy = ga.grid(size)
        vign = 0.62 - 0.22 * np.clip(np.hypot(dx, dy) / (size * 0.7), 0, 1)
        bg = Image.fromarray(np.round(np.asarray(ground, dtype=np.float64) * vign[..., None]).astype(np.uint8))
    out = bg.convert("RGBA")
    out.alpha_composite(tech.resize((136, 136), Image.LANCZOS), (4, 4))
    return out.convert("RGB")


# --------------------------------------------------------------------------------------------- build

def build() -> None:
    if not RAW.exists():
        print("  no assets/fal/: keeping the procedural art")
        return
    gun, tech_raw = raw("gun"), raw("tech")
    if gun is not None:
        ga.save(fit_square(gun, 64), ga.GFX / "icons/portal-gun.png")
    tech = fit_square(tech_raw, 256, margin=0.01) if tech_raw is not None else tech_art(gun) if gun is not None else None
    if tech is not None:
        ga.save(tech, ga.GFX / "technology/portal-gun.png")
        ga.save(thumbnail(tech), ga.MOD / "thumbnail.png")
    decal = scorch_decal()
    if decal is not None:
        for color in ("blue", "orange"):
            frames = portal_frames(color, decal)
            ga.save(ga.sheet([b for b, _ in frames], 4), ga.GFX / "entity/portal" / f"portal-{color}-body.png")
            ga.save(ga.sheet([g for _, g in frames], 4), ga.GFX / "entity/portal" / f"portal-{color}-glow.png")
            ga.save(portal_icon(color, 64, decal), ga.GFX / "icons" / f"portal-{color}.png")


# --------------------------------------------------------------------------------------------- preview

def preview() -> None:
    """Procedural (top row) vs fal (bottom row) on grass: gun icon, portal icons, technology, thumbnail, and a
    portal frame at the game's scale 0.5 (32 px per tile) and at full sheet resolution."""
    proc_gun = ga.draw_gun(64)
    proc_tech = ga.tech_icon()
    proc_thumb = ga.thumbnail()
    decal = scorch_decal()
    rows = [
        ("procedural", proc_gun, ga.portal_icon("blue", 64), ga.portal_icon("orange", 64), proc_tech, proc_thumb,
         [ga.portal_frame(c, 0) for c in ("blue", "orange")]),
        ("fal", Image.open(ga.GFX / "icons/portal-gun.png").convert("RGBA"),
         Image.open(ga.GFX / "icons/portal-blue.png").convert("RGBA"),
         Image.open(ga.GFX / "icons/portal-orange.png").convert("RGBA"),
         Image.open(ga.GFX / "technology/portal-gun.png").convert("RGBA"),
         Image.open(ga.MOD / "thumbnail.png").convert("RGBA"),
         [portal_frames(c, decal)[0] for c in ("blue", "orange")]),
    ]
    pad = 16
    width = pad + 3 * (64 + pad) + 256 + pad + 144 + pad + 2 * (96 + pad) + 2 * (192 + pad)
    row_h = 256 + 2 * pad
    w, h = width, row_h * len(rows)
    ground = ground_tile(256)
    if ground is None:
        canvas = Image.new("RGBA", (w, h), (78, 84, 44, 255))
    else:
        canvas = Image.new("RGBA", (w, h))
        for y in range(0, h, 256):
            for x in range(0, w, 256):
                canvas.paste(ground.convert("RGBA"), (x, y))
    for i, (_, g, pb, po, tech, thumb, frames) in enumerate(rows):
        y0 = i * row_h + pad
        x = pad
        for icon in (g, pb, po):
            canvas.alpha_composite(icon, (x, y0 + 96))
            x += 64 + pad
        canvas.alpha_composite(tech, (x, y0))
        x += 256 + pad
        canvas.alpha_composite(thumb, (x, y0 + 56))
        x += 144 + pad
        for body, glow in frames:              # scale 0.5: what the game draws at zoom 1
            layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            layer.alpha_composite(body.resize((96, 96), Image.LANCZOS), (x, y0 + 80))
            glayer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            glayer.alpha_composite(glow.resize((96, 96), Image.LANCZOS), (x, y0 + 80))
            canvas = ga.add_glow(glayer, ga.over(layer, canvas))
            x += 96 + pad
        for body, glow in frames:              # full sheet resolution (zoomed in 2x in game)
            layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            layer.alpha_composite(body, (x, y0 + 32))
            glayer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            glayer.alpha_composite(glow, (x, y0 + 32))
            canvas = ga.add_glow(glayer, ga.over(layer, canvas))
            x += 192 + pad
    ga.save(canvas.convert("RGB"), ROOT / "docs/media/fal-vs-procedural.png")


if __name__ == "__main__":
    step, *rest = sys.argv[1:] or ["build"]
    if step == "generate":
        generate(rest or list(JOBS))
    elif step == "build":
        build()
    elif step == "preview":
        preview()
    else:
        sys.exit(__doc__)
