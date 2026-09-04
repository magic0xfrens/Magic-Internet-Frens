#!/usr/bin/env python3
"""
Extract ALL unique colors from elf SVG files.
Checks: fill=, stroke=, style=, stop-color=, color=, inline CSS, hex, rgb, rgba, named colors.
Groups similar colors (RGB distance <= 15).
"""

import os
import re
import glob
import math
from collections import defaultdict, Counter

NAMED_COLORS = {
    "aliceblue": (240,248,255), "antiquewhite": (250,235,215), "aqua": (0,255,255),
    "aquamarine": (127,255,212), "azure": (240,255,255), "beige": (245,245,220),
    "bisque": (255,228,196), "black": (0,0,0), "blanchedalmond": (255,235,205),
    "blue": (0,0,255), "blueviolet": (138,43,226), "brown": (165,42,42),
    "burlywood": (222,184,135), "cadetblue": (95,158,160), "chartreuse": (127,255,0),
    "chocolate": (210,105,30), "coral": (255,127,80), "cornflowerblue": (100,149,237),
    "cornsilk": (255,248,220), "crimson": (220,20,60), "cyan": (0,255,255),
    "darkblue": (0,0,139), "darkcyan": (0,139,139), "darkgoldenrod": (184,134,11),
    "darkgray": (169,169,169), "darkgreen": (0,100,0), "darkgrey": (169,169,169),
    "darkkhaki": (189,183,107), "darkmagenta": (139,0,139), "darkolivegreen": (85,107,47),
    "darkorange": (255,140,0), "darkorchid": (153,50,204), "darkred": (139,0,0),
    "darksalmon": (233,150,122), "darkseagreen": (143,188,143), "darkslateblue": (72,61,139),
    "darkslategray": (47,79,79), "darkslategrey": (47,79,79), "darkturquoise": (0,206,209),
    "darkviolet": (148,0,211), "deeppink": (255,20,147), "deepskyblue": (0,191,255),
    "dimgray": (105,105,105), "dimgrey": (105,105,105), "dodgerblue": (30,144,255),
    "firebrick": (178,34,34), "floralwhite": (255,250,240), "forestgreen": (34,139,34),
    "fuchsia": (255,0,255), "gainsboro": (220,220,220), "ghostwhite": (248,248,255),
    "gold": (255,215,0), "goldenrod": (218,165,32), "gray": (128,128,128),
    "green": (0,128,0), "greenyellow": (173,255,47), "grey": (128,128,128),
    "honeydew": (240,255,240), "hotpink": (255,105,180), "indianred": (205,92,92),
    "indigo": (75,0,130), "ivory": (255,255,240), "khaki": (240,230,140),
    "lavender": (230,230,250), "lavenderblush": (255,240,245), "lawngreen": (124,252,0),
    "lemonchiffon": (255,250,205), "lightblue": (173,216,230), "lightcoral": (240,128,128),
    "lightcyan": (224,255,255), "lightgoldenrodyellow": (250,250,210),
    "lightgray": (211,211,211), "lightgreen": (144,238,144), "lightgrey": (211,211,211),
    "lightpink": (255,182,193), "lightsalmon": (255,160,122), "lightseagreen": (32,178,170),
    "lightskyblue": (135,206,250), "lightslategray": (119,136,153),
    "lightslategrey": (119,136,153), "lightsteelblue": (176,196,222),
    "lightyellow": (255,255,224), "lime": (0,255,0), "limegreen": (50,205,50),
    "linen": (250,240,230), "magenta": (255,0,255), "maroon": (128,0,0),
    "mediumaquamarine": (102,205,170), "mediumblue": (0,0,205),
    "mediumorchid": (186,85,211), "mediumpurple": (147,111,219),
    "mediumseagreen": (60,179,113), "mediumslateblue": (123,104,238),
    "mediumspringgreen": (0,250,154), "mediumturquoise": (72,209,204),
    "mediumvioletred": (199,21,133), "midnightblue": (25,25,112),
    "mintcream": (245,255,250), "mistyrose": (255,228,225), "moccasin": (255,228,181),
    "navajowhite": (255,222,173), "navy": (0,0,128), "oldlace": (253,245,230),
    "olive": (128,128,0), "olivedrab": (107,142,35), "orange": (255,165,0),
    "orangered": (255,69,0), "orchid": (218,112,214), "palegoldenrod": (238,232,170),
    "palegreen": (152,251,152), "paleturquoise": (175,238,238),
    "palevioletred": (219,112,147), "papayawhip": (255,239,213), "peachpuff": (255,218,185),
    "peru": (205,133,63), "pink": (255,192,203), "plum": (221,160,221),
    "powderblue": (176,224,230), "purple": (128,0,128), "rebeccapurple": (102,51,153),
    "red": (255,0,0), "rosybrown": (188,143,143), "royalblue": (65,105,225),
    "saddlebrown": (139,69,19), "salmon": (250,128,114), "sandybrown": (244,164,96),
    "seagreen": (46,139,87), "seashell": (255,245,238), "sienna": (160,82,45),
    "silver": (192,192,192), "skyblue": (135,206,235), "slateblue": (106,90,205),
    "slategray": (112,128,144), "slategrey": (112,128,144), "snow": (255,250,250),
    "springgreen": (0,255,127), "steelblue": (70,130,180), "tan": (210,180,140),
    "teal": (0,128,128), "thistle": (216,191,216), "tomato": (255,99,71),
    "turquoise": (64,224,208), "violet": (238,130,238), "wheat": (245,222,179),
    "white": (255,255,255), "whitesmoke": (245,245,245), "yellow": (255,255,0),
    "yellowgreen": (154,205,50),
}

