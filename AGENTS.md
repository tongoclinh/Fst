# Local Release installation

- Before building or replacing `/Applications/Fst.app`, read [RELEASING.md — Local Release installation](RELEASING.md#local-release-installation). Use the verified development-signing procedure, not an ad-hoc fallback when the project team is unavailable.
- Keep hardened-runtime library validation enabled. App, Sparkle and Quick Look must share a compatible signing team; `codesign --verify --deep --strict` alone does not prove the app can launch.
- Stage and replace the complete bundle, preserving rollback and unsaved documents. Never overlay a running installed bundle with `ditto`.
- Before reporting success, launch the exact installed path and confirm startup finishes with an editor window. Build success, signature checks and `open` returning zero are insufficient.
