#!/usr/bin/env python3
"""Print the README tool tables from `bl list --json`. Usage: bl list --json | scripts/gen-tool-table.py"""
import json, sys
d = json.load(sys.stdin)
names = {'format': 'Format & validate', 'convert': 'Converters', 'encode': 'Encoders & decoders',
         'inspect': 'Inspect, preview & debug', 'generate': 'Generators', 'media': 'Images & media'}
for k, n in names.items():
    ts = sorted((t for t in d if t['category'] == k), key=lambda t: t['id'])
    print(f"<details>\n<summary><b>{n}</b> ({len(ts)})</summary>\n\n| `bl` id | Tool | What it does |\n|---|---|---|")
    for t in ts:
        s = t['summary'].replace('|', '\\|')
        print(f"| `{t['id']}` | {t['name']} | {s} |")
    print("\n</details>\n")