SKIP_KEYWORDS = {"none", "transparent", "inherit", "currentcolor", "url"}


def hex_to_rgb(hex_color):
    h = hex_color.lstrip('#')
    if len(h) == 3:
        h = h[0]*2 + h[1]*2 + h[2]*2
    if len(h) == 6:
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    if len(h) == 8:
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    return None


def rgb_distance(c1, c2):
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(c1, c2)))


def normalize_color(color_str):
    color_str = color_str.strip().strip(';').strip('"').strip("'").strip()
    if not color_str:
        return None

    lower = color_str.lower()
    for skip in SKIP_KEYWORDS:
        if lower.startswith(skip):
            return None

    # Hex color
    hex_match = re.match(r'^#([0-9a-fA-F]{3,8})$', color_str)
    if hex_match:
        rgb = hex_to_rgb(color_str)
        if rgb:
            canonical = '#{:02X}{:02X}{:02X}'.format(*rgb)
            return (canonical, rgb)

    # rgb()/rgba()
    rgb_match = re.match(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)', color_str)
    if rgb_match:
        rgb = (int(rgb_match.group(1)), int(rgb_match.group(2)), int(rgb_match.group(3)))
        canonical = '#{:02X}{:02X}{:02X}'.format(*rgb)
        return (canonical, rgb)

    # Named color
    if lower in NAMED_COLORS:
        rgb = NAMED_COLORS[lower]
        canonical = '#{:02X}{:02X}{:02X}'.format(*rgb)
        return (canonical + f' ({lower})', rgb)

    return None


def extract_colors_from_svg(filepath):
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    colors = []

    # Attribute-based colors (double-quoted)
    attr_pattern = re.compile(
        r'(?:fill|stroke|stop-color|color|flood-color|lighting-color)\s*=\s*"([^"]*)"',
        re.IGNORECASE
    )
    for match in attr_pattern.finditer(content):
        val = match.group(1).strip()
        if val and not val.startswith('url('):
            colors.append(val)

    # Single-quoted attribute colors
    attr_pattern_sq = re.compile(
        r"(?:fill|stroke|stop-color|color|flood-color|lighting-color)\s*=\s*'([^']*)'",
        re.IGNORECASE
    )
    for match in attr_pattern_sq.finditer(content):
        val = match.group(1).strip()
        if val and not val.startswith('url('):
            colors.append(val)

    # CSS style properties (inside style="..." or <style> blocks)
    style_pattern = re.compile(
        r'(?:fill|stroke|stop-color|color|background-color|background|border-color|flood-color|lighting-color)\s*:\s*([^;}"\']+)',
        re.IGNORECASE
    )
    for match in style_pattern.finditer(content):
        val = match.group(1).strip()
        if val and not val.startswith('url('):
            colors.append(val)

    # Standalone hex colors (catch-all for anything missed)
    hex_standalone = re.compile(r'#([0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?)\b')
    for match in hex_standalone.finditer(content):
        colors.append('#' + match.group(1))

    return colors


