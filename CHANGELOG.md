# Changelog

What changed in each release of Bitlathe. Newest first. `scripts/ship.sh` reads the section for the version it
publishes, so add a `## [x.y.z] - YYYY-MM-DD` section before releasing.

## [Unreleased]

## [0.1.0] - 2026-11-13

First release.

### The Smart Box
- **Paste anything.** JSON, JWTs, timestamps, URLs, Base64, cron, colours, curl, SQL, CSV, YAML and more are recognised and the best tool runs at once; alternatives are one key away (⌘1–⌘6).
- **Say what you want.** `sha256 hello`, `md5 of hello`, `to yaml {…}`, `decode aGk=`, `jwt eyJ…`, `3 uuid v7`, `password 24`, `tomorrow 9am`, `in 2 hours`.
- **Chains.** Base64 that hides JSON comes out decoded and formatted.
- **Fixes.** Broken JSON is offered a repair that lists every change; a list of lines is offered Remove duplicates and Sort.
- **Filter.** A bar under JSON results takes `$.user.id`, with the keys on show as chips to drill in (⌘/).
- **Learns on your Mac.** The action you accept most for each kind of data moves to the front; habits you drop fade.

### Everything else
- 100 tools behind ⌘K: format, convert, encode, inspect, generate.
- Menu bar Quick Panel (⌃⌥Space) shows the clipboard already transformed.
- Pipelines, a scratchpad, user scripts in JavaScript, Quick Look previews.
- `bl` command line tool, and `bl mcp` for AI agents.
- Optional on-device model (macOS 26 and later, Apple Intelligence) that picks the tool for a request in words. It only chooses; the tool produces the result.
