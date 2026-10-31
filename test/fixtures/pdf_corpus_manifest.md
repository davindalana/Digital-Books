# Representative PDF Corpus Manifest • Phase 2.7

This document catalogs the representative PDF test corpus established to benchmark, audit, and validate PDF extraction and semantic reconstruction in Digital Books.

---

## 1. Corpus Summary Table

| ID | Category | Pages | Text Layer | Embedded Images | Document Type | Key Structural Characteristics | Expected Extraction Behavior |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **CORP-01** | Single-column novel | 1 | Yes | No | Native Text | Standard body paragraphs, dialogue quotes (`"..."`), sequential vertical flow. | Extract 1 chapter heading, 3 clean paragraphs; preserve dialogue punctuation. |
| **CORP-02** | Illustrated novel | 1 | Yes | Yes (1 JPEG) | Hybrid | Headpiece / inline figure between paragraphs, italicized caption below image. | Extract image asset with dimensions/aspect ratio; associate caption; preserve text before & after. |
| **CORP-03** | Diagrams and maps | 1 | Yes | Yes (1 JPEG) | Hybrid | Technical architectural blueprint / floor plan diagram occupying center page. | Extract large diagram asset; keep diagram bound to section title; avoid flattening into text. |
| **CORP-04** | Two-column academic | 1 | Yes | No | Native Text | Title & abstract span full width; body in 2 columns (Left: X=50..280, Right: X=310..540). | Detect 2 distinct columns; read Left column top-to-bottom BEFORE Right column; no interleaving! |
| **CORP-05** | Headers & footers | 3 | Yes | No | Native Text | Running book title at Y=25, divider rule at Y=42; footer page number at Y=805, rule at Y=795. | Filter out running header and footer page numbers from main body; preserve genuine section content. |
| **CORP-06** | Footnotes | 1 | Yes | No | Native Text | Narrative prose with footnote markers `[1]`, `[2]`; divider line at Y=740; footnote text at bottom. | Distinguish footnote definitions at bottom from body text; associate citation numbers. |
| **CORP-07** | Tables and figures | 1 | Yes | No | Native Text | Financial grid with column headers (Quarter, Revenue, Net Profit, Margin) and horizontal lines. | Maintain grid cell associations; avoid concatenating row headers across columns. |
| **CORP-08** | Scanned image-only | 1 | No | Yes (1 full-page raster) | Scanned | 0 native text characters; 1 full-page raster scan bitmap (595x842 pt). | Classify page as `scannedImage`; report no text layer; recommend Original PDF Reader; no empty garbage. |
| **CORP-09** | Hybrid mixed | 3 | Mixed | Yes (2 images) | Hybrid | P1: Native text only; P2: Full-page scan only (no text); P3: Native text + embedded chart. | P1 `nativeText`, P2 `scannedImage`, P3 `hybrid`; extract chart from P3; handle heterogeneous pages. |
| **CORP-10** | Multi-heading styles | 1 | Yes | No | Native Text | Non-standard headings: Roman `III`, Quote `"All happy families..."`, Date `14 July 1789`, Number `4`. | Recognize headings by font size/weight rather than hardcoded `Bab/Chapter` regex alone. |
| **USER-LB** | Scanned literary novel (*Laut Bercerita*) | 394 | No (JBIG2 raster) | Yes (394 image masks) | Scanned | High-resolution scanned book pages; literary chapter titles; dialogue-dense prose. | Accurately detect as scanned; default to Original PDF Reader; OCR fallback if requested. |

---

## 2. Detailed Document Specifications

### CORP-01: Single-Column Novel (`01_single_column_novel.pdf`)
- **File**: `test/fixtures/corpus/01_single_column_novel.pdf`
- **Page Dimensions**: 595.0 x 842.0 pt (A4)
- **Typographical Structure**:
  - Chapter Heading: Helvetica Bold 18pt at (50, 60), text `"Chapter 1: The Beginning"`.
  - Paragraph 1: Helvetica 11pt at (50, 100), 2 lines.
  - Paragraph 2 (Dialogue): Helvetica 11pt at (50, 160), 2 lines with opening quotation mark `"`.
  - Paragraph 3: Helvetica 11pt at (50, 220), 3 lines.
- **Verification Target**: 4 text lines, correct vertical sequence, dialogue quotes intact.