def group_similar_colors(color_data, threshold=15):
    sorted_colors = sorted(color_data, key=lambda x: -x[2])
    groups = []
    used = set()

    for i, (canon_i, rgb_i, count_i) in enumerate(sorted_colors):
        if i in used:
            continue
        group = [(canon_i, rgb_i, count_i)]
        used.add(i)
        for j, (canon_j, rgb_j, count_j) in enumerate(sorted_colors):
            if j in used:
                continue
            if rgb_distance(rgb_i, rgb_j) <= threshold:
                group.append((canon_j, rgb_j, count_j))
                used.add(j)
        groups.append(group)

    return groups


def main():
    svg_dir = "/Users/0x0010110/Documents/GitHub/MagicFrens/public/frens/"
    svg_files = sorted(glob.glob(os.path.join(svg_dir, "elf*.svg")))

    if not svg_files:
        print("No elf*.svg files found!")
        return

    print(f"Found {len(svg_files)} elf SVG files\n")
    print("=" * 80)

    global_colors = Counter()
    color_rgb = {}
    per_file = {}
    original_forms = defaultdict(set)

    for filepath in svg_files:
        filename = os.path.basename(filepath)
        raw_colors = extract_colors_from_svg(filepath)
        file_colors = Counter()

        for raw in raw_colors:
            result = normalize_color(raw)
            if result:
                canonical, rgb = result
                file_colors[canonical] += 1
                global_colors[canonical] += 1
                color_rgb[canonical] = rgb
                original_forms[canonical].add(raw.strip())

        per_file[filename] = file_colors

    # --- Report ---
    print("\nPER-FILE COLOR COUNTS:")
    print("-" * 80)
    for filename in sorted(per_file.keys()):
        fc = per_file[filename]
        unique = len(fc)
        total = sum(fc.values())
        print(f"  {filename:40s}  {unique:3d} unique colors, {total:4d} total occurrences")

    print(f"\n{'=' * 80}")
    print(f"TOTAL UNIQUE COLORS (across all files): {len(global_colors)}")
    print(f"TOTAL COLOR OCCURRENCES: {sum(global_colors.values())}")
    print(f"{'=' * 80}")

    print("\nALL COLORS SORTED BY FREQUENCY:")
    print("-" * 80)
    print(f"  {'#':>4s}  {'Color':25s}  {'RGB':20s}  {'Count':>6s}  Original Forms")
    print("-" * 80)

    for idx, (canonical, count) in enumerate(global_colors.most_common(), 1):
        rgb = color_rgb[canonical]
        originals = ', '.join(sorted(original_forms[canonical]))
        if len(originals) > 60:
            originals = originals[:57] + "..."
        print(f"  {idx:4d}  {canonical:25s}  {str(rgb):20s}  {count:6d}  {originals}")

    # --- Group similar colors ---
    print(f"\n{'=' * 80}")
    print(f"SIMILAR COLOR GROUPS (RGB distance <= 15):")
    print("-" * 80)

    color_data = [(canon, color_rgb[canon], count) for canon, count in global_colors.items()]
    groups = group_similar_colors(color_data, threshold=15)
    groups.sort(key=lambda g: -sum(c for _, _, c in g))

    multi_groups = [g for g in groups if len(g) > 1]
    single_groups = [g for g in groups if len(g) == 1]

    print(f"\nFound {len(multi_groups)} groups with similar colors, {len(single_groups)} standalone colors\n")

    for i, group in enumerate(multi_groups, 1):
        total = sum(c for _, _, c in group)
        rep = group[0]
        print(f"  Group {i} (representative: {rep[0]}, total occurrences: {total}):")
        for canon, rgb, count in sorted(group, key=lambda x: -x[2]):
            print(f"    {canon:25s}  {str(rgb):20s}  count: {count}")
        print()

    # --- Deduplicated palette ---
    print(f"{'=' * 80}")
    print("DEDUPLICATED PALETTE (group representatives, sorted by frequency):")
    print("-" * 80)
    palette = []
    for group in groups:
        rep_canon, rep_rgb, _ = group[0]
        total = sum(c for _, _, c in group)
        palette.append((rep_canon, rep_rgb, total))

    palette.sort(key=lambda x: -x[2])
    for idx, (canon, rgb, total) in enumerate(palette, 1):
        print(f"  {idx:4d}  {canon:25s}  rgb{rgb}  total: {total}")

    print(f"\nTotal palette size: {len(palette)} colors")
    print(f"(reduced from {len(global_colors)} unique colors via similarity grouping)\n")


if __name__ == '__main__':
    main()
