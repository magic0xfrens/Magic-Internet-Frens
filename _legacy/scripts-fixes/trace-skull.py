#!/usr/bin/env python3
"""
Trace pixel art skull from PNG screenshot into SVG.
Uses palette-based nearest-color matching for clean classification.
"""
from PIL import Image
import sys, math
from collections import Counter

img = Image.open("/Users/0x0010110/Downloads/skull.png").convert("RGB")
w, h = img.size
px = img.load()
print(f"Image: {w}x{h}")

# --- Grid detection (same as before, works well) ---
edge_counts = [0] * w
for y in range(0, h, 2):
    for x in range(1, w):
        r1, g1, b1 = px[x-1, y]
        r2, g2, b2 = px[x, y]
        if abs(r1-r2) + abs(g1-g2) + abs(b1-b2) > 25:
            edge_counts[x] += 1

peaks = [x for x in range(w) if edge_counts[x] > h//8]
cell = 9
if len(peaks) > 2:
    gaps = [peaks[i+1] - peaks[i] for i in range(len(peaks)-1)]
    gap_counts = Counter(gaps)
    for g, c in gap_counts.most_common(10):
        if 5 <= g <= 20:
            cell = g
            break

offset_x = 0
for x in range(cell):
    if edge_counts[x] > h//10:
        offset_x = x
        break

cols = (w - offset_x) // cell
rows = (h - offset_y if (offset_y := 0) else h) // cell
print(f"Grid: {cols}x{rows}, cell={cell}, offset={offset_x}")

# --- Sample each art pixel (center of each cell, 3x3 median) ---
grid = {}
for gy in range(rows):
    for gx in range(cols):
        cx = offset_x + gx * cell + cell // 2
        cy = gy * cell + cell // 2
        if cx < w and cy < h:
            samples = []
            for dx in range(-1, 2):
                for dy in range(-1, 2):
                    sx, sy = cx + dx, cy + dy
                    if 0 <= sx < w and 0 <= sy < h:
                        samples.append(px[sx, sy])
            samples.sort()
            grid[(gx, gy)] = samples[len(samples)//2]

# --- Palette-based classification ---
# Known skull colors (sampled from the image)
SKULL_PALETTE = [
    (234, 226, 180, "bone"),       # cream bone
    (152, 149, 130, "shadow"),     # warm shadow grey
    (48, 48, 42, "dark"),          # dark outline
    (1, 0, 0, "black"),            # pure black (eyes/mouth)
    (0, 0, 0, "black"),            # pure black
    (255, 248, 226, "highlight"),  # bright highlight
    (109, 76, 65, "brown"),        # brown outline
    (77, 54, 47, "brown"),         # brown/jaw
    (130, 81, 51, "edge"),         # brown edge
    (97, 88, 79, "dark_warm"),     # warm dark grey
]

# Known background colors
BG_PALETTE = [
    (107, 107, 107, "grey_bg"),
    (92, 92, 92, "grey_bg2"),
    (61, 61, 61, "dark_grey_bg"),
    (207, 203, 193, "light_grey_bg"),
    (253, 199, 51, "fire1"),
    (244, 175, 48, "fire2"),
    (200, 150, 30, "fire3"),
    (180, 120, 40, "fire4"),
    (84, 55, 13, "wood1"),        # dark wood plank
    (128, 86, 25, "wood2"),       # light wood plank
    (255, 160, 0, "candle"),      # candle flame
]

def cdist(c, ref):
    """Euclidean color distance."""
    return math.sqrt((c[0]-ref[0])**2 + (c[1]-ref[1])**2 + (c[2]-ref[2])**2)

def classify(r, g, b):
    color = (r, g, b)
    bright = (r + g + b) / 3.0
    sat = max(r, g, b) - min(r, g, b)

    # --- Hard excludes first ---
    # Blue-dominant = water bg
    if b > r + 30 and b > g:
        return "bg"
    # Very saturated fire/gold
    if r > 160 and sat > 80 and b < 80 and g > 60:
        return "bg"
    # Light neutral grey (not warm enough for bone)
    if bright > 170 and sat < 25 and (r - b) < 25:
        return "bg"
    # Cool mid-grey background
    if 80 < bright < 130 and sat < 15:
        return "bg"
    # Neutral dark grey background (50-80 range, near-zero saturation)
    # Skull dark outline (48,48,42) has bright=46 so stays below this
    if 50 < bright < 80 and sat < 10:
        return "bg"

    # --- Palette matching ---
    min_skull = min(cdist(color, (sr, sg, sb)) for sr, sg, sb, _ in SKULL_PALETTE)
    min_bg = min(cdist(color, (br, bg_, bb)) for br, bg_, bb, _ in BG_PALETTE)

    # If clearly closer to skull palette
    if min_skull < 35 and min_skull < min_bg - 10:
        if bright < 15:
            return "dark"  # near-black, resolve later
        return "skull"

    # If clearly closer to bg palette
    if min_bg < 30 and min_bg < min_skull - 10:
        return "bg"

    # Ambiguous — use heuristics
    if bright < 15:
        return "dark"  # near-black
    if bright < 55 and sat < 15:
        return "dark"  # very dark, could be outline or bg
    if r >= g and g >= b and sat < 80:
        return "skull"  # warm = skull
    if bright > 140 and (r - b) > 20:
        return "skull"  # warm bright = bone

    return "bg"

classified = {}
for pos, (r, g, b) in grid.items():
    classified[pos] = classify(r, g, b)

# --- Spatial crop ---
SKULL_X_MAX = 42
SKULL_Y_MIN, SKULL_Y_MAX = 0, 33

# Curved left edge to follow skull's oval shape (wood planks are same color as skull outline)
def get_x_min(gy):
    if gy <= 1: return 8
    elif gy <= 2: return 7
    elif gy <= 4: return 6
    elif gy <= 6: return 5
    elif gy <= 8: return 5
    elif gy <= 28: return 4
    elif gy <= 29: return 5
    elif gy <= 30: return 6
    elif gy <= 31: return 7
    elif gy <= 32: return 8
    else: return 9

for pos in list(classified.keys()):
    gx, gy = pos
    if gx < get_x_min(gy) or gx > SKULL_X_MAX or gy < SKULL_Y_MIN or gy > SKULL_Y_MAX:
        classified[pos] = "bg"

# --- Resolve dark pixels (eyes/mouth vs background) ---
def count_neighbors(pos, label):
    gx, gy = pos
    n = 0
    for dx, dy in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)]:
        np_ = (gx+dx, gy+dy)
        if np_ in classified and classified[np_] == label:
            n += 1
    return n

