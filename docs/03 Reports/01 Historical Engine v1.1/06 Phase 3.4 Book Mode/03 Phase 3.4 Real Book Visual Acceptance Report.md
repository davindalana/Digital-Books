# Phase 3.4 Real Book Visual Acceptance Report

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus I — Core Engine & Document Pipeline (v1.0 s.d. v1.1)
> - **Modul / Kategori**: Book Mode Real Book Full Volume Visual Acceptance (Bicara Itu Ada Seninya)
> - **Urutan Dokumen**: 03 Phase 3.4 Real Book Visual Acceptance Report
> - **Tanggal**: 7 November 2026
> - **Status Verifikasi**: **PASS**

---

- **Date**: 6 November 2026
- **Book**: *Bicara Itu Ada Seninya* (Oh Su Hyang)
- **Book ID**: `7b3dcbf3-0f23-4c6d-8044-d525257dac00`
- **Original PDF**: `~/Documents/DigitalBooks/originals/7b3dcbf3-0f23-4c6d-8044-d525257dac00.pdf`
- **PDF size**: 66,783,602 bytes (66.8 MB) — the previous report's "12.4 MB" was incorrect
- **SHA-256**: `ce0c5eea0aed00f012a63c9e238639fcd90bc66fef1a1a93af9f2a808b0da233`
- **Pages**: 255 (verified with PDFKit)
- **Database used by the app**: `~/Documents/digital_books_db.sqlite`
- **Derivative**: `~/Documents/DigitalBooks/books/7b3dcbf3-0f23-4c6d-8044-d525257dac00.json` (442 KB)

## Verdict

**CONDITIONAL PASS — readable in Book Mode, not yet full acceptance.**

The book now opens in horizontal Book Mode, the nine real chapters are present, every paginated page has content, and page/keyboard/trackpad/chapter/search navigation works. The full text is preserved (37,669 words).

This is **not** a clean PASS because the table of contents is still fragmented, the BAB III title still contains an OCR error, 45 paragraphs begin with a lower-case continuation, illustration/image extraction is still absent, and a human has not read all 255 pages end to end.

---

## 1. What the previous report got wrong

This audit independently re-ran the pipeline instead of trusting the earlier report. Three earlier claims were invalid:

1. **The "ground truth" was circular.** The former page-29 ground-truth string was character-for-character identical to the OCR output (1,211/1,211 characters), so its 0.00% CER proved only that OCR was compared to itself. The page-18/29/33 labels were also 0-based OCR indexes presented as 1-based PDF pages (e.g. the BAB I divider is PDF page 19, not 18).
2. **The previous visual evidence did not show readable text.** Screenshots `02_real_book_spread_bab1.png` and `04_real_book_compact_single.png` rendered with Flutter's Ahem test font, i.e. every glyph was a solid rectangle. The new evidence loads a real font before capture.
3. **The PDF size was wrong** (12.4 MB vs the actual 66.8 MB), although the SHA-256 did match.

The earlier 414/414 claim was reproducible in this audit only after fixing one semantic-classification regression introduced while reworking the OCR pipeline; the final count is reported in §8.

---

## 2. OCR completion

The OCR queue was re-run from scratch with the existing Apple Vision pipeline after fixing the page-render geometry bug (§3.1). No competing OCR implementation was introduced.

| Metric | Result |
|---|---:|
| Total pages | 255 |
| Completed | **255 / 255 (100%)** |
| Failed | 0 |
| Empty (flyleaf/blank) | 10 |
| Total characters | 268,233 |
| Mean confidence (non-empty) | **99.852%** |
| Minimum confidence | 87.5% (BAB III divider page, PDF 115) |
| Total OCR duration (DB sum) | 65.4 s |
| Average per page | 256.5 ms |
| Page-level persistence | 255 rows in `ocr_pages` |
| Search index | 255 pages in `book_search_pages` |

Empty OCR page indexes (0-based): `1, 5, 16, 17, 59, 113, 152, 207, 208, 253` — PDF pages `2, 6, 17, 18, 60, 114, 153, 208, 209, 254`. These are blank flyleaves/divider blanks, not failed OCR.

Low-confidence pages (0-based OCR indexes): 114 (87.5%, broken `|` glyph in `BAB I|I`), 0 (94.2%), 4 (95.0%), 254 (97.0%, back cover), 92 (97.1%), 163 (97.2%).

---

## 3. Root causes found and fixed

### 3.1 OCR page geometry was compressed by 1.5×

