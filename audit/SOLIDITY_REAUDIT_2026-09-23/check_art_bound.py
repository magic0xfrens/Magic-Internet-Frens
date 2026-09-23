"""Run from repository root. Conservative SVG bounds for local trait binaries."""
from pathlib import Path
import hashlib
import json
root = Path('compressed-traits')
stats = []
for p in sorted(root.glob('trait-*.bin')):
    b = p.read_bytes()
    lt, c, idx, x, y, w, h, n = b[:8]
    off = 8 + n
    assert len(b) >= off + (w*h+1)//2, p
    size = runs = 0
    def pixel(k):
        return (b[off+k//2] >> (4 if k % 2 == 0 else 0)) & 15
    for row in range(h):
        col = 0
        while col < w:
            v = pixel(row*w+col)
            assert v <= n, p
            if not v:
                col += 1
                continue
            end = col+1
            while end < w and pixel(row*w+end) == v:
                end += 1
            size += len(f"<rect x='{x+col}' y='{y+row}' width='{end-col}' height='1' fill='#FFFFFF'/>")
            runs += 1
            col = end
    stats.append(dict(file=str(p), sha256=hashlib.sha256(b).hexdigest(), layer=lt, cls=c, index=idx, bytes=size, runs=runs))
worst = []
for c in range(7):
    parts = [max((s for s in stats if s['layer'] == lt and s['cls'] == cl), key=lambda s:s['bytes']) for lt,cl in [(1,c if c in (5,6) else 0),(0,c),(2,c)]]
    worst.append(dict(cls=c, conservative_total=500+sum(s['bytes'] for s in parts), parts=parts))
r = dict(note='Exact pixel rect lengths; 500-byte upper bound for fixed header/footer (<400). Includes stale/unmanifested binaries conservatively. Arbitrary owner uploads excluded.', traits=len(stats), max_bytes=max(s['conservative_total'] for s in worst), by_class=worst, all_traits=stats)
Path('audit/SOLIDITY_REAUDIT_2026-09-23/remediation/ART_BUFFER_BOUND.json').write_text(json.dumps(r,indent=2)+'\n')
print(r['traits'], r['max_bytes'])
