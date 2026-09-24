# Releases

Run `just release 0.1.1` from a clean, up-to-date `main` checkout. Like Moves, releases run on your Mac using your existing Keychain credentials. The command tests, builds a universal app, signs with Developer ID, notarizes and staples it, signs the ZIP with Sparkle, creates a version tag, publishes the GitHub release and appcast, and updates `mikker/homebrew-tap`.

You need Xcode 26+, Python 3.11+, `gh`, GitHub SSH access, a Developer ID Application identity, the `TunaNotary` notarization profile, and Fst’s Sparkle key (Keychain account `com.mikker.Fst`). Verify these prerequisites on the machine doing the release; an Apple Development certificate is not a substitute for public distribution. Override `NOTARYTOOL_PROFILE` to use another profile. No GitHub Actions secrets are required. CI only builds and tests pull requests and main.

Release versions are `X.Y.Z` and must increase. The supplied version sets both app version fields. Packaging completes before the tag is pushed. ZIP and appcast assets are uploaded to a draft and published together; published archives are never replaced. Run the same command again to retry a failed release or finish a failed tap update. Do not move published tags.

The tap update uses a temporary checkout and your normal SSH credentials, leaving your existing tap checkout untouched. Keep a secure backup of the Sparkle key and renew the Developer ID certificate before expiry.

`Scripts/package-release.sh 0.1.1` builds and notarizes without publishing. Output is in ignored `dist/`.

Sparkle’s feed is the `appcast.xml` asset of the latest GitHub release; no Pages deployment or separate appcast repository is needed.

## Local Release installation

For a local optimized build without publishing, use [Scripts/agent-build.sh](Scripts/agent-build.sh) with `build -project Fst.xcodeproj -scheme Fst -configuration Release -destination 'platform=macOS'`. If the project's signing team is unavailable, select an installed Apple Development identity and its matching team through command-line `CODE_SIGN_IDENTITY`, `DEVELOPMENT_TEAM`, and `CODE_SIGN_STYLE=Manual` overrides; do not change the shared project to a personal identity. Discover available identities with `security find-identity -v -p codesigning`.

The following override has been verified on this workstation. The identity hash is a certificate selector, not a private key; confirm it still appears in `security find-identity -v -p codesigning` before reusing it. On another machine, select its available development identity and actual signing team instead.

```sh
Scripts/agent-build.sh build \
  -project Fst.xcodeproj -scheme Fst -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=42XUBQNRUN \
  CODE_SIGN_IDENTITY=9B3B8886011F3B835DAD0FE610EDCF759CCBAE0A
```

Do not fall back to `CODE_SIGN_IDENTITY=-` or `CODE_SIGNING_ALLOWED=NO` for an app being installed in `/Applications`. If the default project team fails, use the development override above rather than assuming no usable certificate exists. `just` is optional: invoke `Scripts/agent-build.sh` directly when it is unavailable.

Keep hardened-runtime library validation enabled. Fst and embedded Sparkle must have compatible signing identities: an ad-hoc app with a differently signed Sparkle framework can pass `codesign --verify --deep --strict` yet abort at launch with `mapping process and mapped file (non-platform) have different Team IDs`. Inspect both with `codesign -dv` and verify the complete bundle before installing.

The build output is `build/dd/Build/Products/Release/Fst.app`. Stage a complete copy before replacing `/Applications/Fst.app`, retain the previous bundle for rollback, and avoid modifying a running app bundle in place. Target any running instance by executable path/PID, not just the shared bundle identifier; never force-quit unsaved documents. After installation, launch the exact installed path and confirm startup completes with an editor window. A successful build, signature check, or `open` exit code alone is not launch verification. Local development signing does not provide Developer ID notarization.

Before installation, inspect all three signatures; their `TeamIdentifier` must match the selected team:

```sh
codesign -dv build/dd/Build/Products/Release/Fst.app
codesign -dv build/dd/Build/Products/Release/Fst.app/Contents/Frameworks/Sparkle.framework
codesign -dv build/dd/Build/Products/Release/Fst.app/Contents/PlugIns/FstQuickLook.appex
codesign --verify --deep --strict build/dd/Build/Products/Release/Fst.app
```

After replacing the bundle, register the installed Quick Look extension and launch the exact installed app:

```sh
pluginkit -a /Applications/Fst.app/Contents/PlugIns/FstQuickLook.appex
pluginkit -e use -i com.mikker.Fst.QuickLook
open -a /Applications/Fst.app
```

Do not report installation complete until the running instance resolves to `/Applications/Fst.app`, `NSRunningApplication.isFinishedLaunching` is true, and an editor window exists. If launch fails, inspect the newest `~/Library/Logs/DiagnosticReports/Fst-*.ips`; a DYLD rejection mentioning Sparkle and `different Team IDs` requires compatible signing, not disabling library validation.