### CORP-02: Illustrated Novel (`02_illustrated_novel.pdf`)
- **File**: `test/fixtures/corpus/02_illustrated_novel.pdf`
- **Embedded Asset**: JPEG image `Im1` (16x16 dummy or real JPEG) rendered at `Rect.fromLTWH(50, 150, 240, 160)`.
- **Caption**: Helvetica Italic 9pt at (50, 315): `"Figure 2.1: The cottage in the forest."`.
- **Verification Target**: Image extracted to disk; image dimensions recorded; caption recognized immediately adjacent to image.

### CORP-03: Diagrams and Maps (`03_diagrams_maps.pdf`)
- **File**: `test/fixtures/corpus/03_diagrams_maps.pdf`
- **Embedded Asset**: Full-width diagram `Rect.fromLTWH(50, 120, 400, 250)`.
- **Verification Target**: Image dimensions preserved; aspect ratio (400:250 = 1.6) calculated correctly.

### CORP-04: Two-Column Academic Document (`04_two_column_academic.pdf`)
- **File**: `test/fixtures/corpus/04_two_column_academic.pdf`
- **Geometry**:
  - Full-width title at (50, 50).
  - Left Column: X in `[50, 280]`, Y in `[90, 300]`. Contains Abstract and Section I.
  - Right Column: X in `[310, 540]`, Y in `[90, 300]`. Contains Section II and Section III.
- **Critical Reading Order Check**:
  - Must read Left Column completely (Abstract -> Section I) BEFORE jumping to Right Column (Section II -> Section III).
  - **Failure Condition**: Any algorithm that sorts purely by Y coordinate will produce: Abstract line 1 -> Section II line 1 -> Abstract line 2 -> Section II line 2 (garbled reading order).

### CORP-05: Headers and Footers (`05_headers_footers.pdf`)
- **File**: `test/fixtures/corpus/05_headers_footers.pdf` (3 pages)
- **Geometry**:
  - Running Header: Y=25, height=15pt, text `"THE ADVENTURES OF SHERLOCK HOLMES"`.
  - Header Divider Line: Y=42.
  - Running Footer: Y=805, height=15pt, text `"Page X of 3"`.
  - Footer Divider Line: Y=795.
- **Verification Target**: Geometrically filtered out from body text.

### CORP-06: Footnotes (`06_footnotes.pdf`)
- **File**: `test/fixtures/corpus/06_footnotes.pdf`
- **Geometry**:
  - Body Text: Y in `[50, 150]`, font size 11pt, contains references `[1]` and `[2]`.
  - Divider Line: Y=740.
  - Footnote 1: Y=750, font size 8pt.
  - Footnote 2: Y=768, font size 8pt.
- **Verification Target**: Footnotes at Y > 730 separated from main body; 8pt font size distinguished from 11pt body.

### CORP-07: Tables and Figures (`07_tables_figures.pdf`)
- **File**: `test/fixtures/corpus/07_tables_figures.pdf`
- **Geometry**:
  - Columns at X=50 (Quarter), X=180 (Revenue), X=310 (Net Profit), X=440 (Margin).
- **Verification Target**: Table rows identified without interleaving cells.

### CORP-08: Scanned Image-Only PDF (`08_scanned_image_only.pdf`)
- **File**: `test/fixtures/corpus/08_scanned_image_only.pdf`
- **Geometry**: 1 page, 0 text strings, 1 full-page raster image covering (0, 0, 595, 842).
- **Verification Target**: Classified as `PageLayerType.scannedImage`; 0 false text lines hallucinated; recommended reading mode: Original PDF Reader.

### CORP-09: Hybrid Mixed Document (`09_hybrid_mixed.pdf`)
- **File**: `test/fixtures/corpus/09_hybrid_mixed.pdf` (3 pages)
- **Geometry**:
  - Page 1: Native text only (`PageLayerType.nativeText`).
  - Page 2: Full-page scan only (`PageLayerType.scannedImage`).
  - Page 3: Native text + embedded chart image (`PageLayerType.hybrid`).
- **Verification Target**: Page-level classification is heterogeneous: `[nativeText, scannedImage, hybrid]`.

### CORP-10: Multi-Heading Styles (`10_multi_heading_styles.pdf`)
- **File**: `test/fixtures/corpus/10_multi_heading_styles.pdf`
- **Styles Included**:
  - Roman Numeral: `III` (20pt Bold)
  - Literary Quote: `"All happy families are alike..."` (14pt Italic)
  - Date / Historical: `14 July 1789 — Bastille Day` (13pt Bold)
  - Plain Numeral: `4` (22pt Bold)
- **Verification Target**: All 4 headings identified by font size/weight differential (`fontSize > 12pt`), not by string regex matching.

