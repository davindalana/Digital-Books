# Phase 3.8 Artifact Integrity Report

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus I — Core Engine & Document Pipeline (v1.0 s.d. v1.1)
> - **Modul / Kategori**: Phase 3.8 Processed Artifact Integrity & Self-Contained Bundle Storage
> - **Urutan Dokumen**: 03 Phase 3.8 Artifact Integrity Report
> - **Tanggal**: 11 November 2026
> - **Status Verifikasi**: **CONDITIONAL PASS**

---

**Project**: Digital Books (local-first hybrid PDF library)<br>
**Date**: 11 November 2026<br>
**Base commit**: `084e201` — `docs(release): add Phase 3.7 independent audit report and mark Phase 3.6 superseded`<br>
**Branch**: `main` (3 unpushed Phase 3.7 commits at start)<br>
**Pipeline version introduced**: `3.8.0` (artifact schema `2`)<br>
**Verdict**: **CONDITIONAL PASS**

---

## 1. Summary

Phase 3.8 addressed the product-quality defects that Phase 3.7 left open:

1. **Stale processed artifacts** were invisible and could not be refreshed safely. Every new Book Mode artifact now records a pipeline version, artifact schema version, source size/hash, page count, and OCR page count. The library shows whether an artifact is current, stale, incomplete, unreadable, or newer than the running app, and can rebuild it without touching the original PDF.
2. **Real-book tests silently passed when fixtures were missing.** The new Phase 3.8 suites fail explicitly for mandatory fixtures and use `markTestSkipped` for optional ones. The previously silent `return`s were converted to explicit skips.
3. **TOC leakage and duplicated/misplaced chapter titles** were reproduced on a real book and fixed at the classifier/reconstructor level, not with book-specific rules.
4. **OCR output was implicitly trusted.** OCR readiness is now an explicit gate (`pending`, `inProgress`, `failed`, `insufficientQuality`, `ready`, `notRequired`) and Book Mode is not advertised as reliable when the gate is not satisfied.
5. **Native macOS acceptance** was attempted. The app builds and launches, but screen capture and UI automation are blocked by macOS permissions; this report does not claim manual acceptance.

Verdict is **CONDITIONAL PASS**: data-integrity work is covered by automated tests, but OCR quality for the three scanned books and native GUI acceptance remain unverified, and annotation remapping is heuristic.

---

## 2. Root Causes

### 2.1 Stale artifacts had no provenance

`BookDocument.metadata` had no pipeline identifier. The only signal was incidental shape differences, so the reader could not distinguish:

- an artifact produced by the current pipeline,
- an artifact produced before chapter/heading work,
- an artifact whose source PDF had since changed,
- an artifact left incomplete by a failed OCR run.

The library displayed `Tersedia (OCR Selesai)` for any non-null `processedBookPath`, including incomplete derivatives. There was no reprocess path at all, so the only recovery was deleting and re-importing the book — which risks losing annotations and reading progress.

### 2.2 Real-book tests could pass by doing nothing

Eight test files used this pattern:

```dart
if (!realBook.existsSync()) {
  print('Skipping ...');
  return;   // the test body never runs and is reported as PASS
}
```

`flutter test` reports the test as passing, so "500 passed" in Phase 3.7 overstated real-book coverage. Missing fixtures never failed the suite and never appeared as skipped.

### 2.3 TOC pages were promoted to chapters

`SemanticDocumentReconstructor._buildChapters` promotes **every** `heading1` block to a chapter boundary. `SemanticClassifier` is responsible for demoting table-of-contents lines, but its detector was fragile:

- The header match was `^(daftar isi|table of contents|contents)\b`. Spacing-based extraction produced `T able of Contents` (split word), so the header did not match.
- A continuation page without a header was only recognised if it had three or more named chapter labels. *The Let Them Theory* has two (`Introduction`, `Conclusion`), so page 11 was classified as body text and its two TOC entries became chapters 1 and 2.
- The saved *Laut Bercerita* artifact contains a one-block `Daftar Isi` chapter plus TOC fragments promoted to tiny `Prolog` / `Ucapan Terima Kasih` chapters and a sentence fragment used as a chapter title.

### 2.4 Roman glyphs inside an arabic chapter sequence

`The Let Them Theory` produced `CHAPTER II` between `CHAPTER 10` and `CHAPTER 12`. The PDF's font maps the lining figures to roman glyphs. The chapter title is a single isolated anomaly inside an otherwise consecutive arabic sequence, which is detectable without book-specific rules.

