# Reader UI Alignment and Glass Progress Bar

Date: 2026-11-13

## Changes

- Centered the reflowable chapter running head and placed it flush with the top edge of the page.
- Increased the bottom reading progress bar height, softened its translucent surface, and constrained the chapter/progress label so it cannot crowd the scrubber.
- Centered the Library section heading within the available header space and vertically aligned the sidebar brand with the title bar.
- Replaced Indonesian user-facing copy in the Library and Reader flows with English. Book metadata and document text remain unchanged.

## Verification

- `flutter analyze`: passed with no issues.
- `git diff --check`: passed.
- Library shell/responsive tests: 7 passed.
- PDF error/loading test: 1 passed.
- Spread-toggle reader test: 1 passed.
- `flutter build macos --debug`: succeeded. Xcode emitted non-fatal warnings about an unavailable Metal toolchain search path.
- Full `flutter test`: did not pass. The suite reported failures including stale Indonesian text expectations and Google Fonts requests for Literata failing to load from `fonts.gstatic.com`. Test-generated visual evidence was restored after the run; the full suite was not rerun after updating the affected label expectations.

Native visual acceptance in the rebuilt app remains to be performed manually.
