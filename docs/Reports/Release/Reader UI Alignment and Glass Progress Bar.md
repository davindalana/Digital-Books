# Reader UI Alignment and Glass Progress Bar

Date: 2026-11-13

## Changes

- Centered the reflowable chapter running head and placed it flush with the top edge of the page.
- Increased the bottom reading progress bar height, softened its translucent surface, and constrained the chapter/progress label so it cannot crowd the scrubber.
- Aligned the Library section heading with the content card, adjusted the sidebar brand against the macOS traffic lights, and lowered the Add Book action.
- Let reader content render behind the transparent macOS title bar and top-aligned two-page PDF spreads to remove the large black band above the pages.
- Replaced Indonesian user-facing copy in the Library and Reader flows with English. Book metadata and document text remain unchanged.

## Verification

- `flutter analyze`: passed with no issues.
- `git diff --check`: passed.
- Library shell/responsive tests: 7 passed.
- PDF error/loading test: 1 passed.
- Spread-toggle reader test: 1 passed.
- `flutter build macos --debug`: succeeded. Xcode emitted non-fatal warnings about an unavailable Metal toolchain search path.
- Follow-up verification: `phase_2_2_reader_ui_test.dart` (8 passed), `reader_typography_refinement_test.dart` (8 passed), `library_shell_and_sidebar_responsive_test.dart` (6 passed), `flutter analyze`, and a fresh macOS debug build all passed.
- Full `flutter test`: did not pass. The suite reported failures including stale Indonesian text expectations and Google Fonts requests for Literata failing to load from `fonts.gstatic.com`. Test-generated visual evidence was restored after the run; the full suite was not rerun after updating the affected label expectations.

Native visual acceptance in the rebuilt app remains to be performed manually; restart the running app to load the latest build.