### 2.5 OCR had no quality contract

`OcrSemanticPipeline` reconstructed Book Mode from whatever completed OCR pages existed. A book with 3 of 300 pages OCR'd, or with near-empty pages, could be presented as a finished reflowable book even though the original PDF was still the only reliable view.

---

## 3. Processed Artifact Versioning Design

### 3.1 Manifest contract

`lib/features/processing/models/processing_manifest.dart` defines:

| Field | Meaning |
| --- | --- |
| `pipelineVersion` | Algorithm version that produced the artifact. Current: `3.8.0`. |
| `artifactSchemaVersion` | Persisted metadata contract version. Current: `2`. |
| `processedAt` | Timestamp of the producing run. |
| `processingSource` | `nativeText` or `ocr`. |
| `sourceFileHash` | SHA-256 of the original PDF, when known. |
| `sourceFileSize` | Byte size of the original PDF. |
| `sourceTotalPages` | Page count at processing time. |
| `ocrCompletedPages` | OCR pages used, for scanned derivatives. |

`ReconstructedDocument.toBookDocument()` always writes the manifest. Callers can add data (`sourceFileHash`, `sourceFileSize`) and declare `processingSource: 'ocr'` when OCR was actually consumed. The manifest is additive: older artifacts keep working.

### 3.2 Freshness states

`ProcessedArtifactInspector` classifies an artifact as:

| State | Condition | Needs reprocess |
| --- | --- | --- |
| `current` | Schema and pipeline match, artifact readable | No |
| `stale` | No manifest, older schema, older pipeline, changed source size, changed source hash (when verified) | Yes |
| `incomplete` | No chapters/blocks, `processingStatus` is `requiresOcr` or `reconstructionFailed` | Yes |
| `unreadable` | File missing or not valid Book Mode JSON | Yes |
| `missing` | No processed document | Yes (first build) |
| `newer` | Artifact schema/pipeline newer than the app | No (never downgraded) |

Source-hash verification is opt-in (`verifySourceHash`) because hashing a 66 MB PDF on every book-details open is wasteful; size checking is always-on and cheap.

---

## 4. Migration and Reprocessing Behaviour

There is no schema migration: the manifest lives inside the existing JSON artifact. Existing artifacts are detected as `stale` on first inspection and remain readable until the user or the pipeline rebuilds them.

`BookReprocessor.reprocess()` performs:

1. **Recovery first** — `recoverInterrupted` resolves `.bak`/`.tmp`/`.reprocess` files left by an earlier crash.
2. **Freshness check** — a `current` artifact returns `alreadyCurrent` unless `force` is set, so opening details repeatedly does not reprocess.
3. **Source check** — a missing original PDF returns `missingSource`; nothing is written.
4. **Rebuild** — `BookDocumentRebuilder` re-extracts native text (scanned books reuse completed OCR pages; with no OCR pages it returns `null` rather than inventing content).
5. **Validation before replacement**:
   - candidate must have chapters and readable text,
   - candidate must not be `requiresOcr` / `reconstructionFailed`,
   - candidate may not lose more than 50% of the previous text blocks unless `force`.
6. **Atomic file swap** — old bytes are written to `.bak`, a `.reprocess` marker records the phase (`prepared`), and the new JSON is written through `writeFileAtomic` (temp file + rename).
7. **Single DB transaction** — new chapters, remapped bookmarks/highlights, and remapped reading progress commit together (`DatabaseService.applyReprocessingUpdates`).
8. **Commit marker** — the marker is updated to `phase: committed`; only then are `.bak` and the marker removed.
9. **Rollback** — any exception restores the old bytes from memory/`.bak`, removes the marker, and returns `failed` with `rolledBack: true`.

Recovery semantics follow the marker phase:

- `prepared` (uncommitted) + backup → restore the old artifact, because the database may still hold old anchors.
- `committed` + valid target → keep the new artifact and delete the stale backup.
- No marker + valid target + backup → keep target, clean backup.

Original PDFs are never written. Annotation rows are never deleted: unresolved anchors are marked `anchorStatus = 'unresolved'` and stay visible.

### 4.1 Annotation and progress preservation

`AnnotationRemapper` relocates by content rather than by regenerated UUIDs:

