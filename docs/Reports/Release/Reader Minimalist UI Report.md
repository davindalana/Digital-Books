# Digital Books — Minimalist Reader UI Acceptance Audit

**Audit date:** 2026-11-12
**Native verification date:** 2026-11-13
**Implementation under review:** `f3e273f` and following Reader toolbar refinements
**Audited HEAD:** `ac846ba` plus the local spacing/auto-hide changes
**Verdict:** **CONDITIONAL PASS**

## Summary

The Reader changes remain in the current branch. The full automated test suite, static analysis, formatting check, whitespace check, and a fresh native macOS debug build all completed successfully. The current app also launched and its Library screen rendered with existing local book data.

The original audit could not inspect the native Reader. A follow-up on 2026-11-13 quit the stale app instance, rebuilt the bundle, and verified the Reader in the running macOS app at compact, standard, and expansive window sizes. Page margins, the 80 pt top inset, toolbar auto-hide, and the native traffic-light show/hide lifecycle were observed directly. The table-of-contents and search dialogs could not be driven reliably with synthesized clicks, and annotation/highlight flows were not exercised, so the overall verdict remains **CONDITIONAL PASS**.

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

## Follow-up page-spacing refinement

After the audit above, the reading canvas was adjusted to address the page composition shown in the user's screenshots:

- On macOS, the Reader body now starts 80 pt below the top edge, keeping book content clear of the native title-bar controls even while the Flutter toolbar auto-hides.
- Reflowable page margins now use a shared rule: 48 pt minimum for page widths from 400–649 pt, and 56 pt minimum for wider pages. Compact pages below 400 pt keep the existing 18 pt minimum. Paginated, scrolling, and pagination measurement use the same margin helper.
- Page content now has a 24 pt vertical inset, and pagination height calculations use the same value so the extra top and bottom breathing room does not clip text.
- A macOS method channel now hides the native close/minimize/zoom buttons with the Reader toolbar, reveals them on top-edge hover, and restores them when leaving the Reader.
- Entering the Reader now asserts the native chrome state (`initState`) so a hot restart or abnormal exit cannot leave the traffic lights hidden.
- Existing geometry expectations were updated to the new page widths.

## Root cause of the stale screenshot

The app instance that produced the user's screenshot had been started on 2026-11-12 at 22:26:27. The Debug bundle it was running from was produced at 22:49, and the Swift title-bar change was written at 22:45. The running process therefore predated both the Swift change and the bundle rebuild, so the screenshot showed older code. This was confirmed by process start time and file timestamps, not inferred from appearance. Quitting that instance and launching the freshly built bundle is required for native Swift changes to take effect.

During the audit, launching the app twice also produced a permanent Library spinner; the spinner disappeared once only one instance was left running. Two instances sharing the same Drift/SQLite database is the probable cause and is an operational limitation, not part of this change.

## Native verification (2026-11-13)

A fresh `flutter build macos --debug` was produced at 04:54:10 (`kernel_blob.bin`), newer than the 04:47 source edit. The stale instance was quit and the new bundle was launched from `build/macos/Build/Products/Debug/Digital Books.app`.

Captures below are real window captures taken with `screencapture -x -l <windowID>` (and `-o` for the shadow-free set). They are native app evidence, not `testWidgets` / `RepaintBoundary` captures.

| Evidence | Observed result |
|---|---|
| `/tmp/native_06_reader_top_hover.png` | 800×600 Book mode. Top-edge hover revealed the Flutter toolbar and the real AppKit traffic lights on the same centerline, with no overlap between the buttons and the back control. |
| `/tmp/native_07_reader_autohide.png` | Pointer moved into the page; after the 3.2 s timer the toolbar and the native traffic lights were both gone. This frame is pixel-identical to the pre-hover hidden frame. |
| `/tmp/native_08_hidden_again.png` | Bottom-edge hover revealed both bars together, with the native buttons visible. |
| `/tmp/native_15_book_mode_standard.png` | 1100×760 Book mode, two-column spread. Clear outer margins and 48 pt gutter, no clipped line, footer page numbers and bottom progress bar present. |
| `/tmp/native_16_book_autohide_standard.png` | Same window with controls auto-hidden: no traffic lights, no text in the 80 pt title-bar band. |
| `/tmp/native_17_book_expansive.png` | 1400×900 Book mode. Wider columns, margins still generous, anchored TOC line retained after re-pagination. |
| `/tmp/native_18_prose_expansive.png` | Prose page at 1400×900 after resize and page navigation. No clipping at column edges. |
| `/tmp/native_19_compact_prose.png` | Back to 800×600; single-page layout, 56 pt-class margins, the same paragraph remains at the top of the page. |
| `/tmp/native_36_toc_try.png` | PDF mode at 800×600 with toolbar and traffic lights visible, scanned spread intact. |
| `/tmp/native_42_library_after_escape.png` | After leaving the Reader with Escape, the Library is shown with all three native traffic lights restored. |