`pdfrx`'s `render(width:, height:)` is a **clip rectangle in page coordinates**, not an output size. Passing only those values rendered the page at native scale into a 1.5× canvas, so every OCR box occupied only the top-left ~2/3 of the image. The semantic stage then multiplied those boxes by the PDF page size, compressing all text upward and leftward by 33%. Footers appeared mid-page, the footer/header zones never matched, and headings/paragraphs were classified from the wrong positions.

**Fix**: render with `fullWidth`/`fullHeight` (`apple_vision_ocr_service.dart`). Re-OCR was required and completed.

### 3.2 OCR line-box height was treated as font size

Apple Vision gives no font family, weight, or size. The pipeline estimated `fontSize = box.height * 0.8`; ascenders/descenders vary by 2–5 pt, so ordinary prose and dialogue were promoted to headings. Before the fix: **618 headings** and 1,687 paragraph blocks, with 661 paragraphs starting mid-sentence. After the OCR-specific rules: **139 headings** (8 H1, 22 H2, 109 H3) and 917 paragraphs, with 45 lower-case starts.

The new OCR rules use:
- first-line indentation and vertical whitespace for paragraph breaks;
- casing and gap-before/gap-after for headings;
- no font-size or bold/italic breaks for Apple Vision lines;
- dialogue markers (including the misread `¿`) and list/chapter patterns.

### 3.3 Running headers/footers and TOC page order

Running headers such as `vi BICARA ITU ADA SENINYA` were being merged with the next page's first line, and TOC pages were partitioned as two columns because of indented entries. The TOC is now forced to strict top-to-bottom order and numbered chrome is isolated.

### 3.4 Back cover merged into BAB V

The back cover (PDF 255: marketing copy, price, barcode, publisher) was appended to BAB V. It is now detected and excluded from the reflowable derivative; the original PDF still preserves it.

### 3.5 Pagination clipped the last line

Some dense pages rendered ~5–36 px taller than the pagination estimate. With `NeverScrollableScrollPhysics`, that overflow was silently clipped. The page body now uses a scale-down safety net (`FittedBox`) so the last line is never cut off and vertical scrolling remains disabled. Measured overflow after the fix: **0.0 px** across all chapter starts.

### 3.6 Stale "PDF Asli recommended" banner

`ReadingScreen` treated every `book.isScanned == true` book as poor quality and showed a large banner recommending Original PDF, even when the OCR derivative's reconstruction quality was **good (0.99)**. Because the banner covered the top of the page, it undermined Book Mode. The banner now follows `reconstructionQuality.status` instead of the source scan flag; the real book's good OCR derivative no longer shows it.

---

## 4. Semantic reconstruction result

| Chapter | Blocks | Source pages |
|---|---:|---:|
| 0. Bagian Awal | 27 | 1–5 |
| 1. Testimoni | 19 | 7–8 |
| 2. Prolog: Membuka Peluang Kesempatan dengan Kebiasaan Bicara | 13 | 9–12 |
| 3. Daftar Isi | 67 | 13–16 |
| 4. BAB I: Perbedaan Juara 1 dan Juara 2 Terletak pada Ucapannya | 189 | 19–59 |
| 5. BAB II: Pintar Mendengar, Pandai Berbicara | 293 | 61–113 |
| 6. BAB III: Ucapan yang Membuat Lawan Bicara Memhak Kita | 156 | 115–151 |
| 7. BAB IV: Beratnya Ucapan Ditentukan oleh Dalamnya Isi | 276 | 154–207 |
| 8. BAB V: Suara Bagus Bukan Bawaan dari Lahir | 199 | 210–253 |

Totals: **1,239 blocks**, 917 paragraphs, 117 `heading` + 22 `sectionHeading`, 68 ordered lists, 62 unordered lists, 40 quotes, 9 copyright blocks, 3 footnotes, 1 document title, **0 image blocks**.

- All nine real chapters are present; no invented chapters.
- No adjacent duplicate paragraphs; 1,239 unique block IDs.
- No running header appears as a heading.
- No heading starts with a quote or lower-case letter.
- The back cover is not inside BAB V.
- Text is preserved: 37,669 words / 268,328 characters. Pages 134 and 217 (short chapter-end pages) have no direct block because their text is merged into the preceding cross-page paragraph; spot checks (`dalam klimaks cerita`, `Choi Bool Am`) confirm the text is present.
- Remaining paragraph issues: 45 paragraphs (4.9%) start lower-case (page-boundary splits), 74 paragraphs are shorter than 20 characters.

### Table of contents