- exact block ID when it still exists (idempotent re-run),
- otherwise old block text → new block text, preferring the same page and chapter title,
- prefix/suffix context for highlights,
- normalized-text match for hyphenation/spacing differences,
- final fallback: first readable block on the recorded source page (bookmarks only).

Reading progress is remapped by chapter title, then by exact block text, then proportionally within the new chapter. `progressPercentage` is preserved unchanged.

### 4.2 UI

Book details now shows the artifact state and pipeline version, and exposes **Perbarui Mode Buku** only when reprocessing is needed, with an inline progress indicator and a summary of relocated annotations.

---

## 5. Data Preservation Evidence

`test/phase_3_8_artifact_integrity_test.dart` (18 tests, all passing) covers:

- stale detection: no manifest, older pipeline, older schema, changed source size;
- current and newer artifacts are not downgraded;
- `requiresOcr` artifacts are incomplete, not usable;
- unreadable JSON is reported;
- successful reprocess updates the artifact and relocates bookmark, highlight, and progress;
- incomplete candidate never replaces the previous artifact;
- DB failure after the file swap restores the previous bytes;
- reconstruction exception leaves the artifact untouched;
- second reprocess returns `alreadyCurrent` and byte-identical output;
- missing source PDF returns `missingSource` without writing;
- interrupted swap is recovered before the freshness decision;
- uncommitted recovery restores the backup; committed recovery keeps the new artifact.

The preservation test asserts specifically:

- bookmark `anchorNodeId`/`chapterId` point at the new block/chapter after reprocess;
- highlight offsets (`startOffset`/`endOffset`), `anchorNodeId`, and `anchorStatus = resolved` survive;
- reading progress keeps chapter index, block position, and percentage;
- original PDF bytes are unchanged.

---

## 6. Real-Book Regression Results

Fixtures are resolved through `test/helpers/real_book_fixtures.dart`. Mandatory fixtures call `fail()` with every checked path; optional fixtures call `markTestSkipped()` and are reported (`~`) rather than passed.

| Book | File size | Pages | Text layer | Chapters | Result |
| --- | --- | --- | --- | --- | --- |
| The Let Them Theory | 8,237,163 B | 272 | 256 native / 7 hybrid / 5 scanned / 4 empty | 23 | Reconstructed, text preserved (475,670 chars vs 470,360 extracted) |
| Laut Bercerita | 2,630,743 B | 394 | 0 native / 394 scanned | 1 placeholder | `requiresOcr`, Original PDF fallback |
| The Devotion of Suspect X | 1,762,180 B | 324 | 0 native / 324 scanned | 1 placeholder | `requiresOcr`, Original PDF fallback |
| Bicara Itu Ada Seninya | 66,783,602 B | 255 | 0 native / 255 scanned | 1 placeholder | `requiresOcr`, Original PDF fallback |

Each run records path, byte size, SHA-256 prefix, page count, layer breakdown, extraction character count, chapter/block counts, quality status, processing status, and pipeline version. All four PDF SHA-256 digests are distinct, and extraction is asserted not to modify the source files.

Additional evidence: the historical *Laut Bercerita* artifact
`~/Documents/DigitalBooks/books/8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.json`
(738,046 B, 8 chapters, 1,377 blocks) is loaded as a real pre-3.8 artifact and passes the normalization assertions below.

Limitation: OCR was not run for the 973 scanned pages. Those books are verified to gate correctly, not to reconstruct correctly.

---

## 7. Heading and Reading-Order Results

**Before**: *The Let Them Theory* produced 25 chapters, with `Introduction: My Story` and `Conclusion: Y our Let Me Era Is Here` promoted from the table of contents before the real `INTRODUCTION`, and `CHAPTER II` between 10 and 12.

**After**: 23 chapters in document order — `Bagian Awal`, `INTRODUCTION`, `CHAPTER 1`…`CHAPTER 20`, `CONCLUSION` — with consecutive numbering, unique titles, no sentence-like titles, and page order monotonic.

Fixes, all format-level:

