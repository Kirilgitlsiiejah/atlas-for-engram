#!/usr/bin/env python3
"""Generate transparent-background PNG icons for the Obsidian Web Clipper rebrand.

Pipeline:
  1. Load source RGB image.
  2. Compute the figure's tight bounding box on the source. The source image
     ships with ~25% whitespace margin around the figure; without cropping, the
     figure occupies only ~50% of the canvas after resize and the 16x16 toolbar
     icon is visually indistinguishable next to other Chrome extension icons.
     We mark a pixel as "figure" using `min(R,G,B) < BBOX_THRESHOLD` where the
     threshold equals SOFT_LOW (the matte's "fully opaque" floor). Using
     SOFT_LOW (not SOFT_HIGH) avoids capturing JPEG-style compression noise
     in the matte transition band, which can otherwise scatter min=244 blots
     along the source edges and balloon the bbox back to the full canvas.
     We then add a small percentage padding (PAD_PCT) so anti-aliased
     outlines aren't clipped flush against the bbox edge.
  3. Crop the source to the padded bbox. The figure is taller than wide, so
     after cropping we square-pad with transparent margin on the sides; this
     prevents the LANCZOS resize from squashing the aspect ratio.
  4. Convert to RGBA and remove the near-white background using a soft
     threshold (linear ramp from `SOFT_LOW` -> `SOFT_HIGH` on the min RGB
     channel). Pixels brighter than `SOFT_HIGH` become fully transparent;
     pixels below `SOFT_LOW` stay fully opaque; pixels in between get a
     proportional alpha so anti-aliased outlines blend cleanly.
  5. Resize the cleaned RGBA master with LANCZOS to each target size.
  6. Verify dimensions, mode, corner alpha, and opaque-ratio for every output.

Reproducible: takes --source and --out-dir, falls back to sane defaults.
Idempotent: re-running overwrites the same three files. The source image is
read-only — all transformations happen in memory.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

# Defaults relative to the repo layout.
REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SOURCE = Path(
    r"C:\Users\David\Desktop\obsidian\ChatGPT Image 25 abr 2026, 11_25_10 p.m..png"
)
DEFAULT_OUT = REPO_ROOT / "assets" / "clipper" / "icons"

TARGET_SIZES = (16, 48, 128)

# Soft-threshold band for background removal.
# Pixels with min(R,G,B) >= SOFT_HIGH -> fully transparent.
# Pixels with min(R,G,B) <= SOFT_LOW  -> fully opaque.
# Between -> linear alpha ramp (preserves anti-aliased line edges).
SOFT_LOW = 200
SOFT_HIGH = 245

# Padding (percent of bbox dimension) added around the figure bbox before
# cropping, so anti-aliased edges aren't clipped flush against the border.
PAD_PCT = 0.05

# Threshold for bbox detection: a pixel counts as "figure" iff
# min(R,G,B) < BBOX_THRESHOLD. Set to SOFT_LOW so we ignore matte-transition
# pixels (alpha < 1) that are typically just AI-generated background noise
# scattered around the canvas edges. Real figure pixels have min << SOFT_LOW.
BBOX_THRESHOLD = SOFT_LOW


def compute_figure_bbox(img: Image.Image) -> tuple[int, int, int, int]:
    """Return (left, top, right, bottom) of the non-white figure on `img`.

    A pixel counts as "figure" when min(R,G,B) < BBOX_THRESHOLD. We use the
    stricter SOFT_LOW threshold (not SOFT_HIGH) so noise pixels scattered in
    the matte transition band don't expand the bbox to the full canvas.
    Bottom/right are exclusive (PIL crop convention).
    """
    rgb = img.convert("RGB")
    pixels = rgb.load()
    w, h = rgb.size

    min_x, min_y = w, h
    max_x, max_y = -1, -1

    for y in range(h):
        for x in range(w):
            r, g, b = pixels[x, y]
            if min(r, g, b) < BBOX_THRESHOLD:
                if x < min_x:
                    min_x = x
                if x > max_x:
                    max_x = x
                if y < min_y:
                    min_y = y
                if y > max_y:
                    max_y = y

    if max_x < 0 or max_y < 0:
        # No figure detected — fall back to the full image to avoid a crash.
        return (0, 0, w, h)

    # Convert max to exclusive (PIL crop convention).
    return (min_x, min_y, max_x + 1, max_y + 1)


def pad_and_clamp_bbox(
    bbox: tuple[int, int, int, int], img_size: tuple[int, int], pct: float
) -> tuple[int, int, int, int]:
    """Inflate `bbox` by `pct` of its width/height and clamp to image bounds."""
    left, top, right, bottom = bbox
    img_w, img_h = img_size
    bw = right - left
    bh = bottom - top
    pad_x = int(round(bw * pct))
    pad_y = int(round(bh * pct))
    return (
        max(0, left - pad_x),
        max(0, top - pad_y),
        min(img_w, right + pad_x),
        min(img_h, bottom + pad_y),
    )


def square_pad_rgba(img: Image.Image) -> Image.Image:
    """Pad an RGBA image with fully-transparent margin to a square canvas.

    The figure is taller than it is wide, so we add transparent bars on the
    left and right (or top and bottom, if it were wider). This keeps the
    figure's aspect ratio intact when LANCZOS-resized to a square target.
    """
    w, h = img.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    off_x = (side - w) // 2
    off_y = (side - h) // 2
    canvas.paste(img, (off_x, off_y))
    return canvas


def remove_white_background(img: Image.Image) -> Image.Image:
    """Return an RGBA copy of `img` with near-white pixels alpha-keyed out."""
    rgba = img.convert("RGBA")
    pixels = rgba.load()
    w, h = rgba.size
    span = SOFT_HIGH - SOFT_LOW
    for y in range(h):
        for x in range(w):
            r, g, b, _a = pixels[x, y]
            # Use the minimum channel: a pixel is "white-ish" only if
            # ALL channels are bright. Coloured strokes (purple, black)
            # have at least one low channel and are preserved.
            m = min(r, g, b)
            if m >= SOFT_HIGH:
                pixels[x, y] = (r, g, b, 0)
            elif m > SOFT_LOW:
                # Linear ramp: brighter -> more transparent.
                alpha = int(255 * (SOFT_HIGH - m) / span)
                pixels[x, y] = (r, g, b, alpha)
            # else: keep fully opaque
    return rgba


def resize_rgba(master: Image.Image, size: int) -> Image.Image:
    """High-quality LANCZOS resize that preserves the alpha channel."""
    return master.resize((size, size), Image.LANCZOS)


def opaque_ratio(img: Image.Image) -> float:
    """Fraction of pixels with alpha > 0. Smoke-test for 'figure fills canvas'."""
    px = img.load()
    w, h = img.size
    opaque = 0
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 0:
                opaque += 1
    return opaque / (w * h)


def verify(path: Path, expected_size: int) -> dict:
    """Open `path` and report dimensions, mode, corner alphas, opaque ratio."""
    out = Image.open(path)
    w, h = out.size
    mode = out.mode
    corners = {
        "tl": out.getpixel((0, 0))[3],
        "tr": out.getpixel((w - 1, 0))[3],
        "bl": out.getpixel((0, h - 1))[3],
        "br": out.getpixel((w - 1, h - 1))[3],
    }
    ratio = opaque_ratio(out)
    ok = (
        w == expected_size
        and h == expected_size
        and mode == "RGBA"
        and all(a == 0 for a in corners.values())
    )
    return {
        "path": str(path),
        "size": (w, h),
        "mode": mode,
        "corners_alpha": corners,
        "opaque_ratio": ratio,
        "ok": ok,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    p.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    args = p.parse_args(argv)

    if not args.source.exists():
        print(f"ERROR: source not found: {args.source}", file=sys.stderr)
        return 2

    args.out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[load]  {args.source}")
    src = Image.open(args.source)
    print(f"        size={src.size} mode={src.mode}")

    print(f"[bbox]  scanning for figure (min(R,G,B) < {BBOX_THRESHOLD})")
    raw_bbox = compute_figure_bbox(src)
    padded_bbox = pad_and_clamp_bbox(raw_bbox, src.size, PAD_PCT)
    rl, rt, rr, rb = raw_bbox
    pl, pt, pr, pb = padded_bbox
    print(f"        raw bbox    = x:{rl}..{rr} y:{rt}..{rb} "
          f"({rr - rl}x{rb - rt})")
    print(f"        padded bbox = x:{pl}..{pr} y:{pt}..{pb} "
          f"({pr - pl}x{pb - pt}) [+{int(PAD_PCT*100)}%]")

    cropped = src.crop(padded_bbox)

    print(f"[matte] soft threshold {SOFT_LOW}..{SOFT_HIGH}")
    matted = remove_white_background(cropped)

    print("[square] pad to 1:1 canvas with transparent margin")
    master = square_pad_rgba(matted)
    print(f"        master size={master.size} mode={master.mode}")

    # Quick master sanity: corners should be alpha=0.
    mc = [master.getpixel((0, 0))[3],
          master.getpixel((master.size[0] - 1, master.size[1] - 1))[3]]
    print(f"        master corner alphas: {mc}")

    reports = []
    for size in TARGET_SIZES:
        out_path = args.out_dir / f"icon{size}.png"
        resized = resize_rgba(master, size)
        resized.save(out_path, format="PNG", optimize=True)
        report = verify(out_path, size)
        reports.append(report)
        flag = "OK" if report["ok"] else "FAIL"
        print(f"[{flag}]    {out_path.name} -> {report['size']} {report['mode']} "
              f"opaque={report['opaque_ratio']*100:.1f}% "
              f"corners={report['corners_alpha']}")

    failed = [r for r in reports if not r["ok"]]
    if failed:
        print(f"\n{len(failed)} file(s) failed verification", file=sys.stderr)
        return 1
    print("\nAll icons generated and verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
