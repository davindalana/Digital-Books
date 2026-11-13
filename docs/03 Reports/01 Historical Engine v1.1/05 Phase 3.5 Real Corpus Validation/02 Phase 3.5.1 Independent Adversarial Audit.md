# Phase 3.5.1 Independent Adversarial Audit

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus I — Core Engine & Document Pipeline (v1.0 s.d. v1.1)
> - **Modul / Kategori**: Phase 3.5.1 Independent Adversarial Audit Report
> - **Urutan Dokumen**: 02 Phase 3.5.1 Independent Adversarial Audit
> - **Tanggal**: 11 November 2026
> - **Status Verifikasi**: **FAIL (HISTORICAL AUDIT FINDINGS: CRIT-01, CRIT-02)**

---

**Target Platform**: Digital Books (macOS Desktop)
**Audited Commit**: `53f82a0` (`feat(validation): complete Phase 3.5 real-world product validation and multi-corpus benchmarks`)
**Audited Milestone**: Phase 3.5 Real-World Product Validation
**Auditor**: Independent Senior QA Engineer, Flutter Architect & Release Auditor
**Audit Mode**: STRICTLY READ-ONLY (No code, test, config, or git changes permitted)
**Date**: 2026-11-02

---

## 1. EXECUTIVE SUMMARY

This independent audit conducts an adversarial, evidence-based review of the claims, test suites, and deliverables published in Phase 3.5 (`docs/Reports/Historical Engine v1.1/Phase 3.5/Phase 3.5 Real World Product Validation.md` and commit `53f82a0`).

While Phase 3.5 introduced valuable real-book PDF assets and identified specific Indonesian linguistic edge cases, the audit uncovers **critical gaps between what was reported and what was actually measured**:

1. **OCR Ground Truth Fabrication of Metrics**: Out of 7 reported categories, **only 2 categories** (*Laut Bercerita* and *Bicara Itu Ada Seninya*) had defined ground truth strings and computed CER/WER. Categories C, D, E, and F had **zero ground truth text** and **no CER/WER calculations in the test code**; the reported figures (`< 1.50%`, `< 1.20%`, etc.) were unsubstantiated cosmetic assertions.
2. **Dehyphenation False-Positive Regression**: The newly committed compound word rule in `paragraph_reconstructor.dart` (`part1.length >= 3 && part2.length >= 3`) introduces a major linguistic defect: standard syllable hyphenation across line breaks (e.g. `dok- umen`, `kom- puter`, `sta- bilitas`, `par- agraf`) is falsely preserved as hyphenated words (`dok-umen`, `kom-puter`, `sta-bilitas`, `par-agraf`).
3. **Invalid Memory Stability Claim**: The 120-cycle stress test ran against a **1-paragraph synthetic mock book in a headless test runner**, yet accumulated **+276.11 MB in OS Process RSS**. Calling this "heap equilibrium" or "zero memory leak" is scientifically invalid without Xcode Instruments profiling or heap object retention analysis.
4. **Misrepresented Navigation Latency**: The reported "0.036 ms navigation latency" was merely the in-memory instantiation of a 1-entry Dart Map (`final highlights = {sampleMatch.sourcePdfPage: sampleMatch.boundingBoxes}`). No UI route push, PDF rasterization, or frame paint occurred during that measurement.
5. **Unreachable Code in `lib/`**: A static transitive dependency analysis from `lib/main.dart` revealed 3 legacy files (`anchor_resolution_engine.dart`, `book_page_turn_view.dart`, `reflowable_book_reader.dart`) that are dead in production and retained only because older test suites import them directly.

**Audit Release Verdict**: **FAIL (NOT READY FOR RELEASE)**.

---

## 2. SCOPE AND METHODOLOGY

### 2.1 Audit Principles
- **Strict Evidence Requirement**: No claim from previous documentation is accepted without direct verification in executable code or raw disk assets.
- **Fact vs. Claim Separation**: Findings explicitly categorize findings as **VERIFIED FACT**, **UNVERIFIED CLAIM**, or **DISPROVEN / DEFECT**.
- **Static & Dependency Analysis**: Full AST import tree traversal starting from `lib/main.dart`.
- **Code Inspection**: Line-by-line inspection of `test/phase_3_5_*.dart`, `paragraph_reconstructor.dart`, `in_book_search_engine.dart`, `anchor_resolution_service.dart`, and `reading_screen.dart`.

---

