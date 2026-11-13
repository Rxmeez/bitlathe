# Quick Look extension

`BitlatheQuickLook` is a view-based Quick Look preview extension (`com.apple.quicklook.preview`) embedded in
`Bitlathe.app/Contents/PlugIns`. Select a file in Finder and press Space.

| File | Preview |
| --- | --- |
| `.jwt`, or a file whose content is a JWT | Claims summary (iss, sub, aud, exp, nbf, iat, jti) with an expiry badge, plus tinted header and payload JSON. `alg=none` is flagged. |
| `.pem` `.crt` `.cer` `.der` | Subject, issuer, validity (Expired / Expires soon / Valid badge), SANs, key, signature algorithm, serial, SHA-256 and SHA-1 fingerprints. Chains show every certificate. Private keys in a PEM are skipped, never shown. |
| `.csr` `.p10` | Certificate request summary (subject, key, SANs, attributes). |
| `.json` `.jsonc` `.json5` | Pretty-printed, syntax-tinted. Comments and trailing commas are accepted. Invalid input is shown verbatim with a notice. |
| `.yaml` `.yml` | Re-indented, syntax-tinted YAML (multi-document streams are separated by `---`). |

## Implementation

- Sources: `QuickLook/` (controller, view model builder, SwiftUI views). Parsing reuses `JWTTool.decode`, `X509`,
  `PEM`, `JSONParser`/`JSONSerializer` and the YAML bridge (via `QuickLookSupport.prettyYAML`) from the Bitlathe package.
- Sandbox: `com.apple.security.app-sandbox` plus `files.user-selected.read-only`. No network.
- Light and dark mode follow the system; syntax colours come from the default editor theme.
- Files are read up to 8 MB; displayed code is capped at 300k characters.
- Types: `com.bitlathe.jwt` (`.jwt`), `com.bitlathe.json5` (`.json5`, `.jsonc`, conforms to `public.json`) and
  `com.bitlathe.csr` (`.csr`, `.p10`) are exported by the app's Info.plist. System types used: `public.json`,
  `public.yaml`, `public.x509-certificate` (which macOS already maps to `.pem`, `.crt`, `.cer`, `.der`).

## Limits

- For `.pem`/`.crt`/`.cer`/`.der`, macOS ships its own Quick Look generator for `public.x509-certificate`, and on the
  test machine (macOS 27) the system preview won over this extension (qlmanage showed Apple's certificate view).
  The certificate/chain renderer is implemented (`PreviewBuilder.certificates`) but is only reached for certificate
  files the system does not claim, or via content sniffing. `.csr` has no system type and is handled by Bitlathe.

- The extension does not claim `public.plain-text`, so a JWT saved as `token.txt` is not previewed (claiming all text
  would hijack every text preview). The content sniffing applies to files that reach the extension via another type.
- Quick Look only loads extensions from an app that macOS has registered. A development build must be launched once
  (or `pluginkit -a Bitlathe.app/Contents/PlugIns/BitlatheQuickLook.appex`), then `qlmanage -r` to reset caches.
  Ad-hoc signed builds may be refused by the system; see the verification notes in the commit.
