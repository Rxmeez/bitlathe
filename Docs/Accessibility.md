# Accessibility audit

Method: code review of the shared UI plus a Release build (no warnings). The live AXUIElement tree was NOT inspected
(no Accessibility permission/running session in this pass), and no 1.5x-zoom screenshots were taken.

## Checklist

| Area | Status |
|---|---|
| Icon-only buttons labelled (+ help): settings gear, More actions, Copy output, favourite, copy, dismiss, diff nav | Done |
| Decorative images hidden (empty-state glyphs, file icon, clipboard wand) | Done |
| Status badges convey state in text + icon (`StatusBadge`) | Already OK |
| Diff added/removed not colour-only: unified has +/- glyph; side-by-side cells now labelled "Added/Removed, line N, text"; chips carry +/- and words | Done |
| Regex flag chips expose selected trait; match/group highlights are tinted only (tooltips, no text) | Partial |
| CodeEditor label ("Input editor"/"Output editor", language), placeholder as help | Done |
| Editor errors announced (NSAccessibility announcementRequested, high priority) once per new error | Done |
| Toasts announced to VoiceOver | Done |
| Shortcut conflicts: Save (Cmd-Shift-S) in file preview clashed with Swap; Cmd-Opt-V on in-view Paste buttons duplicated menu Smart Paste; both removed | Done |
| Menu shortcuts present: Copy Output, Replace Clipboard (Cmd-Shift-V, unique), Swap, Clear, Open, Save, Inspector, zoom, palette | Verified in Commands.swift |
| Esc dismisses clipboard-suggestion banner | Already OK (cancelAction) |
| Contrast: status colours (success/warning/danger) were 2.1-3.4:1 on light chrome; now adaptive, >= 4.5:1 text and on 14% tint, light and dark | Done |
| Contrast: `.tertiary` text was ~1.9:1 light / 2.3:1 dark; text uses switched to `Palette.subtle` (~5.9:1 light, ~6.3:1 dark) | Done (icons left tertiary) |
| Reduce Motion: `Motion.animation()` returns nil for system setting or app override; all `withAnimation`/`.animation` in audited files route through it | Verified |

## Not done / known issues

- `.secondary` system label is ~3.9:1 on light chrome (below AA 4.5). It is used widely; fix needs a global token swap.
- Cmd-Delete (Clear) is a menu shortcut and shadows the text view's delete-to-line-start while an editor has focus. Consider Cmd-Shift-Delete.
- Font zoom (Cmd +/-/0) scales only the editor (mono) size, not sidebar/header/status text. Not changed (needs a type-scale design).
- Cmd-L to focus sidebar search: `.searchable` focus control needs macOS 15 (`searchFocused`); app targets 14.
- Zoom In is bound to "+"; "=" alias not added.
- Regex match/group highlights are colour-only in the editor (no text equivalent for VoiceOver beyond the match list).
- Live AX tree inspection and 1.5x zoom screenshots not performed.
