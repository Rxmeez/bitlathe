# Decisions

Format: date · decision · why · consequences.

- **2026-11-12 · Build with Xcode 16.4 / macOS 15.5 SDK.** The machine has
  Xcode 16.4 (Swift 6.1.2). macOS 26 APIs (Liquid Glass, Foundation Models)
  are not in that SDK, so they are gated with `#if canImport(FoundationModels)`
  and `#if compiler(>=6.2)` + `#available(macOS 26, *)`. They compile to no-ops
  on 16.4 and light up when the project is built with Xcode 26.
- **2026-11-12 · Own `CodeEditor` on NSTextView instead of CodeEditSourceEditor/STTextView.**
  Zero dependencies, Swift 6 clean, full control over highlighting and error
  underlines; wrapped so it can be replaced. Trade-off: no code folding (listed
  as a known gap in TOOLS.md).
- **2026-11-12 · SQLite (system module) instead of SwiftData/GRDB** for history,
  favourites, usage and pipelines. SwiftData + strict concurrency is still
  rough on macOS 14 and GRDB is a large dependency for four tables.
- **2026-11-12 · JS formatters in JavaScriptCore.** Prettier 3.10.1,
  sql-formatter 15.9.0, terser 5.51.2, marked 15.0.12, mermaid 11.17.2 and
  highlight.js 11.12.0 are bundled as resources (MIT, except Terser: BSD-2-Clause and highlight.js: BSD-3-Clause; see THIRD_PARTY_NOTICES.md). Loaded lazily, one
  warmed context per bundle, no Node, no network.
- **2026-11-12 · Dropped ua-parser-js** (AGPL). User-agent parsing is our own
  regex table.
- **2026-11-12 · Dropped turndown** (needs a DOM). HTML → Markdown and HTML → JSX
  use Foundation's `XMLDocument` HTML tidy parser.
- **2026-11-12 · Brotli** uses Apple's `Compression` framework (encode and decode
  both verified on macOS 15+).
- **2026-11-12 · Declarative options.** Every tool publishes `optionFields`;
  one generic option bar and one CLI flag parser serve 90% of tools. Custom
  views are the exception, not the rule.
- **2026-11-12 · Password hashing implemented natively** (bcrypt, scrypt,
  Argon2id, BLAKE2, BLAKE3, SHA-3, Keccak) rather than via C dependencies:
  keeps the sandbox simple and the licence list short; all have test vectors.
- **2026-11-12 · Diceware uses the EFF short word list** (CC-BY 3.0, attributed
  in THIRD_PARTY_NOTICES.md).
- **2026-11-12 · Two app targets, shared sources** for Direct and App Store
  builds; `DIRECT_DISTRIBUTION` compile flag gates Sparkle and the direct CLI
  symlink installer.
- **2026-11-12 · `com.apple.security.network.client` for WebKit previews (approved by the owner).**
  Inside the App Sandbox, WKWebView's renderer stays blank without this entitlement, even for
  `loadHTMLString` with no base URL. The HTML and Markdown previews add a WKContentRuleList that blocks
  every URL except `about:`, `data:` and `blob:`, cancel all navigation except in-page anchors, and use a
  non-persistent data store. Verified: previewing HTML that references a remote stylesheet, script,
  images and an iframe opened no sockets in the app or WebKit's WebContent/Networking processes.
  Links open in the default browser only on an explicit click.
- **2026-11-13 · The on-device model lives in a helper (`bl-advisor`), and only chooses tools.** Xcode 16.4's SDK has
  no FoundationModels, but the Command Line Tools on the same Mac do (Swift 6.4, macOS 27 SDK). They cannot build the
  app (no SwiftUI macro plug-ins), so the model call is a dependency-free SwiftPM executable that `scripts/embed-cli.sh`
  builds with the Command Line Tools when Xcode's SDK lacks the framework, and with Xcode otherwise (where it reports
  "built without on-device model support" until Xcode has the SDK). The app runs it from `Contents/Helpers`.
  The model never produces a result: `SmartBox.Advisor` gives it a shortlist of at most 14 tools, and accepts back
  only a tool id from that list, option values that tool declares, and input that is a verbatim part of the
  person's text. Text that looks like a secret is never sent. Consequences: the App Store target, which does not
  embed helpers, has no model; when Xcode is upgraded the helper could be folded into the app.