# Dark pixels with 2+ skull neighbors (4-connected) = skull
for _ in range(4):
    changed = False
    for pos in list(classified.keys()):
        if classified[pos] == "dark":
            gx, gy = pos
            n4 = sum(1 for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]
                     if (gx+dx, gy+dy) in classified and classified[(gx+dx, gy+dy)] == "skull")
            if n4 >= 2:
                classified[pos] = "skull"
                changed = True
    if not changed:
        break

# Remaining dark with 1+ skull neighbor = skull
for pos in list(classified.keys()):
    if classified[pos] == "dark":
        gx, gy = pos
        n4 = sum(1 for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]
                 if (gx+dx, gy+dy) in classified and classified[(gx+dx, gy+dy)] == "skull")
        if n4 >= 1:
            classified[pos] = "skull"
        else:
            classified[pos] = "bg"

# --- Flood fill (8-connected for skull blob, allows diagonal) ---
skull_pixels = set()

# Find start: bright bone pixel near center of skull region
start = None
center_x = (get_x_min(17) + SKULL_X_MAX) // 2
center_y = (SKULL_Y_MIN + SKULL_Y_MAX) // 2
for radius in range(max(cols, rows)):
    for cx in range(center_x - radius, center_x + radius + 1):
        for cy in range(center_y - radius, center_y + radius + 1):
            if (cx, cy) in classified and classified[(cx, cy)] == "skull":
                r, g, b = grid.get((cx, cy), (0,0,0))
                if (r + g + b) / 3 > 120:
                    start = (cx, cy)
                    break
        if start: break
    if start: break