The TOC page is now read top-to-bottom, but entries are still fragmented: dot leaders, page numbers, and entry lines are separate blocks (e.g. `Testimoni ...............`, `... v`, `..3 "Nyawa" Logika ......`). This is not a clean TOC and is listed as a remaining issue.

---

## 5. Independent ground-truth accuracy

Ground truth was transcribed from rendered PDF page images, not from OCR output. Three representative excerpts were used.

| PDF page | Excerpt | CER | WER |
|---:|---|---:|---:|
| 19 | BAB I divider (59 chars) | 0.00% | 0.00% |
| 22 | Narrative paragraph (675 chars) | 0.15% | 1.01% |
| 51 | Narrative paragraph (238 chars) | 0.00% | 0.00% |
| **Mean** | | **0.05%** | **0.34%** |

The single page-22 error is the raw OCR string `la` instead of `Ia`; the reconstruction normalises this to `Ia` (186 corrections in the book). This is a genuinely independent measurement, unlike the previous 0.00% page-29 result.

Heading classification was checked on the actual scan: page 21's all-caps section title remains `sectionHeading`, `Ucapan yang membuat il-feel` remains an H3, and `"Hmm... biasa saja."` remains a non-heading dialogue paragraph.

---

## 6. Horizontal Book Mode

Pagination was measured with a real font loaded (Arial metrics, matching the test environment) and with the reader's default typography (18 pt Palatino, 1.6 line spacing, two-page spread at ≥ 850 px).

| Layout | Pages | Blank pages | Chapters represented |
|---|---:|---:|---|
| Desktop spread (1100 × 750, two pages) | **290** | 0 | all 9 |
| Compact (600 × 800, single page) | **244** | 0 | all 9 |

Navigation was exercised on the actual book, not only on the fixture:

- next / previous page: pass, correct page content;
- ArrowRight / ArrowLeft / Space / Shift+Space: pass;
- trackpad horizontal scroll: pass;
- resize 1100×750 → 600×800: reading anchor preserved;
- chapter jump to BAB III: page 111, target node present;
- search jump: search result node present on the destination page;
- vertical scroll: none; overflow measured at 0 px after the safety net.

### Visual evidence (real fonts, actual book)

- `docs/visual_evidence/phase_3_6/02_real_book_spread_bab1.png` — BAB I spread
- `docs/visual_evidence/phase_3_6/03_real_book_spread_bab2.png` — BAB II spread
- `docs/visual_evidence/phase_3_6/04_real_book_compact_single.png` — compact single page
- `docs/visual_evidence/real_book_acceptance/06_reading_screen_book_mode.png` — actual `ReadingScreen` (not just the widget) opening the real book in Book Mode at BAB I, dark theme

Supplementary captures from the same audit: `docs/visual_evidence/real_book_acceptance/01_desktop_bab1.png`, `02_desktop_bab3.png`, `03_desktop_bab5.png`, `04_compact_bab1.png`, `05_desktop_list.png`.

The actual `ReadingScreen` integration was verified separately: the screen loads the real `Book` row and its processed JSON, mounts exactly one `PaginatedReflowableReader`, and shows no "PDF Asli recommended" banner for the good OCR derivative.

The text is readable in these captures. Remaining visual issues are described in §9.

---

## 7. In-book search

After indexing, 255 pages were searchable. Representative queries:

| Query | Results | Note |
|---|---:|---|
| `komunikasi` | 63 | includes cover/front matter |
| `memihak` | 1 | only the TOC; the BAB III title is OCR'd as `MEMHAK` |
| `cerita` | 74 | body content |
| `ucapan` | 154 | body content |

Search indexing and navigation work. The BAB III title typo limits one query; that is an OCR/content issue, not a search-engine failure.

---

## 8. Regression

| Check | Result |
|---|---|
| `flutter analyze` | **0 issues** |
| `git diff --check` | **0 whitespace/conflict errors** |
| Changed-file `dart format` | clean |
| Full suite, serial (`flutter test --concurrency=1 --timeout 180s`) | **414 / 414 passed** (3 min 4 s) |
| Real-book E2E suite | **6 / 6 passed** |
| Horizontal Book Mode suite | **13 / 13 passed** |

A parallel `flutter test` run on this machine produced timeouts in OCR-heavy tests because several suites compete for the same native Vision/DB resources; the serial run is the authoritative result.

`flutter analyze` and the test suite were run after all code changes. No commit or push was made.

---

## 9. Remaining issues