Measured layout facts from the native captures and the shared geometry code:

- At 1100 pt wide, two-page spread: each page is 526 pt; the 48 pt inset yields 430 pt of text; the spread is centered so body text begins ~96 pt from the window edge.
- At 1400 pt wide: each page is 676 pt; the 56 pt inset yields 564 pt of text, beginning ~112 pt from the window edge.
- At 800 pt wide, single page: 56 pt inset, ~688 pt text column (capped at 680 pt).
- Available height at a 700 pt viewport is 600 pt (`700 − 2×24 − 28 − 24`), matching the renderer's padding (24 pt + 28 pt header + 24 pt footer).

Interactions actually verified natively:

- Space bar turned the page (page footer advanced).
- Left-edge pointer zone turned back a page.
- Clicking an empty page area toggled the toolbar; auto-hide then removed both the toolbar and the traffic lights.
- Top-edge and bottom-edge hover revealed the toolbar, with the native buttons, at least once each (captured).
- Minimize was clicked and the window minimized (`kAXMinimized = 1`), then restored.
- `Book`/`PDF` mode switching worked with a toolbar click at 1100 pt width.
- Back navigation exited to the Library, and the traffic lights were restored.

Interactions not verified natively:

- The table-of-contents and search dialogs. Synthesized clicks on those Material toolbar icons did not open them reliably after the window was re-activated; the first click of a sequence was sometimes consumed as window activation, and clicks aimed at the toolbar while it was hidden landed in the 80 pt empty top inset. These dialogs therefore remain covered only by automated tests.
- Text selection, highlight creation, annotation editing, and bookmark actions.
- Trackpad scroll inertia and multi-touch gestures.

## Automated verification after the changes

| Check | Actual result |
|---|---|
| `flutter test --reporter expanded` | **646 passed, 2 skipped, 0 failed; exit code 0** |
| `flutter analyze` | **No issues found; exit code 0** |
| `dart format --output=none --set-exit-if-changed lib test` | **207 files, 0 changed; exit code 0** |
| `git diff --check` | **Clean; exit code 0** |
| `flutter build macos --debug` | **Built successfully; exit code 0** |

The suite regenerates tracked PNGs under `docs/visual_evidence/`; those test-generated changes were reverted so the commit contains no regenerated widget screenshots.

## User data safety

The user database was snapshotted after quitting the stale app and before launching the new build (`/tmp/digital_books_db.baseline.sqlite`, SHA-256 `16167e4cab69be494e8ee5099bc5d557e80c5d0b9915549bae2c5eb23a70e7e4`). The app wrote progress during the audit, so the database was restored from that snapshot afterwards and the SHA-256 was verified to match. All 19 files under `~/Documents/DigitalBooks` (book artifacts and originals) had identical SHA-256 hashes before and after the audit.

## Performance

No FPS, memory, or frame-time claim is made. Resize re-pagination and page turns were observed visually but were not benchmarked.

## Known limitations

- Native dialog acceptance (TOC/search, annotation and highlight flows) is still incomplete.
- Native input was synthesized with CoreGraphics events; the first click after re-activation can be consumed by macOS, which limits repeatable click-through testing.
- The 80 pt macOS title-bar inset is a fixed value; very large accessibility text in the top toolbar was not exercised natively.

## Acceptance

**CONDITIONAL PASS — the spacing, auto-hide, and native traffic-light behavior were verified in the rebuilt macOS app, and static checks plus the full suite pass. Native dialog and annotation flows remain unverified, so an overall PASS is not claimed.**

The evidence in `/tmp/native_*.png` is native window capture. The images under `docs/visual_evidence/minimalist_ui/` remain `testWidgets` / `RepaintBoundary` captures and must not be cited as native proof; in particular, the drawn traffic-light circles in screenshot 13 are not AppKit buttons.