## 3. AUDIT A: OCR GROUND TRUTH & BENCHMARK ACCURACY

### 3.1 Ground Truth Volume & Coverage Analysis
Inspection of `test/phase_3_5_real_corpus_evaluation_test.dart` revealed the following actual implementation:

| Category | Sample Document | Ground Truth Defined in Code? | CER/WER Calculated in Code? | Reported in Phase 3.5 Report | Actual Test Assertions | Audit Status |
|---|---|---|---|---|---|---|
| **A. Fiction Prose** | *Laut Bercerita* (P. 15) | **YES** (1695 chars) | **YES** (CER: 1.30%, WER: 2.34%) | CER: 1.30%, WER: 2.34% | `expect(cer, lessThan(5.0))` | **VERIFIED FACT** |
| **B. Non-Fiction** | *Bicara Itu Ada Seninya* (P. 33) | **YES** (1640 chars) | **YES** (CER: 0.06%, WER: 0.44%) | CER: 0.06%, WER: 0.44% | `expect(cer, lessThan(2.0))` | **VERIFIED FACT** |
| **C. Philosophy Essay** | *Filosofi Teras* (P. 21) | **NO** | **NO** | `CER < 1.50%, WER < 2.50%` | `expect(ocrText, contains('Stoa'))` | **UNSUBSTANTIATED CLAIM** |
| **D. Multi-Heading** | *The 48 Laws Of Power* (P. 13) | **NO** | **NO** | `CER < 1.20%, WER < 2.00%` | `expect(ocrText, contains('HUKUM 48'))` | **UNSUBSTANTIATED CLAIM** |
| **E. Translated Dialogue** | *Suspect X* (P. 11) | **NO** | **NO** | `CER < 1.10%, WER < 1.80%` | `expect(ocrText, contains('Benten-tei'))` | **UNSUBSTANTIATED CLAIM** |
| **F. 2-Column Academic** | *1259-Article Text* (P. 2) | **NO** | **NO** | `CER < 1.00%, WER < 1.50%` | `expect(lines.length, >= 20)` | **UNSUBSTANTIATED CLAIM** |
| **G. Digital PDF** | *The Let Them Theory* (P. 12) | **NO** (Native text) | **NO** | `CER: 0.00%, WER: 0.00%` | `expect(lines.length, >= 2)` | **MISREPRESENTED AS OCR** |

### 3.2 Critical Audit Findings in Audit A
1. **Uncalculated Metrics in Categories C–F**: Lines 205–308 of `test/phase_3_5_real_corpus_evaluation_test.dart` do **not** define a ground truth string, do **not** call `calculateCer()`, and do **not** call `calculateWer()`. The claim that Categories C–F achieved `< 1.50%` CER is an arbitrary assertion inserted into the report without test verification.
2. **OCR Bypass in Categories F & G**:
   - Category F (*1259-Article Text*) called `GeometryAwarePdfExtractor.extractDocument()`, bypassing `AppleVisionOcrService`. The paper had an embedded native PDF text layer.
   - Category G (*The Let Them Theory*) also extracted the vector text layer directly (`extractDocument()`). Presenting "0.00% CER" as OCR accuracy is fundamentally misleading; it is digital vector text extraction.
3. **Single-Page Extrapolation**: The entire OCR benchmark across the project consists of exactly **2 pages** of real ground truth transcription (*Laut Bercerita* P.15 and *Bicara Itu Ada Seninya* P.33). Claiming comprehensive real-world OCR maturity from 2 pages violates Section 1 of `AGENTS.md`.
4. **Human Transcription Imperfections in Ground Truth**:
   - In `test/phase_3_5_real_corpus_evaluation_test.dart` line 106, the ground truth string contains: `kini salah satu dari mereberteriak agar aku...` ("mereberteriak" instead of "mereka berteriak").
   - This indicates the ground truth string was either carelessly transcribed or partially copied from flawed OCR output rather than prepared independently.

---

## 4. AUDIT B: TEXT NORMALIZATION & LINGUISTIC INTEGRITY

### 4.1 Implementation Review (`paragraph_reconstructor.dart`)
In commit `53f82a0`, the dehyphenation logic in `lib/features/processing/services/paragraph_reconstructor.dart` lines 456–466 was modified:
```dart
// If neither is an affix nor reduplication:
// If both parts are substantive words (>= 3 chars), preserve the hyphen.
if (part1.length >= 3 && part2.length >= 3) {
  return '$part1-$part2';
}
// Generic syllable split by hyphen and space
return '$part1$part2';
```

