# Changelog

What changed in each release of Bitlathe, newest first. The format follows [Keep a Changelog](https://keepachangelog.com),
and versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

## [0.1.1] - 2026-11-14

Two new visualisers: paste a GitHub Actions workflow or Kubernetes manifests and see them as a diagram.

### Added
- **GitHub Actions Visualizer.** Paste a workflow to see its triggers and jobs as a graph in the order `needs:` runs them, with each job's runner, steps and matrix. Matrices are counted the way GitHub expands them (`include`, `exclude`), and `runs-on: ${{ matrix.os }}` shows the actual runners. Cycles and unknown `needs:` are flagged.
- **Kubernetes Visualizer.** Paste manifests (several documents, or a `kubectl get -o yaml` list) to see Ingress and Gateway routes → Services → the workloads their selectors pick → ConfigMaps, Secrets, volumes, service accounts and RBAC. Anything referred to but not defined is drawn dashed, and a Service whose selector matches nothing is flagged. Secret values are never shown, only key names.
- Both open straight from the Smart Box when you paste a workflow or manifests. Click a card for its details and connections; copy the diagram as an image or as Mermaid. In `bl` and for AI agents they print a text outline.

## [0.1.0] - 2026-11-13

The first release. Bitlathe is a developer toolbox for the Mac with one idea at its centre: you paste, it works out
what you pasted and what you probably want done with it.

### The Smart Box

- **Paste anything.** JSON, JWTs, timestamps, URLs, Base64, cron, colours, curl, SQL, CSV, YAML, certificates, IP ranges and more are recognised, and the best tool runs at once. Alternatives are one key away (`⌘1`–`⌘6`); `⌘↩` copies the result.
- **Say what you want.** An instruction, then the data: `sha256 hello`, `md5 of hello`, `to yaml {…}`, `decode aGk=`, `minify {…}`, `snake_case helloWorld`, `count words in …`. Or a tool's name, then the data: `jwt eyJ…`, `qr https://…`.
- **Commands.** `3 uuid v7`, `password 24`, `lorem 2 sentences`, `now`.
- **Dates in words.** `tomorrow 9am`, `next friday`, `in 2 hours`, `3 days ago`.
- **Chains.** Base64 that hides JSON comes out decoded and formatted, in one step.
- **Fixes.** Broken JSON is offered a repair (missing commas, unclosed brackets, single quotes, `True`/`None`, text cut off half-way) that lists every change it made. JSON Lines are joined into an array. A list of lines is offered Remove duplicates and Sort.
- **Filter.** A bar under JSON results takes a path such as `$.user.id`; the keys on show are chips you can click to drill in. `⌘/` jumps there.
- **Secrets are marked.** Keys, tokens and JWTs are flagged, and never leave your Mac.
- **It learns, on your Mac only.** The action you accept most for each kind of data moves to the front, and habits you drop fade. Reset it in Settings › History & Privacy.

### Tools

- **100 tools** behind `⌘K`: format, convert, encode and decode, inspect, generate. JSON, YAML, XML, TOML, SQL, HTML, CSS, JavaScript, CSV, hashes, JWTs, certificates, cron, colours, regular expressions, diffs, QR codes and more.
- **Results beside their facts.** A parsed URL or a decoded token shows the result and the table of details side by side.
- **Menu bar Quick Panel** (`⌃⌥Space`): the clipboard, already transformed, ready to copy.
- **Pipelines** chain tools; the **Scratchpad** applies tools to selections; **user scripts** in JavaScript become tools.
- **Quick Look** previews for JSON, YAML, CSV and other developer files in Finder.

### For the command line and AI agents

- **`bl`**, a command line tool with every text tool: `bl json.format < package.json`, `pbpaste | bl detect`.
- **`bl mcp`** serves the tools to Claude Code and other agents over the Model Context Protocol, so they get exact results instead of guessing a hash or a decode.

### On-device model (optional)

- On macOS 26 and later with Apple Intelligence, the language model built into macOS can pick the tool for a request the rules do not recognise. It only chooses a tool; the tool produces the result, text that looks like a secret is never shown to it, and nothing leaves your Mac. Switch it off in Settings › Detection.

### Good to know

- Bitlathe is not notarised by Apple. The first time you open it, allow it in System Settings › Privacy & Security › Open Anyway. Updates install themselves after that.
- Everything runs locally. Bitlathe sends nothing anywhere.

[Unreleased]: https://github.com/Rxmeez/bitlathe/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/Rxmeez/bitlathe/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Rxmeez/bitlathe/releases/tag/v0.1.0
