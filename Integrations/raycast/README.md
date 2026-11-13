# Bitlathe for Raycast

A Raycast extension that drives Bitlathe through the `bl` command line tool.

| Command | What it does |
| --- | --- |
| Search Bitlathe Tools | Lists every tool from `bl list --json`. Enter opens it in the app via `bitlathe://tool/<id>?input=<clipboard>&action=open`; Cmd+Enter runs it on the clipboard and shows the output (Copy / Paste actions); Cmd+Shift+Enter runs it and copies the result. |
| Detect Clipboard | Runs `bl detect --json` on the clipboard, ranks matching tools, and runs the one you pick. |
| Run Pipeline | Lists saved pipelines (tools of kind `pipeline` in `bl list --json`) and runs one on the clipboard with `bl pipeline <slug>`. |

## Requirements

* Bitlathe installed, and the `bl` CLI on disk: Bitlathe > Settings > Integrations > Install CLI.
* Node 20+ and npm. Raycast is only needed to load the extension.

## Install (development)

```bash
cd Integrations/raycast
npm install
npm run build      # validates and compiles; "built extension successfully"
npm run dev        # loads it into Raycast (requires Raycast.app)
```

`npm run dev` registers the extension in Raycast and keeps it live-reloading. Close the dev server to keep the
extension; it stays imported.

## Preferences

**bl Executable**: absolute path to `bl`. When empty the extension looks in `/usr/local/bin/bl`,
`/opt/homebrew/bin/bl` and `~/.local/bin/bl`.

## Notes

* Raycast runs extensions without your shell profile, so the extension does not rely on `PATH`.
* The `author` field in `package.json` must be a real Raycast Store username before you run `npm run lint` clean or
  publish; it is a placeholder here.
* Screenshots for a Store submission belong in `metadata/` (PNG, 2000x1250, taken with Raycast's Window Capture,
  `Cmd+Shift+Option+M`). None are included; the extension has not been loaded into Raycast in this repo's CI.