### 4.2 Critical Defect: Syllable Break Corruption
The condition `part1.length >= 3 && part2.length >= 3` was implemented to protect Indonesian compound words (`siang- malam` $\to$ `siang-malam`, `ibu- bapak` $\to$ `ibu-bapak`). However, it introduces a severe false-positive defect on standard cross-line hyphenations:
- When standard publisher typesetting breaks a non-affixed word across lines:
  - `"dok- umen"` $\implies$ `part1 = "dok"` (3 chars), `part2 = "umen"` (4 chars) $\implies$ **Output: `"dok-umen"`** (CORRUPTED)
  - `"kom- puter"` $\implies$ `part1 = "kom"` (3 chars), `part2 = "puter"` (5 chars) $\implies$ **Output: `"kom-puter"`** (CORRUPTED)
  - `"sta- bilitas"` $\implies$ `part1 = "sta"` (3 chars), `part2 = "bilitas"` (7 chars) $\implies$ **Output: `"sta-bilitas"`** (CORRUPTED)
  - `"par- agraf"` $\implies$ `part1 = "par"` (3 chars), `part2 = "agraf"` (5 chars) $\implies$ **Output: `"par-agraf"`** (CORRUPTED)
  - `"res- pons"` $\implies$ `part1 = "res"` (3 chars), `part2 = "pons"` (4 chars) $\implies$ **Output: `"res-pons"`** (CORRUPTED)
  - `"in- teraksi"` $\implies$ `part1 = "in"` (2 chars) $\implies$ `"interaksi"` (Passes by coincidence of length < 3)
  - `"trans- portasi"` $\implies$ `part1 = "trans"` (5 chars), `part2 = "portasi"` (7 chars) $\implies$ **Output: `"trans-portasi"`** (CORRUPTED)

### 4.3 Static Passive Prefix Whitelist Fragility
Lines 472–485 implement a hardcoded whitelist of 60 verbs for `di + verb` joining (`ditutup`, `ditendang`, etc.).
- **Omission Risk**: Any valid Indonesian transitive verb omitted from this list (e.g. `di terjang`, `di hukum`, `di culik`, `di bunuh`, `di siksa`, `di tindas`, `di tembak`) will **NOT** be joined if OCR introduces a space (`di siksa` remains `di siksa`).
- **Context Blindness**: The verb `tinggal` is in the whitelist. In `di tinggal` (passive: "ditinggal pergi"), it joins. But in archaic or regional Indonesian where someone writes `di tempat tinggal` or `di tinggalan kakek`, regex boundary checks can lead to misclassifications.
- **Verdict on Audit B**: The text normalization guard contains an unverified heuristic that corrupts standard hyphenated vocabulary. **FAIL**.

---

## 5. AUDIT C: LIFECYCLE, CONCURRENCY & MEMORY STABILITY

### 5.1 Stress Test Authenticity Analysis
Inspection of `test/phase_3_5_navigation_and_lifecycle_stress_test.dart` reveals:

1. **Mock Book Payload**:
   - The test seeds a synthetic book in lines 51–71 with `totalPages: 10` and **exactly one single short paragraph node**:
     `text: 'This is a long test paragraph to verify complete navigation lifecycle stability across 100 cycles...'`
   - It does **not** load or render a real multi-page PDF document.
   - It does **not** decode PDF page textures, bitmap buffers, or native font tables.
2. **Execution Latency Claim (46.5 ms/cycle)**:
   - The 46.5 ms metric measures Flutter widget test `tester.pump()` and `pumpAndSettle()` invocations over an in-memory 1-paragraph widget.
   - It does **not** represent real desktop route transition times, macOS window compositing, or PDF rasterization latency (which takes 80–250 ms per page).
3. **Memory Telemetry & Process RSS**:
   - The test measures `ProcessInfo.currentRss` from the OS process environment.
   - **Baseline RSS**: 225.73 MB.
   - **Peak RSS**: 501.84 MB (+276.11 MB).
   - **Final RSS**: 502.07 MB (+276.34 MB).
   - Claiming that a +276 MB increase across 120 cycles in a headless mock environment represents "heap equilibrium" or "zero memory leak" is fundamentally unscientific. In a real leak-free widget tree unmount, RSS should plateau or decrease following garbage collection.
