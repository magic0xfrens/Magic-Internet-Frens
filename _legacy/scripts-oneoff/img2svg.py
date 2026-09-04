#!/usr/bin/env python3
"""
Convert a pixel-art PNG to a 120x120 SVG rect format matching MiFrens collection.
Uses LANCZOS downscaling + curated palette snapping for clean pixel art output.
"""

import argparse
import math
from PIL import Image, ImageEnhance, ImageFilter
import numpy as np
from collections import Counter


# Hand-tuned palette for the Elf character, derived from dominant color analysis
# Each color serves a specific role in the character design
ELF_PALETTE = [
    # Dark outlines / black
    (10, 10, 4),       # near-black (outlines)
    (20, 40, 14),      # very dark green (hat outline, shadows)

    # Hat greens (4 shades: dark → light)
    (30, 55, 30),      # dark hat green (shadow)
    (50, 85, 50),      # mid hat green (main)
    (65, 110, 50),     # bright hat green (highlight)
    (90, 140, 60),     # light hat green (top highlight)

    # Skin greens (4 shades)
    (35, 65, 20),      # dark skin (shadow / outline)
    (70, 130, 45),     # mid skin green (main face)
    (95, 140, 55),     # bright skin (highlight)
    (110, 160, 80),    # very light skin (forehead highlight)

    # Vine / plant greens
    (55, 80, 35),      # dark vine
    (75, 105, 50),     # mid vine

    # Blue tunic (4 shades)
    (10, 70, 100),     # dark blue (deep shadow)
    (20, 100, 145),    # mid-dark blue (fold shadow)
    (50, 130, 180),    # main blue (tunic)
    (75, 155, 200),    # light blue (highlight)

    # Orange/red lips (2 shades)
    (160, 50, 10),     # dark orange/red
    (210, 100, 20),    # bright orange

    # Brown boots (3 shades)
    (25, 15, 8),       # very dark brown
    (65, 40, 22),      # mid brown
    (100, 65, 35),     # light brown

    # Gold sparkle / earring
    (200, 180, 50),    # gold
    (230, 210, 90),    # bright gold

    # Gray / white (eyes, highlights)
    (170, 170, 170),   # light gray
    (230, 230, 230),   # near-white (eye whites)
]


def color_distance_lab_approx(c1, c2):
    """
    Weighted RGB distance that better matches perceptual difference.
    Human eyes are more sensitive to green, less to blue.
    """
    dr = c1[0] - c2[0]
    dg = c1[1] - c2[1]
    db = c1[2] - c2[2]
    rmean = (c1[0] + c2[0]) / 2
    return math.sqrt(
        (2 + rmean / 256) * dr * dr +
        4 * dg * dg +
        (2 + (255 - rmean) / 256) * db * db
    )


def snap_to_palette(r, g, b, palette):
    """Find the nearest color in the palette using perceptual distance."""
    best = None
    best_dist = float('inf')
    for pr, pg, pb in palette:
        d = color_distance_lab_approx((r, g, b), (pr, pg, pb))
        if d < best_dist:
            best_dist = d
            best = (pr, pg, pb)
    return best


def is_background(r, g, b, a, threshold=230):
    if a < 40:
        return True
    if r > threshold and g > threshold and b > threshold:
        return True
    return False


def main():
    parser = argparse.ArgumentParser(description='Convert pixel art PNG to MiFrens SVG')
    parser.add_argument('input', help='Input PNG file')
    parser.add_argument('output', help='Output SVG file')
    parser.add_argument('--target-height', type=int, default=74)
    parser.add_argument('--offset-x', type=int, default=None)
    parser.add_argument('--offset-y', type=int, default=22)
    parser.add_argument('--sharpen', type=float, default=1.3, help='Sharpness factor (default 1.3)')
    parser.add_argument('--contrast', type=float, default=1.15, help='Contrast factor (default 1.15)')
    args = parser.parse_args()

    img = Image.open(args.input).convert('RGBA')
    print(f"Input: {img.size[0]}x{img.size[1]}")

    # Split into RGB and Alpha
    rgb = img.convert('RGB')
    alpha = np.array(img)[:, :, 3]

    # Find bounding box of non-white, non-transparent pixels
    arr = np.array(img)
    mask = (alpha > 40) & np.any(arr[:, :, :3] < 230, axis=2)
    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    print(f"Character bbox: ({cmin},{rmin}) to ({cmax},{rmax})")

    # Crop
    cropped_rgba = img.crop((cmin, rmin, cmax + 1, rmax + 1))
    cropped_rgb = cropped_rgba.convert('RGB')
    cw, ch = cropped_rgba.size
    print(f"Cropped: {cw}x{ch}")

    # Enhance before downscaling
    enhancer = ImageEnhance.Contrast(cropped_rgb)
    cropped_rgb = enhancer.enhance(args.contrast)
    enhancer = ImageEnhance.Sharpness(cropped_rgb)
    cropped_rgb = enhancer.enhance(args.sharpen)

    # Scale with LANCZOS (high quality anti-aliased downscale)
    scale = args.target_height / ch
    new_w = max(1, round(cw * scale))
    new_h = args.target_height

    scaled_rgb = cropped_rgb.resize((new_w, new_h), Image.LANCZOS)
    # Scale alpha separately with LANCZOS
    cropped_alpha = cropped_rgba.split()[3]
    scaled_alpha = cropped_alpha.resize((new_w, new_h), Image.LANCZOS)

    print(f"Scaled: {new_w}x{new_h} (scale={scale:.3f})")

    # Compute canvas offset
    if args.offset_x is not None:
        ox = args.offset_x
    else:
        ox = (120 - new_w) // 2
    oy = args.offset_y
    print(f"Canvas offset: ({ox}, {oy})")

    # Generate rects with palette snapping
    rgb_pixels = scaled_rgb.load()
    alpha_pixels = scaled_alpha.load()
    palette = ELF_PALETTE

    rects = []
    color_counts = {}

    for y in range(new_h):
        for x in range(new_w):
            r, g, b = rgb_pixels[x, y]
            a = alpha_pixels[x, y]

            if is_background(r, g, b, a):
                continue

            # Snap to curated palette
            pr, pg, pb = snap_to_palette(r, g, b, palette)
            color = f"#{pr:02X}{pg:02X}{pb:02X}"

            sx = ox + x
            sy = oy + y

            if 0 <= sx < 120 and 0 <= sy < 120:
                rects.append((sy, sx, color))
                color_counts[color] = color_counts.get(color, 0) + 1

    rects.sort()
    print(f"Total rects: {len(rects)}, Unique colors: {len(color_counts)}")

    # Write SVG
    with open(args.output, 'w') as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" shape-rendering="crispEdges">\n')
        for sy, sx, color in rects:
            f.write(f'<rect x="{sx}" y="{sy}" width="1" height="1" fill="{color}"/>\n')
        f.write('</svg>\n')

    print(f"Written to {args.output}")

    sorted_colors = sorted(color_counts.items(), key=lambda x: -x[1])
    print("\nPalette usage:")
    for color, count in sorted_colors:
        print(f"  {color}: {count}px")


if __name__ == '__main__':
    main()
