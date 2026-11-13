# Scripting

Bitlathe runs your own JavaScript snippets as first-class tools. A script in the scripts folder appears in the sidebar (under **Scripts & Pipelines**), in the command palette (⌘K), in smart detection (when it declares a `detect` pattern) and in the `bl` command line, exactly like a built-in tool.

## Where scripts live

* Default: `Application Support/Bitlathe/Scripts` inside Bitlathe's sandbox container. The ten example scripts are copied there the first time the app launches.
* Custom: **Settings > Scripts > Choose Folder…**. Bitlathe is sandboxed, so the choice is stored as a security-scoped bookmark and stays valid across launches. The CLI is not sandboxed and reads the same path from settings.
* The folder is watched. Saving, adding, renaming or deleting a `.js` file reloads the scripts within a couple of seconds, no restart needed. **Reload** in Settings forces it.
* Settings > Scripts lists every loaded script (name, description, icon) and any load problem. **New Script…** writes the template as `my-script.js` and reveals it in Finder.

## File format

One `.js` file per script. The file name (lowercased, non-alphanumerics become `-`) gives the tool id: `url-slug.js` becomes `script.url-slug`.

A header comment holds the metadata as JSON (JSON5 is accepted: comments, trailing commas, unquoted keys):

```js
/**
 * @bitlathe {
 *   "name": "Sort JSON Keys",
 *   "description": "Recursively sort object keys alphabetically",
 *   "icon": "arrow.up.arrow.down",
 *   "keywords": ["json", "sort"],
 *   "detect": "^\\s*[\\{\\[]"
 * }
 */
function main(input) {
    input.text = input.text.toUpperCase();
}
```

| Key | Meaning | Default |
|-----|---------|---------|
| `name` | Shown in the sidebar and palette | file name |
| `description` | One-line summary | "User script" |
| `icon` | An SF Symbol name | `scroll` |
| `keywords` | Extra search terms (`tags` as a comma separated string also works) | none |
| `detect` | ICU regular expression. If clipboard or pasted text (under 4 KB) matches, Bitlathe suggests the script. Remember to escape backslashes inside JSON. | none |

Leading ` * ` decoration inside the comment is ignored. Boop headers (`/** { "api": 1, "name": … } **/`) are also understood, so many Boop scripts run unchanged when they use the API below.

## API

`main(input)` is called once. Read and assign `input.text`; whatever it holds afterwards is the output.

| Member | Description |
|--------|-------------|
| `input.text` | The selection if there is one, otherwise the whole input. Assign to replace it. |
| `input.fullText` | The whole input, always. |
| `input.selection` | The selected text, `""` when nothing is selected. |
| `input.isSelection` | `true` when there is a selection. |
| `input.postInfo(msg)` | Show `msg` as a warning next to the result. The run still succeeds. |
| `input.postError(msg)` | Fail the run and show `msg` as an error. |
| `input.insert(s)` | Same as assigning `input.text = s`. |
| `console.log(msg)` / `console.error(msg)` | Same as `postInfo` / `postError`. |

Throwing, a syntax error or a missing `main` are reported as errors with line and column where known.

## Limits and sandbox

* Each run uses a fresh JavaScriptCore context: no state survives between runs, and there is no `fetch`, `XMLHttpRequest`, `require`, file access or timers. A script can only transform the text it is given.
* A run is stopped and reported as an error after **2 seconds**. Avoid unbounded loops and very large allocations.
* Scripts cannot touch anything outside Bitlathe's sandbox, whatever they contain. Still, only install scripts you trust: the output they produce ends up on your clipboard or in your files.
* A script cannot replace a built-in tool: ids are `script.<file>`.

## Load problems

Settings > Scripts shows problems next to the file. A file with no `main` function, one that can't be read as UTF-8, or one that duplicates another script's id is not loaded (red). A malformed header still loads, using the file name and default icon (orange).

## Examples

Ten scripts ship with the app, installed on first launch (or later with **Copy Example Scripts**; existing files are never overwritten):

| File | What it does |
|------|--------------|
| `sort-json-keys.js` | Recursively sort JSON object keys |
| `url-slug.js` | Text to a URL-safe slug, one per line |
| `count-words.js` | Words, characters, lines, sentences, reading time |
| `reverse-lines.js` | Reverse line order |
| `camel-to-snake.js` | `camelCase` / `PascalCase` to `snake_case` |
| `strip-ansi.js` | Remove terminal escape sequences |
| `wrap-80.js` | Hard-wrap at 80 columns, keep indentation |
| `extract-emails.js` | Unique email addresses, one per line |
| `json-to-markdown-table.js` | JSON array of objects to a Markdown table |
| `add-line-numbers.js` | Prefix each line with its number |

## Command line

Scripts are loaded by `bl` from the same folder (Settings path if one is chosen, otherwise the container folder).

```sh
bl list --category scripting          # scripts show up in the list
echo '{"b":1,"a":2}' | bl script.sort-json-keys
bl script.url-slug notes.txt
git log --oneline | bl pipe "script.reverse-lines | script.add-line-numbers"
```

`postInfo` messages are printed to stderr as warnings; `postError` exits non-zero with the message.