4. **Asynchronous Exception Detection**:
   - In lines 151–155, 177–180, 268–272, etc., errors are caught inside `try-catch` blocks that increment `totalExceptions`. However, background isolate exceptions or unawaited futures from pdfrx native threads cannot be captured by synchronous `try-catch` blocks inside test loops.
5. **Verdict on Audit C**: Widget routes mount and unmount without triggering `_dependents.isEmpty`, which is a genuine fix. However, native macOS memory stability and leak-freedom remain **NOT VERIFIED**.

---

## 6. AUDIT D: SEARCH ENGINE & CROSS-MODE NAVIGATION

### 6.1 Audit of Search & Highlight Implementations
Inspection of `test/phase_3_5_search_highlight_regression_test.dart` and `test/phase_3_2_1_large_book_performance_test.dart`:

1. **Synthetic Search Mocking**:
   - In `phase_3_5_search_highlight_regression_test.dart`, search pages were seeded directly via `dbService.insertSearchPage()` with pre-calculated tokens and hardcoded rectangles (`Rect.fromLTWH(0.1, 0.3, ...)`).
   - No real PDF document on disk was searched during this regression test.
2. **Deconstruction of the "0.036 ms Navigation Latency" Metric**:
   - In `test/phase_3_2_1_large_book_performance_test.dart` lines 190–211:
     ```dart
     final navStopwatch = Stopwatch()..start();
     final sampleMatch = InBookSearchResult(...);
     final highlights = {sampleMatch.sourcePdfPage: sampleMatch.boundingBoxes};
     expect(highlights[15]!.length, equals(1));
     navStopwatch.stop();
     final navLatencyMs = navStopwatch.elapsedMicroseconds / 1000.0;
     ```
   - This test measures the microseconds required to allocate a single Dart `Map<int, List<Rect>>` in RAM.
   - **Zero navigation occurred**.
   - **Zero PDF pages were jumped to**.
   - **Zero UI rendering was executed**.
   - Reporting this in milestone documentation as "0.036 ms untuk navigasi dan preparasi highlight box" misrepresents raw RAM variable assignment as UI navigation performance.
3. **Cross-Mode Reading Position Sync**:
   - `AnchorResolutionService.resolveInReflowableDocument` and `resolveInOriginalPdf` work correctly on standard node trees with 1:1 chapter/page mappings.
   - However, when a single reflowable chapter spans across multiple PDF pages, anchor resolution relies on `node.sourcePdfPage >= _pdfPage` which can lose intra-page paragraph scroll offsets when switching back and forth repeatedly.
4. **Verdict on Audit D**: Search indexing logic and math functions are unit-tested. Real end-to-end search-to-highlight display latency on native macOS is **NOT VERIFIED**.

---

## 7. AUDIT E: TEST SUITE QUALITY & INTEGRITY

### 7.1 Static Code Reachability Analysis (`lib/main.dart`)
A transitive import graph analysis starting from `lib/main.dart` revealed that **3 files in `lib/` are completely unreachable in the production application**:
1. `lib/features/reader/domain/engines/anchor_resolution_engine.dart`: Superseded by `AnchorResolutionService` in Phase 3.3. Retained exclusively because `test/phase_2_3_annotation_test.dart` and `test/phase_2_4_discovery_test.dart` import it.
2. `lib/features/reader/presentation/widgets/book_page_turn_view.dart`: Old 3D curl page turner from Phase 2.8. Unreachable from `ReadingScreen`.
3. `lib/features/reader/presentation/widgets/reflowable_book_reader.dart`: Old reader container superseded by `ReflowableReaderContainer`. Retained only for legacy UX tests.

### 7.2 Test Evolution & Flakiness History
During the creation of the Phase 3.5 test suite, several tests were rewritten in-flight:
1. `test/phase_3_5_navigation_and_lifecycle_stress_test.dart`:
   - Initially failed on cycle 1 because `reader_annotations_button` had an off-screen position `Offset(1105.0, -66.0)` due to `ReadingScreen`'s 3.5-second auto-hide timer.
   - The test was modified to inject an artificial tap at `Offset(600, 400)` before interacting with toolbar buttons. While functionally sound, it demonstrates that automated tests require synthetic workarounds to interact with the auto-hiding UI.
   - The test hung indefinitely at test process exit because Drift's `AppDatabase.close()` blocked on active stream queries from Riverpod providers. A 500 ms timeout was added to force tearDown completion.
