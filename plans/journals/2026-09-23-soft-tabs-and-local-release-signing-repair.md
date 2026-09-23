---
title: Soft tabs and local Release signing repair
date: 2026-09-23
summary: "Whitespace and indentation controls, verification fixes, and the Sparkle signing launch failure."
---

# Soft tabs and local Release signing repair

## Outcome
Added whitespace symbols, per-file indentation detection, soft Tab/Backspace, status-bar indentation selection, and an undoable Tabs → Spaces action. Settings persist whitespace visibility, detection, fallback soft tabs, and default size. Conversion only changes leading tabs; paste and Save preserve existing text. Manual per-file choices override detection, which overrides defaults.

## Decisions
Rejected implicit conversion on save in favor of soft tabs and explicit conversion. Leading tabs may be semantic in Makefiles and multiline strings, so conversion remains a user action. Detection is a bounded heuristic, not a language parser; ambiguous files use defaults. Quick Look typography remains independent.

## Failures and fixes
The first status-bar layout imposed too much minimum width; reduced clipping resistance and assigned visibility priorities. Conversion initially registered edits twice via shouldChangeText plus insertText, breaking one-step undo; fixed with one AppKit change notification boundary and a batched text-storage edit. Native rendering exposed hidden tab control glyphs being skipped; drawing their markers fixed arrows while leaving document bytes unchanged.

The first local Release installation was faulty. Ad-hoc signing passed deep/strict codesign verification, but dyld rejected Sparkle because the app and framework had different Team IDs. The missing launch smoke check was an error in delivery. Rebuilt using an available Apple Development identity and matching team, verified both app/framework team identifiers, replaced the installed bundle atomically, then opened /Applications/Fst.app and observed finishedLaunching=true with an Untitled window. No library-validation bypass was added. This is local signing, not a notarized public release.

## Evidence
Scripts/test.sh passed all checks, including detection for 2/4/8 spaces, soft tab stops, leading-only conversion, Unicode/caret preservation, undo/redo, unchanged saves, and existing regressions. Debug and Release builds succeeded. Native render smoke confirmed dots/arrows and exercised explicit conversion; bitmap capture of native controls was incomplete, so it is not a full Settings interaction test. The separate smoke instance was stopped by its tracked process; the user's other instance was not terminated.

## Follow-through
README.md and Development.md describe the editor controls. RELEASING.md records signing compatibility, safe replacement, instance targeting, and mandatory installed-app launch verification. Retain manual override for heuristic detection; use the existing Developer ID/notarization workflow for public distribution. AgentWiki publish skipped.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
