# Bitlathe app icon

## Concept
One bold glyph: a **turned spindle** seen side-on, split down its axis.
The left half is *raw bits* — a staircase of rounded squares approximating the
profile. The right half is the *finished turning* — the same profile as one
smooth, continuous curve. A hairline at the axis is the cutting edge where raw
becomes clean. Bits in, clean shape out; no wrench, no gear.
The hourglass-like silhouette still reads at 16-32 px.

## Construction
* Canvas 1024 x 1024, transparent.
* macOS icon grid: body is an 824 x 824 rounded square centred at (100,100),
  corner radius 185 (about 22.4 %), leaving a 100 px margin for the shadow.
* Glyph: axis x = 512, spans y 212-812 (600 px, 15 rows of 40 px). Half-width
  profile `w(t) = 135 + 62 cos(2 pi t)` for t in 0..1 (195 px at the ends, 73 px at the waist).
* Bits: 34 px squares, radius 6, 6 px gap (40 px pitch), row count per row =
  `round(w / 40)`, right edge flush 3 px from the axis.
* Cutting-edge hairline: 4 x 644 px at x = 510, 35 % white.

## Colour
| Role | Value |
|------|-------|
| Body gradient top to bottom | `#5E8DFF` to `#1B2F9E` (sits with the app accent `#3D7BFF`) |
| Top sheen | white 22 % fading to 0 by 45 % height |
| Smooth half | gradient `#FFFFFF` to `#CFDDFF` |
| Bits | white 92 % |
| Glyph shadow | `#0A1650` 45 %, blur 10, dy 10 |
| Body drop shadow | black 28 %, blur 14, dy 14 |

## Files
* `Docs/icon/bitlathe-icon.svg` — hand-written source of truth.
* `Docs/icon/bitlathe-icon-1024.png` — render (`inkscape ... -w 1024 -h 1024`).
* `Docs/icon/make-appiconset.py` — slices the PNG into
  `App/Assets.xcassets/AppIcon.appiconset` (16-512 at 1x/2x, 1024 is the 512@2x).