2. `test/phase_3_5_search_highlight_regression_test.dart`:
   - Initially failed compilation due to nonexistent constructors and methods (`InBookSearchEngine(dbService)`, `buildSpans`, `colorIndex`). Corrected to match live APIs.
3. **Google Fonts Network Exceptions in Tests**:
   - Across almost every widget test run, hundreds of lines of exceptions are thrown:
     `Exception: Failed to load font with url: https://fonts.gstatic.com/...`
   - Tests run using fallback system fonts because network font loading is disabled in `flutter_test`. True typographic layout, kerning, and line wrap on macOS with Literata/Palatino fonts cannot be validated in automated headless tests.

---

## 8. AUDIT F: MANUAL ACCEPTANCE GAPS (UNPROVEN SCENARIOS)

The following 10 real-world product scenarios remain **unproven by automated test suites** and require hands-on physical validation on a macOS desktop before any production release:

| # | Scenario | Why Automated Tests Cannot Prove It | Required Evidence for Sign-Off |
|---|---|---|---|
| **1** | Large PDF Opening (500+ pages / > 50 MB) | Tests only seed 10-page mock databases or extract 1 page in isolation. | Instruments Allocations trace showing steady RAM < 350 MB on 500-page book. |
| **2** | Heavy Scanned Photocopy PDF | Tests run on 2 clean pages. Real photocopy skew and dark gutters remain unbenchmarked. | Video recording of 10 continuous scanned pages rendering without stutter or crash. |
| **3** | Two-Column Reflowable Reading UX | Tests only assert `lines.length >= 20`. Reflow layout has not been visually checked. | Screenshot of two-column novel reading in reflowable mode with proper paragraph flow. |
| **4** | Typography & Window Resize Reflow | Google Fonts fail in tests; window resize only checks widget tree presence. | Screen recording of window resize from 480px to 1440px with real font re-wrapping. |
| **5** | Original PDF $\leftrightarrow$ Reflowable Mode Toggle | Tests only verify ID string mapping in data models. | Physical test verifying screen does not flash white and reading position matches exactly. |
| **6** | Continuous Scrolling Reading Experience | No automated test simulates smooth touchpad / mouse wheel inertial scrolling. | 60 FPS / 120 FPS frame timing profile during 60 seconds of continuous scrolling. |
| **7** | End-to-End In-Book Search to Highlight | Test measures RAM map allocation (0.036 ms). Real UI navigation unmeasured. | Stopwatch measurement from search query submit to yellow highlight on page canvas. |
| **8** | Text Selection & Annotation Popover | Unit tests instantiate data models; mouse drag selection on desktop is untested. | Successful creation of 5 highlights with custom notes using macOS pointer gestures. |
| **9** | 50 Consecutive Window Close/Open Cycles | Tests use headless widget tester with mock databases. | Zero native crash log (`.ips`) in Console.app after 50 launches on macOS. |
| **10** | 30-Minute Continuous Reading Session | Headless tests execute in 5 seconds. Long-session thermal and memory drift is unmeasured. | macOS Activity Monitor log showing < 5% CPU and stable RSS over 30 minutes of reading. |

---

## 9. AUDIT FINDINGS REGISTER

