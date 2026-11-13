#!/usr/bin/env python3
"""Regenerate App/Assets.xcassets/AppIcon.appiconset from Docs/icon/bitlathe-icon-1024.png (run from repo root)."""
import json, subprocess

D = "App/Assets.xcassets/AppIcon.appiconset"
imgs = []
for pt in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        px = pt * sc
        fn = f"icon_{pt}x{pt}@{sc}x.png"
        subprocess.run(["sips", "-z", str(px), str(px), "Docs/icon/bitlathe-icon-1024.png", "--out", f"{D}/{fn}"],
                       check=True, capture_output=True)
        imgs.append({"filename": fn, "idiom": "mac", "scale": f"{sc}x", "size": f"{pt}x{pt}"})
json.dump({"images": imgs, "info": {"author": "xcode", "version": 1}}, open(D + "/Contents.json", "w"), indent=2)
