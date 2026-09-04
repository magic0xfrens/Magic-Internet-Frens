#!/usr/bin/env python3
"""
Combine wizard body + face layers into a single SVG
Usage: python3 combine-wizard.py <wizard-num> <face-num> <output.svg>
Example: python3 combine-wizard.py 05 07 purple-derp-wizard.svg
"""

import sys
import re
from pathlib import Path

def combine_svgs(wizard_path, face_path, output_path):
    """Layer wizard SVG on top of face SVG (face = base layer)"""

    # Read both SVGs
    wizard_svg = Path(wizard_path).read_text()
    face_svg = Path(face_path).read_text()

    # Extract content between <svg> tags (remove svg wrapper from wizard)
    wizard_content = re.search(r'<svg[^>]*>(.*)</svg>', wizard_svg, re.DOTALL)
    if not wizard_content:
        print("Error: Could not parse wizard SVG")
        return False

    wizard_inner = wizard_content.group(1).strip()

    # Insert wizard content before closing </svg> tag of face (face is base, wizard on top)
    combined = face_svg.replace('</svg>', f'{wizard_inner}\n</svg>')

    # Write output
    Path(output_path).write_text(combined)
    print(f"✅ Created: {output_path}")
    print(f"   Wizard: {wizard_path}")
    print(f"   Face: {face_path}")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 combine-wizard.py <wizard-num> <face-num> [output.svg]")
        print("Example: python3 combine-wizard.py 05 07 purple-derp-wizard.svg")
        sys.exit(1)

    wizard_num = sys.argv[1].zfill(2)  # Pad to 02
    face_num = sys.argv[2].zfill(2)
    output = sys.argv[3] if len(sys.argv) > 3 else f"wizard-{wizard_num}-face-{face_num}.svg"

    wizard_path = f"public/frens/wizard-{wizard_num}.svg"
    face_path = f"public/frens/face-{face_num}.svg"

    if not Path(wizard_path).exists():
        print(f"❌ Wizard not found: {wizard_path}")
        sys.exit(1)

    if not Path(face_path).exists():
        print(f"❌ Face not found: {face_path}")
        sys.exit(1)

    combine_svgs(wizard_path, face_path, output)
