# BOOK MODE — DEEP LAYOUT DEBUGGING & READING EXPERIENCE REDESIGN

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus I — Core Engine & Document Pipeline (v1.0 s.d. v1.1)
> - **Modul / Kategori**: Book Mode Deep Layout Debugging & Reading Experience Redesign
> - **Urutan Dokumen**: Laporan 02 dari 05 pada Book Mode Redesign
> - **Tanggal**: 7 November 2026
> - **Status Verifikasi**: **PASS**

---

**Date**: 7 November 2026
**Book**: *Bicara Itu Ada Seninya* (Oh Su Hyang, 255 scanned pages)
**Book ID**: `7b3dcbf3-0f23-4c6d-8044-d525257dac00`
**Original PDF**: `~/Documents/DigitalBooks/originals/7b3dcbf3-0f23-4c6d-8044-d525257dac00.pdf` (66,783,602 bytes, SHA-256 `ce0c5eea…b0da233`)
**Database**: `~/Documents/digital_books_db.sqlite`
**Derivative**: `~/Documents/DigitalBooks/books/7b3dcbf3-0f23-4c6d-8044-d525257dac00.json`

## Verdict

**CONDITIONAL PASS — the book now reads like a book, with documented limitations.**

The front matter is structured, legal clauses are readable, the TOC has real entries with page labels, body text is left-aligned and comfortable, and chapter openings have a clear hierarchy. The remaining blockers are image/illustration extraction, the OCR typo in the BAB III title, a small number of cross-page paragraph fragments, and the absence of a human 30–60 minute reading session.

---

## 1. Root cause analysis

The screenshot was not a colour or font problem. The pipeline was producing semantically wrong blocks and the renderer was faithfully displaying them.

### 1.1 Front matter was processed as body prose

`ParagraphReconstructor` merges OCR lines using body-text rules. On the cover and copyright pages it merged display lines into one giant all-caps block:

> `BIP KELOMPOK GRAMEDIA THE SECRET HABITS … BICARA ADA ITU SENINYA … (DOSEN & PAKAR …) SELLER`

The same pass treated publisher metadata, ISBN, translator/editor lines and legal notices as ordinary paragraphs. The cover and copyright page therefore became a wall of text with no roles.

**Fix:** a dedicated `FrontMatterReconstructor` owns the leading pages (0…contentStart-1), splits the cover into publisher logo / English title / main title / subtitle / author / credential / badge, and groups copyright metadata into identity, catalog, publisher and legal notices. It also inserts semantic page breaks between cover, copyright and title pages.

### 1.2 Legal clauses were split and misclassified

The original blocks contained:

- clause 1 split into three blocks, including a continuation block starting `(satu) tahun …`;
- clause 3 and clause 4 classified as `footnote`;
- list markers rendered as gold UI badges detached from the legal text.

**Fix:** the copyright parser joins continuation lines into four atomic `orderedList` blocks with `legalClause: true`, `listMarker`, and page-break protection. The renderer uses a plain hanging number in a legal-text style instead of a decorative badge.

### 1.3 TOC was a pile of OCR lines

TOC titles, dot leaders and page labels arrive on separate OCR lines (`Testimoni ...............`, `... v`, `..3 "Nyawa" Logika ......`). The generic paragraph pass kept them as separate body paragraphs.

**Fix:** `TocReconstructor` pairs title lines with page labels by vertical position, merges title continuations, parses chapter labels (`Bab I|I` → `BAB III`), and emits `tocEntry`, `tocChapterLabel` and `tocChapterTitle` blocks. The renderer draws a real TOC row: title, dot leader, page label.

### 1.4 Typography forced justification

`TypographySettings` defaulted to `TextAlign.justify`. In a 490–520 px column this produced large inter-word gaps, especially on the copyright and legal pages.

**Fix:** body default is now `TextAlign.left`; justification remains available as an opt-in setting. Headings, lists, metadata and TOC entries are always left-aligned.

### 1.5 Chapter titles were giant all-caps blocks

`BAB I: PERBEDAAN …` was rendered as one 1.45× bold justified heading. There was no distinction between chapter marker and chapter title.

**Fix:** for uppercase `BAB/CHAPTER <number>: <title>` headings the renderer now draws a small gold `BAB I` kicker and a 1.22× left-aligned title. Mixed-case headings (e.g. `Bab 1: Dikotomi Kendali`) keep the generic heading path for compatibility.

### 1.6 Front matter pages had the wrong page furniture

The cover and title page showed the running header `BAGIAN AWAL`, page numbers, and a top-aligned block. The cover and copyright page also flowed into the same page because there was no page boundary.

**Fix:** front matter pages hide the running header; cover/title pages hide the page footer; cover/title/slogan pages are vertically centred. Semantic `pageBreak` blocks separate cover, copyright and title pages. Copyright pages use compact metadata with section labels (`INFORMASI PENERBITAN`, `PENERBIT`, `HAK CIPTA`).

### 1.7 Pagination clipped or split content badly

