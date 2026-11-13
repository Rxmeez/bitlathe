# Bitlathe for Alfred

An Alfred 5 workflow (requires the Powerpack) that runs Bitlathe tools on the clipboard through `bl`.

| Keyword | Behaviour |
| --- | --- |
| `bl [query]` | Script filter over `bl list --json`. Choose a tool: it runs on the clipboard, the result is copied and a notification is posted. Saved pipelines appear too (`pipeline.<slug>`). |
| `bld` | Runs `bl detect --json` on the clipboard and lists the ranked tools; choose one to run it the same way. |

## Build and install

```bash
Integrations/alfred/build.sh          # writes Integrations/alfred/Bitlathe.alfredworkflow
open Integrations/alfred/Bitlathe.alfredworkflow
```

`build.sh [dir]` validates `info.plist` with `plutil -lint` and zips it with the scripts in `src/`. The scripts use only
`bash` and `osascript -l JavaScript`, which ship with macOS.

## Requirements and configuration

* `bl` on disk (Bitlathe > Settings > Integrations > Install CLI). The scripts check `$BL_PATH`, then
  `/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin`.
* To use another location, open the workflow in Alfred, click `[x]` (Configure Workflow variables) and set `BL_PATH`.
* Errors from a tool are shown in the notification instead of replacing the clipboard.

The script filter and run scripts were exercised from the command line; the `.alfredworkflow` itself has not been
imported into Alfred (not installed on the build machine).
