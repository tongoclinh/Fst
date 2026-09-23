---
title: Active indent guides and verified local installation
date: 2026-09-23
summary: "Indentation-only block guides, native rendering checks, and signed Release installation."
---

# Active indent guides and verified local installation

## Outcome
Implemented indentation guides and a brighter guide for the nearest block containing the caret. No block background, folding, or syntax parser was added. Settings expose independent Show indent guides and Highlight active indent guide toggles, both enabled by default; turning guides off retains the highlight preference.

## Design and limits
IndentGuideIndex caches visual indentation columns and nested block spans. Tabs expand to tab stops; opener lines select the block they open. Interior blanks inherit surviving context, sibling blocks remain separate, and trailing EOF blanks do not extend blocks. WhitespaceLayoutManager draws visible fragments only and skips wrapped continuations to avoid drawing over text. Caret selection uses a binary line lookup and cached block identity. Content edits rebuild the model across logical lines; this deliberately simple approach may need incremental repair for large-file typing. Indentation remains a visual heuristic, not semantic scope.

## Verification
Scripts/test.sh passed the new nested/sibling, opener/body, blank-line, EOF, edit-refresh and mixed-tab checks plus existing regressions. A temporary native AppKit document smoke exercised guides on/off, active highlight on/off, wrapping, scrolling, and unchanged saved bytes. Rendered light/dark images confirmed the active guide stops at the sibling boundary and bridges the internal blank. Offscreen bitmap captures do not prove every native Settings interaction. Temporary smoke source and binary were removed.

Signed Debug and Release builds succeeded. Installed the Release bundle at /Applications/Fst.app through staging and atomic replacement, preserving the previous bundle. Verified app and Sparkle share the signing team and the staged bundle passes deep/strict signature verification. Launched the exact installed binary as a tracked smoke process; observed finishedLaunching=true and editor windows. The close request exited that smoke process with code 0. No other instance was terminated. Local Apple Development signing is not public notarization.

## Documentation and next steps
README.md lists active indent guides; Development.md owns behavior, limits, and source links. No public release or push was requested. AgentWiki publish skipped.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