print(f"Flood fill start: {start}")

if start:
    # 8-connected flood fill (allows diagonal connections within skull)
    queue = [start]
    visited = set()
    while queue:
        pos = queue.pop()
        if pos in visited:
            continue
        visited.add(pos)
        if pos not in classified or classified[pos] != "skull":
            continue
        skull_pixels.add(pos)
        gx, gy = pos
        for dx in [-1, 0, 1]:
            for dy in [-1, 0, 1]:
                if dx == 0 and dy == 0:
                    continue
                np_ = (gx+dx, gy+dy)
                if np_ not in visited:
                    queue.append(np_)

print(f"Skull pixels after flood fill: {len(skull_pixels)}")

if not skull_pixels:
    print("ERROR: No skull found!")
    sys.exit(1)

# --- Bounding box ---
xs = [p[0] for p in skull_pixels]
ys = [p[1] for p in skull_pixels]
min_x, max_x = min(xs), max(xs)
min_y, max_y = min(ys), max(ys)
skull_w = max_x - min_x + 1
skull_h = max_y - min_y + 1
print(f"Skull bounds: ({min_x},{min_y})-({max_x},{max_y}) = {skull_w}x{skull_h}")

# --- Center on 120x120 canvas ---
off_x = (120 - skull_w) // 2 - min_x
off_y = (120 - skull_h) // 2 - min_y

# --- Snap colors to clean palette ---
CLEAN_PALETTE = {
    "highlight": (255, 248, 224),
    "bone":      (232, 224, 180),
    "shadow":    (152, 148, 128),
    "dark":      (48, 48, 40),
    "brown":     (108, 76, 64),
    "brown2":    (76, 52, 44),
    "edge":      (128, 80, 48),
    "black":     (0, 0, 0),
    "dark_warm": (96, 88, 80),
}

def snap_color(r, g, b):
    """Snap to nearest clean palette color."""
    best_name = "bone"
    best_dist = 999
    for name, (pr, pg, pb) in CLEAN_PALETTE.items():
        d = math.sqrt((r-pr)**2 + (g-pg)**2 + (b-pb)**2)
        if d < best_dist:
            best_dist = d
            best_name = name
    return CLEAN_PALETTE[best_name]

# --- Generate SVG ---
lines = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" shape-rendering="crispEdges">']
lines.append('<!-- Skull traced from pixel art reference -->')

for (gx, gy) in sorted(skull_pixels, key=lambda p: (p[1], p[0])):
    sx = gx + off_x
    sy = gy + off_y
    if 0 <= sx < 120 and 0 <= sy < 120:
        r, g, b = grid[(gx, gy)]
        r, g, b = snap_color(r, g, b)
        lines.append(f'<rect x="{sx}" y="{sy}" width="1" height="1" fill="#{r:02X}{g:02X}{b:02X}"/>')

lines.append('</svg>')

svg_path = "/Users/0x0010110/Documents/GitHub/MagicFrens/public/frens/skull.svg"
with open(svg_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f"\nWrote skull SVG: {len(skull_pixels)} pixels")

# Visual grid
print("\nVisual grid (skull only):")
for gy in range(min_y, max_y + 1):
    row = ""
    for gx in range(min_x, max_x + 1):
        if (gx, gy) in skull_pixels:
            r, g, b = grid[(gx, gy)]
            br = (r + g + b) / 3
            if br < 40:
                row += "█"
            elif br < 90:
                row += "▓"
            elif br < 150:
                row += "▒"
            else:
                row += "░"
        else:
            row += " "
    print(f"  {gy:2d}: |{row}|")

# Also print color stats
color_counts = Counter()
for pos in skull_pixels:
    r, g, b = grid[pos]
    r, g, b = snap_color(r, g, b)
    name = "?"
    for n, (pr, pg, pb) in CLEAN_PALETTE.items():
        if (pr, pg, pb) == (r, g, b):
            name = n
            break
    color_counts[name] += 1

print(f"\nColor distribution:")
for name, count in color_counts.most_common():
    print(f"  {name}: {count}")
