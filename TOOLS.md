# Bitlathe — Tool checklist

Status: ✅ done · 🚧 in progress · ⬜ not started · ★ beyond DevUtils

✅ means the engine works in the generic screen and the CLI. Custom views (tree, swatches, side-by-side diff, previews) are still pending for the richer tools.

Tool IDs are stable and used by the CLI (`bl <id>`), URL scheme and Shortcuts.

## 1. Format, validate and minify
| ID | Tool | Status | Notes |
|----|------|--------|-------|
| json.format | JSON format / validate / minify | ✅ | indent, sort keys, escape non-ASCII, ★ tree view, ★ JSONPath/jq-style query, ★ JSON Schema validation, ★ JSON5/JSONC input |
| html.format | HTML beautify / minify | ✅ | prettier |
| css.format | CSS beautify / minify | ✅ | prettier + own minifier |
| js.format | JavaScript beautify / minify | ✅ | prettier + terser |
| ts.format | ★ TypeScript beautify | ✅ | prettier |
| xml.format | XML beautify / minify | ✅ | XMLDocument |
| scss.format | SCSS beautify | ✅ | prettier |
| less.format | LESS beautify | ✅ | prettier |
| erb.format | ERB beautify | ✅ | placeholder-protected HTML formatting |
| sql.format | SQL formatter | ✅ | standard, PostgreSQL, MySQL, ★ BigQuery, ★ Snowflake, ★ SQLite; keyword case |
| graphql.format | ★ GraphQL formatter | ✅ | prettier |
| yaml.format | ★ YAML formatter / validator | ✅ | Yams |
| toml.format | ★ TOML formatter | ✅ | TOMLKit |
| text.lines | Line tools | ✅ | sort (alpha/natural/numeric/length), dedupe, reverse, shuffle, trim, remove empty, prefix/suffix, number, join/split |

## 2. Data converters
| ID | Tool | Status | Notes |
|----|------|--------|-------|
| convert.yaml-json | YAML ⇄ JSON | ✅ | |
| convert.json-csv | JSON ⇄ CSV / TSV | ✅ | |
| convert.json-toml | ★ JSON ⇄ TOML | ✅ | |
| convert.json-xml | ★ JSON ⇄ XML | ✅ | |
| convert.json-plist | ★ JSON ⇄ Property List | ✅ | XML + binary plist |
| convert.json-query | ★ JSON ⇄ query string | ✅ | |
| json.to-code | JSON → code types | ✅ | TypeScript, Swift Codable, Go, Kotlin, Rust serde, Python dataclass / Pydantic, C#, Java, JSON Schema |
| php.array-json | PHP array ⇄ JSON | ✅ | |
| php.serialize | PHP serialize / unserialize | ✅ | |
| html.to-jsx | HTML → JSX | ✅ | |
| svg.to-css | SVG → CSS | ✅ | data URI + background-image |
| svg.to-code | ★ SVG → SwiftUI Path / React component | ✅ | |
| curl.to-code | cURL → code | ✅ | Swift, Python, JS fetch, Node axios, Go, Rust, PHP, Ruby |
| code.to-curl | ★ code / raw HTTP → cURL | ✅ | |
| text.case | String case converter | ✅ | all variants shown at once |
| number.base | Number base converter | ✅ | 2/8/10/16/32/36/custom, signed, bit width |
| hex.text | Hex ⇄ ASCII / ★ UTF-8 bytes / ★ binary | ✅ | |
| convert.bytesize | ★ Byte-size converter | ✅ | |
| convert.units | ★ Unit converter | ✅ | durations, data rates, px/pt/rem/em |
| csv.viewer | ★ CSV table viewer | ✅ | sort, filter, column stats |
| convert.markdown-html | ★ Markdown ⇄ HTML | ✅ | |

## 3. Encoders and decoders
| ID | Tool | Status | Notes |
|----|------|--------|-------|
| base64.text | Base64 string encode / decode | ✅ | URL-safe, no padding |
| base64.image | Base64 image encode / decode | ✅ | preview, data URI |
| url.encode | URL encode / decode | ✅ | component vs full |
| html.entities | HTML entity encode / decode | ✅ | |
| text.backslash | Backslash escape / unescape | ✅ | |
| base32.text | ★ Base32 | ✅ | |
| base58.text | ★ Base58 | ✅ | |
| base85.text | ★ Base85 / Ascii85 | ✅ | |
| compress.text | ★ Gzip / Deflate / Brotli / Zlib | ✅ | Base64 or hex wrapping |
| unicode.escape | ★ Unicode escape | ✅ | \u, &#…;, %… in every direction |
| punycode.idn | ★ Punycode / IDN | ✅ | |
| quoted.printable | ★ Quoted-printable | ✅ | |
| binary.decode | ★ MessagePack / CBOR / Protobuf → JSON | ✅ | |
| string.escape | ★ String escaping per language | ✅ | JSON, Swift, JS, Python, Go, SQL, shell, regex, CSV |

