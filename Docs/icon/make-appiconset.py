#!/usr/bin/env python3
"""Regenerate the app icon sets from the 1024 px renders (run from the repo root).

AppIcon      <- Docs/icon/bitlathe-icon-1024.png      (Release: "Bitlathe")
AppIcon-Dev  <- Docs/icon/bitlathe-dev-icon-1024.png  (Debug: "Bitlathe Dev")
"""
import json, os, subprocess

SETS = {
    "AppIcon": "Docs/icon/bitlathe-icon-1024.png",
    "AppIcon-Dev": "Docs/icon/bitlathe-dev-icon-1024.png",
}

for name, src in SETS.items():
    d = f"App/Assets.xcassets/{name}.appiconset"
    os.makedirs(d, exist_ok=True)
    imgs = []
    for pt in (16, 32, 128, 256, 512):
        for sc in (1, 2):
            px = pt * sc
            fn = f"icon_{pt}x{pt}@{sc}x.png"
            subprocess.run(["sips", "-z", str(px), str(px), src, "--out", f"{d}/{fn}"], check=True, capture_output=True)
            imgs.append({"filename": fn, "idiom": "mac", "scale": f"{sc}x", "size": f"{pt}x{pt}"})
    with open(f"{d}/Contents.json", "w") as f:
        json.dump({"images": imgs, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    print(f"{d}: {len(imgs)} images")