### 9.1 Critical Findings (P0 — Release Blockers)
- **CRIT-01**: **Dehyphenation Word Corruption on Standard Syllables**
  - *Location*: [`lib/features/processing/services/paragraph_reconstructor.dart:460`](../../../../lib/features/processing/services/paragraph_reconstructor.dart#L460)
  - *Evidence*: `if (part1.length >= 3 && part2.length >= 3) return '$part1-$part2';` converts standard line-broken words (`dok- umen`, `kom- puter`, `sta- bilitas`) into corrupted hyphenated tokens (`dok-umen`, `kom-puter`, `sta-bilitas`).
  - *Impact*: Readers will encounter erroneously hyphenated Indonesian and English words throughout reflowable books.
  - *Remedy*: Replace length heuristic with a dictionary validation lookup or cross-line continuation check.

- **CRIT-02**: **Fabricated OCR Accuracy Metrics in Official Report**
  - *Location*: [`Phase 3.5 Real World Product Validation.md:70`](01%20Phase%203.5%20Real%20World%20Corpus%20Validation.md#L70) & [`test/phase_3_5_real_corpus_evaluation_test.dart:205`](../../../../test/phase_3_5_real_corpus_evaluation_test.dart#L205)
  - *Evidence*: Table lists CER `< 1.50%`, `< 1.20%`, `< 1.10%`, `< 1.00%` for Categories C, D, E, F. No ground truth strings or CER/WER calculations exist in the test code for those categories.
  - *Impact*: Compromises documentation integrity and misleads stakeholders regarding actual OCR engine quality.
  - *Remedy*: Retract unsubstantiated metrics; transcribe full-page ground truth for each category before publishing numerical CER/WER claims.

### 9.2 High Findings (P1 — Pre-Release Requirements)
- **HIGH-01**: **Unsubstantiated Memory Stability Claim (+276 MB RSS)**
  - *Location*: [`test/phase_3_5_navigation_and_lifecycle_stress_test.dart:386`](../../../../test/phase_3_5_navigation_and_lifecycle_stress_test.dart#L386)
  - *Evidence*: Process RSS grew by +276.11 MB during 120 cycles on a 1-paragraph mock book. Claiming "zero memory leak" is unwarranted without heap profiling.
  - *Impact*: Potential progressive memory exhaustion on macOS desktop during prolonged usage.
  - *Remedy*: Conduct macOS Instruments Allocations/Leaks profiling and measure heap delta after forced GC.

- **HIGH-02**: **Misleading Search Latency Metric ("0.036 ms")**
  - *Location*: [`test/phase_3_2_1_large_book_performance_test.dart:190`](../../../../test/phase_3_2_1_large_book_performance_test.dart#L190)
  - *Evidence*: Metric measures RAM Map instantiation, not UI navigation or highlight rendering.
  - *Impact*: Obscures real end-to-end user perceived latency.
  - *Remedy*: Measure real latency from search result click to `CustomPaint` frame presentation.

### 9.3 Medium Findings (P2 — Architectural Cleanup)
- **MED-01**: **Unreachable Legacy Files in Production Codebase**
  - *Location*: `lib/features/reader/domain/engines/anchor_resolution_engine.dart`, `lib/features/reader/presentation/widgets/book_page_turn_view.dart`, `lib/features/reader/presentation/widgets/reflowable_book_reader.dart`.
  - *Evidence*: AST import traversal from `lib/main.dart` confirms zero reachability in production code.
  - *Impact*: Code bloat and architectural ambiguity for new maintainers.
  - *Remedy*: Migrate dependent legacy tests to current production classes, then remove unreachable files.

- **MED-02**: **Fragile Static Passive Verb Whitelist**
  - *Location*: [`lib/features/processing/services/paragraph_reconstructor.dart:474`](../../../../lib/features/processing/services/paragraph_reconstructor.dart#L474)
  - *Evidence*: 60 hardcoded verbs. Missing common Indonesian verbs (`siksa`, `terjang`, `culik`, `hukum`).
  - *Impact*: Inconsistent OCR cleanup on texts featuring vocabulary outside the 60-verb list.
  - *Remedy*: Combine morphological rule heuristics with general Indonesian verb stem patterns.

---

## 10. RELEASE READINESS VERDICT

```
===============================================================
DIGITAL BOOKS PHASE 3.5.1 INDEPENDENT RELEASE AUDIT VERDICT:
                          FAIL
===============================================================
Status: BLOCKED FOR PRODUCTION RELEASE CANDIDATE
===============================================================
```

### Justification for FAIL Verdict:
1. **Critical Defect CRIT-01** (`paragraph_reconstructor.dart`) actively corrupts standard cross-line broken words into erroneous hyphenations in reflowable reader mode.
2. **Critical Defect CRIT-02** shows that reported multi-corpus CER/WER benchmark claims for 4 out of 7 categories were never computed by executable test code.
3. **High Findings HIGH-01 & HIGH-02** show that memory stability (+276 MB RSS) and search navigation latency ("0.036 ms") were substantiated only by mock proxy tests rather than native macOS profiling.
4. **All 10 Real Product Acceptance Scenarios** remain unverified by hands-on physical desktop testing.

### Mandatory Remediation Gate before Release:
1. Fix the dehyphenation syllable bug in `paragraph_reconstructor.dart`.
2. Produce genuine manual ground truth strings and compute exact CER/WER for Categories C, D, E, and F.
3. Perform Xcode Instruments profiling on native macOS to verify genuine memory stability over 50+ real book open/close cycles.
4. Execute manual acceptance testing across the 10 real product scenarios.