## 4. Inspect, preview and debug
| ID | Tool | Status | Notes |
|----|------|--------|-------|
| time.unix | Unix timestamp converter | ✅ | s/ms/µs/ns auto, zones, relative, ISO/RFC, ★ city strip |
| jwt.debug | JWT debugger | ✅ | ★ verify HS/RS/ES/EdDSA, ★ encode & sign |
| regex.test | RegExp tester | ✅ | ★ explanation, ★ cheat sheet, ★ test cases |
| text.diff | Text diff | ✅ | ★ JSON structural diff, ★ two files |
| string.inspect | String inspector | ✅ | |
| html.preview | HTML preview | ✅ | sandboxed, JS off |
| markdown.preview | Markdown preview | ✅ | GFM, highlighting, ★ Mermaid |
| cron.parse | Cron parser | ✅ | ★ builder, ★ Quartz, ★ EventBridge |
| color.convert | Colour converter | ✅ | ★ OKLCH, ★ P3, ★ contrast, ★ palette, ★ code output |
| cert.x509 | X.509 decoder | ✅ | ★ CSR, chain |
| ssh.fingerprint | ★ SSH key fingerprint | ✅ | |
| url.parse | URL parser | ✅ | live-rebuilding query table |
| useragent.parse | ★ User-agent parser | ✅ | |
| http.reference | ★ HTTP status / header reference | ✅ | |
| mime.lookup | ★ MIME type lookup | ✅ | |
| chmod.calc | ★ chmod calculator | ✅ | |
| cidr.calc | ★ CIDR / subnet calculator | ✅ | IPv4 + IPv6 |
| semver.compare | ★ Semver comparator | ✅ | |
| env.inspect | ★ .env inspector | ✅ | |
| hex.viewer | ★ Hex viewer | ✅ | |
| file.checksum | ★ File checksum | ✅ | |
| image.exif | ★ Image metadata viewer | ✅ | |

## 5. Generators
| ID | Tool | Status | Notes |
|----|------|--------|-------|
| id.generate | UUID / ULID / Nano ID / ObjectId | ✅ | v1/v3/v4/v5/★v7, decode |
| hash.generate | Hash generator | ✅ | MD5, SHA-1/2/3, Keccak, ★ BLAKE2/3, ★ CRC32, ★ HMAC, files |
| password.hash | ★ Password hashing | ✅ | bcrypt, scrypt, Argon2id |
| random.string | Random string / password | ✅ | ★ diceware |
| lorem.ipsum | Lorem ipsum | ✅ | classic + tech |
| qr.code | QR generator / reader | ✅ | ★ screen region |
| barcode | ★ Barcode generator / reader | ✅ | |
| fake.data | ★ Fake data generator | ✅ | |
| oauth.pkce | ★ PKCE generator | ✅ | |
| key.generate | ★ Key generation | ✅ | RSA, P-256, Ed25519 |
| aes.gcm | ★ AES-GCM encrypt / decrypt | ✅ | |
| image.placeholder | ★ Placeholder image | ✅ | |
| icon.set | ★ App icon / favicon set | ✅ | |
| gitignore.build | ★ .gitignore builder | ✅ | |

## 6. Images and media ★
| ID | Tool | Status | Notes |
|----|------|--------|-------|
| image.convert | Image convert / resize / compress | ✅ | |
| svg.optimize | SVG optimiser | ✅ | |
| ocr.text | OCR | ✅ | Vision |

## 7–8. Scratchpad, scripts, pipelines ★
| Feature | Status |
|---------|--------|
| Scratchpad window | ⬜ |
| User scripts (JavaScriptCore) + 10 examples | 🚧 (loader + sandboxed runner done; examples and UI pending) |
| Pipelines (visual chain, save, export, hotkey, CLI) | 🚧 (engine + `bl pipe` done; visual editor pending) |

## App-level
| Feature | Status |
|---------|--------|
| Smart detection + "Also try" | 🚧 |
| Three-column layout, fuzzy sidebar, Manage Tools | 🚧 |
| ⌘K palette | ✅ |
| Windows + tabs, state restore | ⬜ |
| Menu bar Quick Panel + global hotkeys | ⬜ |
| Services menu | ⬜ |
| History / favourites / pinned inputs / clipboard history | 🚧 (history, pinned inputs, favourites, usage done; clipboard capture pending) |
| URL scheme | ⬜ |
| App Intents | ✅ (Run Tool, Run Tool (File), Run Pipeline, Detect, Format JSON, Decode Base64/JWT, Unix time, UUID; see Docs/Shortcuts.md) |
| CLI `bl` | 🚧 |
| Raycast + Alfred | ⬜ |
| Quick Look | ⬜ |
| On-device AI (macOS 26+) | ⬜ |
| Settings | 🚧 |
| Onboarding + icon | ⬜ |
| Distribution (Direct + App Store) | ⬜ |

## Custom views
| Tool | View |
|------|------|
| json.format | Text / collapsible tree with search, copy path & value |
| regex.test | Pattern bar, flag chips, live highlights, groups table, replace, explain, cheat sheet |
| text.diff | Side-by-side / unified diff, word-level highlights, folds, change navigation, JSON changes |
| csv.viewer | Sortable, filterable table, column stats, CSV/JSON export |
| html.preview / markdown.preview | Sandboxed offline WebKit preview, highlight.js, Mermaid |
| Image / file / binary tools | Drop zones, image & file cards, binary save cards |
