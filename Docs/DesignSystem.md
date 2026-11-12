# Bitlathe Design System

The bar: a first-party Apple app from 2026. Calm, fast, legible. Every token
below is defined once in `BitlatheUI/Tokens.swift` and used everywhere.

## Spacing scale (pt)
`xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48`

Rules: tool content has a 16 pt gutter; controls in a bar are 8 pt apart;
sections 24 pt apart. Never use a raw number in a view.

## Corner radii
`small 6 · medium 10 · large 14 · panel 18`. Chips and badges use `small`,
cards and editors `medium`, floating panels (palette, Quick Panel) `panel`.

## Type ramp (SF Pro / SF Mono)
| Token | Font | Use |
|------|------|-----|
| `title` | `.title2.weight(.semibold)` | one per screen (tool name) |
| `headline` | `.headline` | section titles in inspector/settings |
| `body` | `.body` | descriptions, option labels |
| `caption` | `.caption` secondary | status strip, hints |
| `mono` | `.system(size: 13, design: .monospaced)` | editors, code chips (zoomable) |
| `monoSmall` | `.system(size: 11, design: .monospaced)` | hex viewer, metadata |

Font zoom (⌘+ / ⌘− / ⌘0) scales `mono` and `monoSmall` between 9 and 32 pt.

## Colour
* Accent: system accent by default; optional Bitlathe accent `#3D7BFF` (light)
  / `#5B93FF` (dark).
* Semantic: `success` green, `warning` orange, `danger` red, always paired with
  an icon or text — never colour-only signals.
* Surfaces: `window` (system window background), `editor` (control background),
  `raised` (quaternary fill), `glass` (ultra-thin material; Liquid Glass on
  macOS 26 via `#if` availability).
* Six editor themes shipped: Bitlathe Light, Bitlathe Dark, Paper, Graphite,
  Solar, Midnight — each defined for light and dark appearance.

## Materials
Sidebar and toolbar use native vibrancy (`.sidebar`, `.bar`). Palette and Quick
Panel use `.regularMaterial` and, on macOS 26, `glassEffect`. Content areas
(editors, tables) are solid.

## Motion
`fast 120 ms` for crossfades of results and toasts; `normal 200 ms` for layout
changes; chips slide in with a 24 pt offset. All animations use
`.easeOut`. When Reduce Motion is on, everything becomes an instant switch.

## Components (BitlatheUI)
* `ToolHeader` — symbol, title, summary, trailing action bar.
* `OptionBar` — segmented controls / toggles / steppers from `OptionField`s.
* `SplitPane` — horizontal/vertical, draggable divider, remembers ratio.
* `CodeEditor` — editor with ruler, highlight, errors, find bar.
* `OutputPane` — picks renderer (code, image, table, tree, key/values).
* `StatusStrip` — size, lines, encoding, detected format, timing, validity.
* `ErrorBanner` — inline, with location, no modals.
* `EmptyState` — icon, one line, "Paste from clipboard", sample chips.
* `Chip`, `CopyButton`, `Toast`, `KeyValueList`, `SectionCard`.

## Layout
Three columns: sidebar (220–300 pt) → tool → inspector (260–360 pt, optional).
Tool screen: header (44 pt) → options bar (36 pt) → split → status strip (24 pt).
Minimum window 900 × 600.

## Accessibility
Every control has a label and hint. Keyboard focus order follows the visual
order. Contrast ≥ 4.5:1 for text, ≥ 3:1 for UI. All signals have text or icon.