`FittedBox(scaleDown)` prevented clipping but text could still be split in the middle of a legal clause. Legal clauses are now atomic in `PaginationEngine`, so clause 4 moves whole to the next page instead of splitting mid-sentence.

---

## 2. Architecture decisions

1. **Keep the existing pagination engine and reader.** No second reader or vertical-scroll path was introduced.
2. **Semantic structure before presentation.** Front matter and TOC are reconstructed as semantic blocks before the page renderer sees them.
3. **Use metadata, not new widget types, for presentation roles.** `frontMatter`, `kind`, `sectionLabel`, `tocTitle`, `tocPage`, `legalClause` travel through `BookBlock.metadata` into `ContentNode.attributes`.
4. **Add a semantic page-break type.** `SemanticBlockType.pageBreak` maps to `BlockType.pageBreak`, which the existing pagination engine already understands.
5. **Preserve anchors and search offsets.** Front matter/TOC blocks keep stable IDs and source pages; body text remains unchanged except for legal-clause grouping and the existing OCR cleanup.
6. **Do not invent chapters or headings.** Front matter labels and TOC entries come from the OCR lines; the canonical cover title is taken from the title page when available.

---

## 3. Files changed

| File | Change |
|---|---|
| `lib/features/processing/services/front_matter_reconstructor.dart` | **New.** Cover, title, copyright, publisher and legal front matter reconstruction. |
| `lib/features/processing/services/toc_reconstructor.dart` | **New.** TOC entry/page-label pairing and chapter labels. |
| `lib/features/processing/services/semantic_document_reconstructor.dart` | Runs front-matter/TOC passes, merges blocks by source page, keeps generic prose off owned pages. |
| `lib/features/processing/models/semantic_reconstruction_models.dart` | Adds `SemanticBlockType.pageBreak` and reader mapping. |
| `lib/features/reader/presentation/widgets/reflowable/reflowable_page_renderer.dart` | Front matter roles, chapter opener, legal list, TOC rows, section labels, header/footer rules. |
| `lib/core/typography/typography_settings.dart` | Default body alignment changed from justify to left. |
| `lib/features/reader/domain/engines/pagination_engine.dart` | Legal clauses are atomic; page-break blocks already supported. |
| `test/book_mode_reading_experience_test.dart` | **New.** Cover, legal, TOC, typography and page-break regression tests. |
| `docs/visual_evidence/book_mode_redesign/*` | Before/after evidence from the real book. |

---

## 4. Typography specification

| Role | Size | Weight / style | Alignment |
|---|---|---|---|
| Body | 18 pt | normal, line-height 1.65, paragraph spacing 14 | left |
| Chapter marker | 0.68 × body | bold, letterSpacing 2.2, gold | left |
| Chapter title | 1.22 × body | bold, line-height 1.28 | left |
| Section heading (H2) | 1.15 × body | bold, gold rule | left |
| Subsection (H3) | 1.10 × body | bold | left |
| Cover main title | 1.35 × body | bold, line-height 1.18 | centered |
| Cover English title | 0.74 × body | bold, letterSpacing 1.8, secondary | centered |
| Cover subtitle | 0.95 × body | normal, secondary | centered |
| Author | 1.08 × body | bold | centered |
| Credential | 0.76 × body | italic, secondary | centered |
| Publisher / logo | 0.72 × body | w600, letterSpacing 1.3–1.6, secondary | centered |
| Copyright metadata | 0.78–0.80 × body | normal, secondary, line-height 1.55 | left |
| Legal clause | 0.80 × body | normal, secondary, hanging number | left |
| TOC entry | 0.88 × body | normal, dot leader + page label | left |
| TOC chapter label | 0.70 × body | bold, gold, letterSpacing 1.5 | left |
| TOC chapter title | 1.02 × body | bold | left |

Page geometry: 32 px outer margin (24 px on narrow pages), 18 px gutter safety, 28 px header zone, 24 px footer zone. Body text no longer uses forced justification.

---

## 5. Semantic reconstruction result

| Chapter | Blocks | Notes |
|---|---:|---|
| 0. Bagian Awal | 26 | cover, copyright, legal, title page, page breaks |
| 1. Testimoni | 19 | |
| 2. Prolog | 13 | |
| 3. Daftar Isi | 57 | 46 structured TOC entries + 5 chapter labels/titles |
| 4. BAB I | 189 | |
| 5. BAB II | 293 | |
| 6. BAB III | 156 | title still contains OCR typo `MEMHAK` |
| 7. BAB IV | 276 | |
| 8. BAB V | 199 | |

Totals: **1,228 blocks**, 839 paragraphs, 140 headings (8 H1, 22 H2, 110 H3), 68 ordered lists, 62 unordered lists, 40 quotes, 2 copyright blocks, 2 page breaks, 1 footnote, 0 images.

- 45 paragraphs still begin with a lower-case continuation; 55 are shorter than 20 characters.
- The front matter no longer contains a single giant title block; it has 4 `documentTitle` blocks, 14 metadata blocks and 1 copyright block.
- Legal clauses 1–4 are four atomic blocks.