1. **Split-word header matching** — header comparison folds whitespace, so `T able of Contents` matches `table of contents` / `daftar isi`.
2. **Contents continuation propagation** — a page immediately after a detected contents page is treated as contents when it contains at least two entry-like lines (dot leaders, numbered entries, named sections).
3. **Chapter quality normalization** (`ChapterQualityNormalizer`):
   - heading-only `Daftar Isi` chapters are folded into a neighbour; contents chapters with real entries are preserved;
   - sentence-like display lines are merged into the previous chapter instead of becoming chapters;
   - duplicate titles merge into the substantial chapter, keeping all body blocks and dropping only the repeated title heading;
   - consecutive duplicate headings collapse;
   - empty chapters merge or receive an explicit placeholder.
4. **Isolated roman numeral repair** — `CHAPTER II` becomes `CHAPTER 11` only when the surrounding arabic sequence is `10, _, 12`; genuine roman schemes (`BAB I/II/III`) are untouched.

Saved *Laut Bercerita* artifact: 8 chapters → 4 (`Pengantar`, `Prolog`, `Epilog`, `Ucapan Terima Kasih`). Duplicate `Prolog`/`Ucapan Terima Kasih` chapters merge, the heading-only `Daftar Isi` chapter folds away, and the sentence fragment merges into the last chapter. The test asserts every non-duplicate-title text block from the original document still exists afterwards.

One pre-existing audit test (`audit_corpus_ground_truth_test.dart`) reconstructs *Bicara Itu Ada Seninya* from the local OCR database. It verifies that a real contents chapter with 61 entry nodes and `BAB I`–`BAB V` labels survives unchanged; this guarded against over-aggressive TOC folding.

---

## 8. OCR Quality Gating

`OcrQualityGate` defines measurable readiness:

| Criterion | Threshold |
| --- | --- |
| Page coverage | ≥ 95% completed |
| Failed pages | 0 |
| Average confidence | ≥ 0.70 |
| Text density | ≥ 40 characters per completed page |
| Native text layer present | `notRequired` (OCR optional) |

States: `notRequired`, `pending`, `inProgress`, `failed`, `insufficientQuality`, `ready`.

`OcrSemanticPipeline` writes `ocrQuality` (all inputs and reasons) and `ocrReadiness` to metadata. When the gate is not satisfied, `processingStatus` is forced to `requiresOcr`, which the reader already treats as "use Original PDF" and shows the recommendation banner. The artifact is still saved because OCR text remains useful for search; it is not advertised as a verified reflowable book.

Tests cover native, hybrid, pending, in-progress, failed, partial coverage, low confidence, low density, ready, metadata shape, and end-to-end pipeline wiring for both passing and insufficient OCR on a generated PDF. Hybrid documents correctly stay on native text while OCR is optional.

---

## 9. Native macOS Acceptance Status

Performed:

- `flutter build macos --debug` → **success** (`build/macos/Build/Products/Debug/Digital Books.app`).
- `open "build/macos/Build/Products/Debug/Digital Books.app"` → process launched and stayed alive for the observation window.
- Quit attempt via AppleScript.

Blocked:

- `screencapture -x /tmp/p38_launch.png` → `could not create image from display` (Screen Recording permission unavailable).
- `osascript ... System Events ... windows of process "Digital Books"` → `osascript is not allowed assistive access (-1728)`.

Therefore import, reading, Book Mode switching, typography, theme, chapter navigation, bookmark/annotation flows, restart persistence, and invalid-PDF handling were **not** validated natively. No screenshot was captured; none is claimed. Widget tests are not presented as manual acceptance.

---

## 10. Automated Test Results

Commands and actual outcomes:

| Command | Result |
| --- | --- |
| `flutter analyze` | `No issues found!` |
| `dart format --output=none --set-exit-if-changed lib test` | `Formatted 193 files (0 changed)`, exit 0 |
| `git diff --check` | no output, exit 0 |
| `flutter test test/phase_3_8_artifact_integrity_test.dart` | 18 passed |
| `flutter test test/phase_3_8_heading_quality_test.dart` | 17 passed |
| `flutter test test/phase_3_8_ocr_quality_gate_test.dart` | 12 passed |
| `flutter test test/phase_3_8_real_book_regression_test.dart` | 18 passed, 1 skipped |
| Targeted existing suites (Phase 3.6, 2.7e, 2.8, audits, regression) | 97 passed, 2 skipped, exit 0 |
| `flutter test --reporter expanded` | see §10.1 |

### 10.1 Full suite

`flutter test --reporter expanded`: **564 passed, 2 skipped, 0 failed**, exit code `0`, 71 s (baseline Phase 3.7: 500 passed).

