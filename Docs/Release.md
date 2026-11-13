# Releasing Bitlathe

Two app targets share every source file:

| | Scheme | Distribution | Sparkle | `bl` CLI inside app | Compile flag |
|---|---|---|---|---|---|
| Direct | `Bitlathe` | Developer ID, notarised, DMG, Homebrew cask, GitHub release | yes | yes (`Contents/Helpers/bl`) | `DIRECT_DISTRIBUTION` |
| App Store | `Bitlathe-AppStore` | Mac App Store | no | no | `APP_STORE` |

The App Store build has no embedded `bl`: a sandbox-inheriting helper crashes once copied outside the app, and a
non-sandboxed one fails App Store validation. Its Integrations pane should show `CLIInstaller.unavailableMessage`
(`brew install --cask bitlathe` or the GitHub download). The Updates settings tab only exists in the Direct build.

## Versioning

`MARKETING_VERSION` (semver, shown to users) and `CURRENT_PROJECT_VERSION` (integer build, must increase on every
upload and is what Sparkle compares) live in `project.yml`. `scripts/release.sh 1.2.0` sets the marketing version and
increments the build number (override with `BUILD_NUMBER=42`). Tag is `v1.2.0`.

## One-time setup

1. Apple Developer Program membership; note the 10-character **Team ID** (`TEAM_ID`).
2. Certificates in the login keychain: *Developer ID Application* (Direct) and *Apple Distribution* + *Mac Installer
   Distribution* (App Store, Xcode can create these). `DEVELOPER_ID` is the full name, e.g.
   `Developer ID Application: Your Name (ABCDE12345)`.
3. Notary credentials, stored once in the keychain:
   `xcrun notarytool store-credentials "bitlathe-notary" --apple-id you@example.com --team-id ABCDE12345 --password <app-specific password>`
   then `export NOTARY_PROFILE=bitlathe-notary`.
4. Sparkle signing key: build the Direct scheme once (SwiftPM fetches Sparkle), then run
   `.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`. It stores the private key in the
   keychain and prints the public key. Put the public key in `project.yml` as `SU_PUBLIC_ED_KEY` (target `Bitlathe`).
   Without it the Direct app runs but its update checks are disabled (the Updates tab says so). Back up the private key:
   `generate_keys -x file`.
5. Feed URL: `SU_FEED_URL` in `project.yml` defaults to
   `https://github.com/Rxmeez/bitlathe/releases/latest/download/appcast.xml`, so the appcast is a release asset.
6. `gh auth login` for GitHub releases; `brew install create-dmg`.

## Secrets and environment

| Variable | Used by | Meaning |
|---|---|---|
| `TEAM_ID` | archive, export | Apple team; without it archives are ad-hoc and exports are unsigned (local testing only) |
| `DEVELOPER_ID` | dmg | codesigns the dmg |
| `NOTARY_PROFILE` | notarize | notarytool keychain profile; without it the step stops (exit 2) |
| `SPARKLE_BIN` | appcast | folder containing `generate_appcast` (found automatically in the SwiftPM artifacts) |
| `GITHUB_REPO` | release | default `Rxmeez/bitlathe` |
| `ALLOW_UNSIGNED=1` | release | allow publishing an unsigned dmg (pre-release tests only) |

In CI, import the certificates into a temporary keychain and pass the same variables as encrypted secrets
(certificate .p12 + password, notary Apple ID / team / app-specific password, Sparkle private key).

## Commands

```
make generate                  # xcodegen
scripts/build.sh direct|appstore|all [Debug|Release]
scripts/test.sh [--quick]      # swift test, bl build, both schemes
scripts/archive.sh direct|appstore|all     # universal arm64 + x86_64 -> build/archives/*.xcarchive
scripts/export.sh  direct|appstore|all     # build/export/<scheme>/
scripts/notarize.sh build/export/Bitlathe/Bitlathe.app    # submit, wait, staple
scripts/dmg.sh                             # build/dmg/Bitlathe-<version>.dmg
scripts/release.sh 1.2.0 [--skip-bump|archive|export|notarize|dmg|appcast|cask|github|appstore] [--dry-run]
scripts/install-cli.sh [--dest DIR] [--symlink]
```

`make` equivalents: `archive`, `export`, `notarize`, `dmg`, `install-cli`, `release VERSION=1.2.0 STEPS="--skip-github"`.

## Direct release, step by step

1. `scripts/release.sh X.Y.Z` bumps the version, archives and exports both schemes, notarises and staples the app,
   builds the dmg, notarises and staples it, generates the appcast with Sparkle's `generate_appcast`, rewrites
   `Distribution/homebrew/bitlathe.rb` (version and sha256) and creates the GitHub release `vX.Y.Z` with the dmg and
   `appcast.xml`. Each step can be skipped.
2. Commit the `project.yml` and cask changes. Copy the cask to the tap (`Rxmeez/homebrew-tap`, `Casks/bitlathe.rb`).
3. Smoke test: download the dmg on another Mac, open it (Gatekeeper must not warn), and check Settings > Updates.

Without credentials the pipeline stops cleanly: `notarize` and `github` print what is missing and exit with status 2.
`scripts/release.sh X.Y.Z --skip-notarize --skip-github` produces an unsigned dmg for local testing, marked with
`build/dmg/UNSIGNED` so it can never be published by accident.

## App Store release

1. Create the app record in App Store Connect (bundle id `com.bitlathe.app`).
2. `TEAM_ID=... scripts/archive.sh appstore && TEAM_ID=... scripts/export.sh appstore`.
3. Upload with Transporter (or Xcode Organizer > Distribute App). Increase the build number each upload.
4. The app is sandboxed with user-selected read/write, bookmarks, print and the network-client entitlement WebKit needs
   (see `Docs/Decisions.md`). It has no Sparkle and no Apple-Events exceptions beyond the Info.plist text.

## Notes

- The Direct target embeds `bl` via the `scripts/embed-cli.sh` build phase (`swift build -c release --product bl`,
  universal in Release, signed with the app identity). It disables user-script sandboxing for that target.
- Sparkle in a sandboxed app needs the installer launcher service and two mach-lookup exceptions
  (`<bundle id>-spks`, `<bundle id>-spki`); both are in `project.yml`.
- The DMG background is generated by `scripts/make-dmg-background.sh` into `Distribution/dmg-background.tiff`.
- `Distribution/appcast.xml.template` documents the appcast format and is the manual fallback.