---

## 6. Before / after evidence (same real book)

### Front matter (cover + copyright)

Before (user screenshot, 7 Nov 2026): [before_front_matter.png](../../../visual_evidence/book_mode_redesign/before_front_matter.png)

After: [after_front_matter.png](../../../visual_evidence/book_mode_redesign/after_front_matter.png)

The after spread shows a centered cover with publisher logo, English title, Indonesian title, subtitle, author and credential on the left; `INFORMASI PENERBITAN` and `PENERBIT` sections on the right. No `BAGIAN AWAL` header or page number on the cover.

### Body chapter I (same spread)

Before (HEAD, light theme): [before_body_bab1.png](../../../visual_evidence/book_mode_redesign/before_body_bab1.png)

After (light theme): [after_body_bab1_light.png](../../../visual_evidence/book_mode_redesign/after_body_bab1_light.png)

The after page has a `BAB I` kicker, left-aligned body text, normal word spacing, and a clear H2/H3 hierarchy.

### Other pages

- [after_toc.png](../../../visual_evidence/book_mode_redesign/after_toc.png) — TOC with dot leaders and page labels.
- [after_legal.png](../../../visual_evidence/book_mode_redesign/after_legal.png) — legal page with hanging numbers and atomic clauses.
- [after_reading_screen.png](../../../visual_evidence/book_mode_redesign/after_reading_screen.png) — actual `ReadingScreen` in Book Mode.

---

## 7. Real-book validation

| Check | Result |
|---|---|
| OCR | 255/255 completed, 0 failed, 268,233 chars, mean confidence 99.85% |
| Manual CER / WER | 0.05% / 0.34% on three transcribed excerpts |
| Chapters | 9 real chapters, no invented chapters |
| Pagination (1102×951 two-page) | **222 leaves**, 0 blank |
| Pagination (600×800 single-page) | **245 leaves**, 0 blank |
| Overflow | 0 px after scale-down safety net and atomic legal clauses |
| Navigation | next/prev, arrows, space, trackpad, resize anchor, chapter jump, search jump |
| Actual `ReadingScreen` | loads the real Book row and processed JSON, shows Book Mode at BAB I |
| Search index | 255 pages; “komunikasi” 63, “cerita” 74, “ucapan” 154 results |

Page counts depend on the window size. At the user's screenshot size (1102×951), the real book reflows to **222 two-page leaves**; at 1100×750 the body comparison reflows to 291 (the old build produced 290), and the compact 600×800 layout produces 245. The 1102×951 count is higher than the 159 pages in the user's before screenshot because the new typography uses larger body text, paragraph spacing and front-matter/TOC pages instead of dense all-caps blocks.

---

## 8. Regression & build

| Check | Result |
|---|---|
| `flutter analyze` | 0 issues |
| `git diff --check` | 0 errors |
| New reading-experience tests | 5/5 pass |
| Full suite | **419 / 419 passed** (serial, 2 min 53 s) |
| Native macOS release build | **PASS** — `build/macos/Build/Products/Release/Digital Books.app` (37.1 MB); linker emitted non-fatal Metal toolchain search-path warnings |

---

## 9. Known limitations

1. **BAB III chapter title still reads `MEMHAK`** instead of `MEMIHAK`. The TOC has the correct `Memihak`; a title-correction pass against TOC remains open.
2. **No image/illustration extraction.** 0 image blocks. The scanned book is mostly text, but figure pages would not appear in Book Mode.
3. **45 lower-case paragraph starts** and 55 short paragraphs remain from page-boundary/OCR segmentation.
4. **Later TOC index page** (testimonial names/works) still merges some name lines with the following work title; the main BAB I–V TOC is clean.
5. **Legal page 4 is sparse** (clause 4 + footer) because clauses are atomic; a smarter distribute/keep-with-next policy could balance it.
6. **Human 30–60 minute reading acceptance was not performed.** This report is based on automated pagination, representative real-book screenshots, and structural checks.
7. **Screenshots are Flutter integration renders of the real `ReadingScreen`/reader with production font and real book data, not an OS-level window capture.** The native macOS release build was verified separately (`build/macos/Build/Products/Release/Digital Books.app`).
8. Chapter titles preserve the source all-caps style; no automatic title-casing is applied to content.
9. The real app uses the saved reading theme (black in the evidence); production font is Literata when Google Fonts is available, with Palatino/Georgia fallback in tests.

---

## 10. Git

- Branch: `main`
- Last commit: `c4e8235 Version 1.2.1 test: update real book acceptance report and E2E test suite with visual evidence`
- Commit/push: **none made** (per instruction)
- Version: `1.1.0-alpha.8+9` (unchanged)
- Working tree: modified source, new tests, new visual evidence.

---

## 11. Acceptance

**CONDITIONAL PASS.** The reading experience is materially better and the real book is readable in horizontal Book Mode, but the limitations above prevent a clean PASS.