The two skips are the explicit optional-fixture checks introduced by the new helper; no real-book test is skipped when its file is present.

### 10.2 Formatter commit audit (Phase 1)

`4d3964f` touched 89 files. Each file was compared with its parent after removing whitespace, `{`, `}`, and `,` (the only tokens a formatter/brace lint may legitimately add or remove). **0 of 89 files differed.** The commit is mechanically formatting-only.

---

## 11. Remaining Limitations

1. **No real OCR validation for scanned books.** *Laut Bercerita*, *Suspect X*, and *Bicara* are gated correctly but were not OCR'd end-to-end in this phase (973 pages). Their Book Mode quality is unmeasured.
2. **No end-to-end reprocess on real user data.** The local application database contains no completed OCR rows for the scanned books, so reprocessing was verified with synthetic database rows plus real artifacts and real PDFs. The historical *Laut* JSON was used as the real stale artifact.
3. **Annotation remapping is heuristic.** Content matching can fail after heavy re-extraction; unresolved highlights/bookmarks are preserved but marked `unresolved` (`anchorStatus`), not silently deleted.
4. **Progress fallback is approximate.** When a chapter's anchor text disappears, position is scaled proportionally; the percentage is retained but the exact block may shift.
5. **The reprocess dialog has no widget test.** Service-level behaviour is covered; the button/snackbar path is validated only by analysis.
6. **TOC continuation detection is heuristic.** The "two entry-like lines after a contents page" rule could over-classify an unusual front-matter page; contents chapters with real entries are preserved, so content is not lost.
7. **`--ignore-all-space` is not proof of formatting-only.** The stronger token-multiset comparison in §10.2 was used instead; it covers the 89 files but still cannot detect reordered tokens.
8. **Native GUI acceptance remains blocked** by macOS Screen Recording and Accessibility permissions.
9. **Version not bumped.** `pubspec.yaml` remains `1.1.0-alpha.8+9`; Phase 3.8 is not a release checkpoint.

---

## 12. Git Changes

Base: `084e201` on `main`, 3 unpushed Phase 3.7 commits.

Commits added by this phase (no push):

1. `59459fe` — `feat(processing): version processed artifacts and add safe reprocessing`
2. `48edbf7` — `fix(processing): stop TOC leakage and normalize chapter titles`
3. `87f33f0` — `feat(ocr): gate Book Mode on measured OCR quality`
4. `9655005` — `test(processing): add Phase 3.8 integrity and real-book suites`
5. `docs(release): add Phase 3.8 artifact integrity report`

Each commit was checked to resolve every relative import inside that
commit's own tree, so no commit depends on files introduced later.

Files:

- **New**: `processing_manifest.dart`, `processed_artifact_inspector.dart`, `chapter_quality_normalizer.dart`, `ocr_quality.dart`, `ocr_quality_gate.dart`, `annotation_remapper.dart`, `book_reprocessor.dart`, `book_document_rebuilder.dart`, four Phase 3.8 test files, `test/helpers/real_book_fixtures.dart`.
- **Modified**: `database_service.dart` (single reprocessing transaction), `file_storage_service.dart` (atomic write), `semantic_reconstruction_models.dart` (manifest), `pdf_processing_pipeline.dart` (source hash/size), `ocr_semantic_pipeline.dart` (quality gate + provenance), `semantic_classifier.dart` (TOC detection), `semantic_document_reconstructor.dart` (normalizer), `book_details_dialog.dart` (artifact status + reprocess action), and eight existing real-book tests (silent skips → explicit skips).

No original PDF, user annotation, bookmark, reading-progress row, or artifact was deleted by this work.

---

## 13. Acceptance

**CONDITIONAL PASS**

Satisfied:

- Stale artifacts are detected from explicit versioning, not guesswork.
- Reprocessing is atomic, validated, recoverable, idempotent, and preserves annotations/bookmarks/progress in automated tests.
- Missing mandatory real-book fixtures fail; optional ones report as skipped.
- Heading duplication, TOC leakage, and sentence-title chapters are fixed at the source and verified on a real book and a real historical artifact.
- OCR readiness is explicit and gates Book Mode.
- Analysis, formatting, diff checks, targeted suites, and the full suite pass.

Not satisfied / not verified:

- Native macOS GUI acceptance (permissions blocked).
- OCR quality for the three scanned books (not run).
- Reprocessing against real user annotations (database has no OCR rows for those books).
