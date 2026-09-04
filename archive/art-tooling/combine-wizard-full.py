#!/usr/bin/env python3
"""
Combine wizard: face (bottom) + body (middle) + staff (top)
Usage: python3 combine-wizard-full.py <wizard-num> <face-num> <staff-num> <output.svg>
Example: python3 combine-wizard-full.py 01 11 01 complete-wizard.svg
"""

import sys
import re
from pathlib import Path

def extract_svg_inner(svg_text):
    """Extract content between <svg> tags"""
    match = re.search(r'<svg[^>]*>(.*)</svg>', svg_text, re.DOTALL)
    if not match:
        return None
    return match.group(1).strip()

def combine_layers(face_path, wizard_path, staff_path, output_path):
    """Layer: face (base) -> wizard body -> staff (top)"""

    # Read all SVGs
    face_svg = Path(face_path).read_text()
    wizard_svg = Path(wizard_path).read_text()
    staff_svg = Path(staff_path).read_text()

    # Extract inner content
    wizard_inner = extract_svg_inner(wizard_svg)
    staff_inner = extract_svg_inner(staff_svg)

    if not wizard_inner or not staff_inner:
        print("Error: Could not parse SVG layers")
        return False

    # Build layers: face base + wizard + staff
    combined = face_svg.replace('</svg>', f'{wizard_inner}\n{staff_inner}\n</svg>')

    # Write output
    Path(output_path).write_text(combined)
    print(f"✅ Created: {output_path}")
    print(f"   Layer 1 (base): {face_path}")
    print(f"   Layer 2: {wizard_path}")
    print(f"   Layer 3 (top): {staff_path}")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 combine-wizard-full.py <wizard-num> <face-num> <staff-num> [output.svg]")
        print("Example: python3 combine-wizard-full.py 01 11 01 complete-wizard.svg")
        sys.exit(1)

    wizard_num = sys.argv[1].zfill(2)
    face_num = sys.argv[2].zfill(2)
    staff_num = sys.argv[3].zfill(2)
    output = sys.argv[4] if len(sys.argv) > 4 else f"wizard-{wizard_num}-face-{face_num}-staff-{staff_num}.svg"

    face_path = f"public/frens/face-{face_num}.svg"
    wizard_path = f"public/frens/wizard-{wizard_num}.svg"
    staff_path = f"public/frens/wiz-item-{staff_num}.svg"

    for path, name in [(face_path, "Face"), (wizard_path, "Wizard"), (staff_path, "Staff")]:
        if not Path(path).exists():
            print(f"❌ {name} not found: {path}")
            sys.exit(1)

    combine_layers(face_path, wizard_path, staff_path, output)