1. **TOC is fragmented.** Reading order is now correct, but entries and page numbers are separate blocks and dot leaders remain. A dedicated TOC parser is still needed for a clean contents page.
2. **BAB III title OCR error.** The chapter title reads `MEMHAK` instead of `MEMIHAK` (the TOC has `Memihak`). Search for `memihak` therefore does not find the chapter title.
3. **Paragraph splits at page boundaries.** 45 paragraphs start lower-case; 74 are shorter than 20 characters. Text is not lost, but paragraph rhythm is imperfect.
4. **No image/illustration extraction.** 0 image blocks. Scanned pages that are image-only or contain figures would not appear in Book Mode. The cover is represented as text titles, not as a cover image.
5. **Typography.** Body text is justified, which creates wide word gaps in narrow columns; navigation chevrons overlap the text near the page edges in the compact layout. Headings are large and all-caps when the scan is all-caps.
6. **No human end-to-end reading.** This audit verified representative pages, all chapter starts, navigation, and automated pagination. It did not have a human read all 255 pages for comfort.
7. **Cross-page page citation.** Cross-page paragraphs cite their start page (e.g. `PDF hal. 19, 20, 21` when slices span pages); this is informative but not a per-line source map.
8. **Version unchanged.** `pubspec.yaml` remains `1.1.0-alpha.8+9`; no version bump was made for this audit.

---

## 10. Definition of done

| Requirement | Status |
|---|---|
| OCR 255/255 complete, persisted, restart-safe | **PASS** |
| No failed pages; empty pages explained | **PASS** |
| Real chapters BAB I–V + front matter | **PASS** (9 chapters) |
| Subsection headings preserved | **CONDITIONAL** (139 headings; spot checks pass; not exhaustively ground-truthed) |
| Paragraph reconstruction | **CONDITIONAL** (45 lower-case starts) |
| Table of contents | **FAIL** (fragmented entries/page numbers) |
| Image and caption placement | **FAIL / N.A.** (0 image blocks; no illustration extraction) |
| Horizontal pagination, no blank pages | **PASS** (290 spread / 244 compact, 0 blank) |
| Previous/next, keyboard, trackpad, resize anchor | **PASS** |
| Chapter and search navigation | **PASS** (BAB III title typo caveat) |
| No vertical scrolling / clipping | **PASS** (0 px overflow measured) |
| Ground-truth CER/WER | **PASS** (manual: 0.05% CER / 0.34% WER) |
| Full regression | **PASS** (414/414) |
| Human reading acceptance | **NOT PERFORMED** |

---

## 11. Recommendation

Keep the horizontal Book Mode design. The next iteration should **not** add animations or redesign the reader. It should:

1. parse the TOC as a dedicated structure (entry + dot leader + page number);
2. correct chapter titles against the TOC (starting with `MEMHAK` → `MEMIHAK`);
3. merge paragraph continuations across page boundaries;
4. extract illustration/cover images from scanned pages;
5. run a human acceptance read of BAB I–V before calling the book finished.

The book is now readable in horizontal paginated mode; it is not yet a polished digital book.


---

## Appendix — principal files changed (uncommitted)

| File | Reason |
|---|---|
| `lib/features/processing/services/apple_vision_ocr_service.dart` | Render the full page (`fullWidth`/`fullHeight`) so OCR boxes are not compressed |
| `lib/features/processing/services/paragraph_reconstructor.dart` | OCR-specific paragraph joining, header/footer handling, `la → Ia`, `¿` and quote cleanup |
| `lib/features/processing/services/semantic_classifier.dart` | OCR heading rules driven by casing/whitespace, TOC and prologue handling |
| `lib/features/processing/services/reading_order_resolver.dart` | TOC pages forced to single-column top-to-bottom order |
| `lib/features/processing/services/semantic_document_reconstructor.dart` | Exclude back cover from BAB V |
| `lib/features/processing/services/ocr_semantic_pipeline.dart` | Mark OCR derivatives as scanned |
| `lib/features/reader/domain/engines/pagination_engine.dart` | Keep page-height estimates aligned with the renderer |
| `lib/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart` | Short navigation debounce (50 ms) and page-turn state |
| `lib/features/reader/presentation/widgets/reflowable/reflowable_page_renderer.dart` | Left-align headings; scale-down safety net against clipping |
| `lib/features/reader/presentation/screens/reading_screen.dart` | Do not show the stale "PDF Asli recommended" banner when reconstruction quality is good |
| `test/real_book_acceptance_e2e_test.dart` | Manual ground truth, semantic spot checks, real-font visual evidence |

No commit, no push. Version remains `1.1.0-alpha.8+9`.
