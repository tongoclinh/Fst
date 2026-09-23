# Releases

Run `just release 0.1.1` from a clean, up-to-date `main` checkout. Like Moves, releases run on your Mac using your existing Keychain credentials. The command tests, builds a universal app, signs with Developer ID, notarizes and staples it, signs the ZIP with Sparkle, creates a version tag, publishes the GitHub release and appcast, and updates `mikker/homebrew-tap`.

You need Xcode 26+, Python 3.11+, `gh`, GitHub SSH access, a Developer ID Application identity, the `TunaNotary` notarization profile, and Fst’s Sparkle key (Keychain account `com.mikker.Fst`). Verify these prerequisites on the machine doing the release; an Apple Development certificate is not a substitute for public distribution. Override `NOTARYTOOL_PROFILE` to use another profile. No GitHub Actions secrets are required. CI only builds and tests pull requests and main.

Release versions are `X.Y.Z` and must increase. The supplied version sets both app version fields. Packaging completes before the tag is pushed. ZIP and appcast assets are uploaded to a draft and published together; published archives are never replaced. Run the same command again to retry a failed release or finish a failed tap update. Do not move published tags.

The tap update uses a temporary checkout and your normal SSH credentials, leaving your existing tap checkout untouched. Keep a secure backup of the Sparkle key and renew the Developer ID certificate before expiry.

`Scripts/package-release.sh 0.1.1` builds and notarizes without publishing. Output is in ignored `dist/`.

Sparkle’s feed is the `appcast.xml` asset of the latest GitHub release; no Pages deployment or separate appcast repository is needed.

## Local Release installation

For a local optimized build without publishing, use [Scripts/agent-build.sh](Scripts/agent-build.sh) with `build -project Fst.xcodeproj -scheme Fst -configuration Release -destination 'platform=macOS'`. If the project's signing team is unavailable, select an installed Apple Development identity and its matching team through command-line `CODE_SIGN_IDENTITY`, `DEVELOPMENT_TEAM`, and `CODE_SIGN_STYLE=Manual` overrides; do not change the shared project to a personal identity. Discover available identities with `security find-identity -v -p codesigning`.

Keep hardened-runtime library validation enabled. Fst and embedded Sparkle must have compatible signing identities: an ad-hoc app with a differently signed Sparkle framework can pass `codesign --verify --deep --strict` yet abort at launch with `mapping process and mapped file (non-platform) have different Team IDs`. Inspect both with `codesign -dv` and verify the complete bundle before installing.

The build output is `build/dd/Build/Products/Release/Fst.app`. Stage a complete copy before replacing `/Applications/Fst.app`, retain the previous bundle for rollback, and avoid modifying a running app bundle in place. Target any running instance by executable path/PID, not just the shared bundle identifier; never force-quit unsaved documents. After installation, launch the exact installed path and confirm startup completes with an editor window. A successful build, signature check, or `open` exit code alone is not launch verification. Local development signing does not provide Developer ID notarization.
