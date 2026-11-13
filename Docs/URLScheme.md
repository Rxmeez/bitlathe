# URL scheme and Services menu

## URL scheme: `bitlathe://`

Parsing lives in `Sources/BitlatheCore/DeepLink.swift` (unit tested in `DeepLinkTests`). Routing is in `App/Integrations/DeepLinkRouter.swift`. Every failure shows a toast in the app; nothing crashes.

### Routes

| URL | What it does |
| --- | --- |
| `bitlathe://tool/<id>?…` | Run or open a tool. `<id>` is the tool id (see `TOOLS.md`), e.g. `json.format`. |
| `bitlathe://pipeline/<name-or-slug>?…` | Same, for a saved pipeline. Matches name (case-insensitive), slug or `pipeline.<slug>`. |
| `bitlathe://detect?input=…` | Runs detection on the input and uses the best tool. |

### Query parameters

| Key | Meaning |
| --- | --- |
| `input` | Percent-encoded text input. |
| `input64` | Base64 or base64url (padding optional) UTF-8 text. Wins over `input`. Safer for large or multi-line input. |
| `action` | `open` (default), `copy`, `replace`. |
| anything else | A tool option, by key (`indent=4`, `sortKeys=true`, `mode=decode`). Values are typed like the option's default. Unknown keys are an error ("Unknown option ... Available: ..."). Not used by `detect` or pipelines. |

### Actions

- `open`: shows the tool in the app with the input and options filled in, and brings the app forward.
- `copy`: runs headlessly and puts the output on the clipboard. A toast confirms. The app is not navigated.
- `replace`: same as `copy`, labelled for automation that pastes the result back over a selection (Shortcuts, Alfred, Raycast, Keyboard Maestro). It never brings a tool forward.

If Bitlathe is not running, macOS launches it first (its window appears on a cold start).

### Examples

```sh
# Open the JSON formatter with input and 4-space indent
open 'bitlathe://tool/json.format?input=%7B%22a%22:1%7D&indent=4'

# Base64-encode text and copy the result
open 'bitlathe://tool/base64.text?input=hello&action=copy'

# Decode: option mode=decode
open 'bitlathe://tool/base64.text?input=aGVsbG8%3D&mode=decode&action=copy'

# Multi-line input via base64
open "bitlathe://tool/json.format?input64=$(printf '{"a":1}' | base64)&action=copy"

# Let detection pick the tool, then open it
open 'bitlathe://detect?input=eyJhIjoxfQ%3D%3D'

# Run a saved pipeline and copy the result
open 'bitlathe://pipeline/clean-json?input64=eyJhIjoxfQ&action=copy'
```

## "Open in new window"

The sidebar context menu opens a separate window (`WindowGroup(id: "tool-window", for: String.self)`) with its own `AppModel`, so selection and sessions are independent of the main window.

## Services menu

Entries declared under `NSServices` in `project.yml` (generated into Info.plist), handled by `App/Integrations/ServiceProvider.swift`, registered via `NSApp.servicesProvider` and `NSUpdateDynamicServices()` at launch.

| Menu item | Message | Behaviour |
| --- | --- | --- |
| Bitlathe: Format JSON | `formatJSON` | `json.format` with defaults. |
| Bitlathe: Decode Base64 | `decodeBase64` | `base64.text` with `mode=decode`. |
| Bitlathe: Smart Transform | `smartTransform` | Runs detection and applies the top tool with its suggested options. |

Select text in any app, then use the app menu > Services (or the right-click Services submenu). The selection is replaced with the result. On failure (no text, invalid input, 10 s timeout) macOS shows the error from the service.

If entries do not appear, enable them in System Settings > Keyboard > Keyboard Shortcuts > Services > Text, or run `/System/Library/CoreServices/pbs -update`.
