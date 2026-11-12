# Digital Books — Minimalist Reader UI Acceptance Audit

**Audit date:** 2026-11-12
**Implementation under review:** `f3e273f` and following Reader toolbar refinements
**Audited HEAD:** `bccbbac`
**Verdict:** **CONDITIONAL PASS**

## Summary

The Reader changes remain in the current branch. The full automated test suite, static analysis, formatting check, whitespace check, and a fresh native macOS debug build all completed successfully. The current app also launched and its Library screen rendered with existing local book data.

The native Reader itself and its pointer/keyboard interactions could not be manually accepted in this run. The computer-use interface returned `noWindowsAvailable` for click actions, even though it could read the app's accessibility tree and capture the Library window. Therefore this audit does not claim native Reader acceptance or an overall PASS.

## Scope and root cause under review

The Reader refinement addresses three reported UI problems: the old floating top toolbar covered reading content, the large bottom control card reduced reading space, and always-visible navigation arrows distracted from the page. macOS title-bar integration and auto-hide behavior were also introduced.

This run audited the current repository state and test/build evidence. It did not change Reader behavior or user data.

## Automated verification

Commands were run on `bccbbac`:

| Check | Actual result |
|---|---|
| `flutter test --reporter expanded` | **645 passed, 2 skipped, 0 failed; exit code 0** |
| `flutter analyze` | **No issues found; exit code 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **207 files, 0 changed; exit code 0** |
| `git diff --check` | **Clean; exit code 0** |
| `flutter build macos --debug` | **Built successfully; exit code 0** |

The test run printed `google_fonts` runtime-fetch errors for Literata because requests to `fonts.gstatic.com` failed. The suite still exited successfully and reported two optional corpus skips. The macOS build printed linker warnings for a missing Metal toolchain search path, but completed successfully.

Tests are automated Flutter tests; they are not a substitute for native GUI acceptance.

## Native visual inspection

- Launched the freshly built app at `build/macos/Build/Products/Debug/Digital Books.app`.
- Confirmed the real macOS app window opened and the Library screen rendered populated local data.
- Could not click `Lanjutkan` or otherwise interact with the window: the UI automation returned `noWindowsAvailable` on click attempts. The Reader screen was consequently not inspected in the native app.
- Existing images in `docs/visual_evidence/minimalist_ui/` are produced by `test/reader_minimalist_visual_capture_test.dart`, which uses `testWidgets`, an in-memory database, and a Flutter `RepaintBoundary`. They are widget captures, not screenshots of the running native macOS window.
- In particular, screenshot 13 draws three colored circles in Flutter to represent traffic lights. It does not capture or measure AppKit's native traffic-light buttons.

For that reason, the 13 existing images and geometry assertions can support widget-level layout checks only. They do not prove native title-bar alignment, real window resizing, text clearance in the running app, or that the reading canvas is unobstructed.

## Interaction checks not completed

These checks remain open because native input was unavailable:

- Auto-hide and top/bottom edge hover in the running macOS app.
- Book and PDF modes in the running app.
- Text selection, highlight creation, annotation editing, and bookmark interaction.
- Search and table-of-contents dialogs.
- Trackpad scrolling and keyboard navigation.
- Window dragging, especially the effect of `isMovableByWindowBackground = true` on controls.
- Compact, standard, and expansive native window resizing.
- Actual text intersection with the top toolbar and bottom progress bar.

No screenshots were added or replaced in this audit. No application records were intentionally edited. The working tree was clean after tests and build.

## Acceptance

**CONDITIONAL PASS — automated checks and native build passed; native Reader acceptance remains unverified.**

Do not treat prior PASS wording or widget screenshots as evidence of manual native acceptance. To close this audit, repeat the listed visual and interaction checks in the actual macOS app, capture the Reader at matched window sizes, and record the observed results here.
