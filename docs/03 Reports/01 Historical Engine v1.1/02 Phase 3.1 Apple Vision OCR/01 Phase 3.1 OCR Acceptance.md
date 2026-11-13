# PHASE 3.1 — LOCAL-FIRST BACKGROUND OCR PIPELINE ACCEPTANCE AUDIT

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus I — Core Engine & Document Pipeline (v1.0 s.d. v1.1)
> - **Modul / Kategori**: Phase 3.1 Apple Vision OCR Engine Acceptance
> - **Urutan Dokumen**: Laporan 01 dari 03 pada Phase 3.1 Apple Vision OCR
> - **Tanggal**: 2 November 2026
> - **Status Verifikasi**: **PASS**

---

## 1. Executive Summary

Phase 3.1 implements a production-grade, local-first background Optical Character Recognition (OCR) pipeline for scanned PDF books in Digital Books. 

Prior to Phase 3.1, scanned image-only PDF documents lacked selectable text and could only be viewed in the Original PDF Reader. Phase 3.1 bridges this gap by recognizing text directly on the user's macOS device using Apple's Neural Engine via the Vision Framework, persisting recognized geometry in a local Drift SQLite cache, and running the semantic document reconstruction engine to generate a structured, reflowable, and fully searchable `BookDocument`.

The pipeline adheres strictly to all project principles:
- **Local-first & offline**: 100% native execution via macOS Apple Vision (`VNRecognizeTextRequest`). Zero external APIs, zero telemetry, zero cloud dependencies.
- **Document immutability**: The original scanned PDF file is never modified or overwritten. Reconstructed books are stored as structured derivatives in `books_processed/<bookId>.json`.
- **Unified document model**: Direct conversion from `OcrPageResult` to `ExtractedPageGeometry`, seamlessly feeding into existing `ReadingOrderResolver`, `ParagraphReconstructor`, `SemanticClassifier`, and `ReflowableEngine`.
- **Memory bounded**: Page-by-page streaming queue renders and processes one page at a time. The entire book is never loaded into RAM simultaneously.
- **Resumable & fault-tolerant**: Page-level status tracking in Drift database allows instant resumption after app termination, skipping previously completed pages.

---

## 2. Checkpoint Verification Matrix

| Checkpoint | Module / Deliverable | Status | Verified By |
| :--- | :--- | :--- | :--- |
| **Checkpoint A** | Apple Vision OCR Engine (`vision_ocr.swift`, `bin/vision_ocr`, `AppleVisionOcrService`) | **PASS** | `test/phase_3_1_apple_vision_ocr_test.dart` (6/6 tests passing) |
| **Checkpoint B** | Drift v4 Schema Migration & `OcrPages` Table Persistence | **PASS** | `test/phase_3_1_ocr_persistence_test.dart` (3/3 tests passing) |
| **Checkpoint C** | Background Processing Queue (Resumable, Pause/Resume, Cancel, Retry) | **PASS** | `test/phase_3_1_background_ocr_queue_test.dart` (4/4 tests passing) |
| **Checkpoint D** | Semantic Document Reconstruction (`OcrSemanticPipeline` $\to$ `BookDocument`) | **PASS** | `test/phase_3_1_ocr_semantic_pipeline_test.dart` (1/1 test passing) |
| **Checkpoint E** | Reflowable Reader Integration (Mode Switch, Anchor Mapping, In-Book Search) | **PASS** | `test/phase_3_1_reflowable_integration_test.dart` (2/2 tests passing) |
| **Checkpoint F** | Native macOS Real Corpus Benchmark & Acceptance Audit | **PASS** | `test/phase_3_1_real_acceptance_audit_test.dart` (3/3 tests passing) |

---

## 3. Quantitative Performance & Benchmark Results

Benchmarked on native Apple Silicon hardware across real scanned PDF novel corpus:
1. ***Laut Bercerita*** (Leila S. Chudori) — Indonesian scanned novel, uneven margins, heavy dialogue.
2. ***Bicara Itu Ada Seninya*** (Oh Su Hyang) — Korean-Indonesian translation, structured headings, numbered lists.
3. ***The Devotion of Suspect X*** (Keigo Higashino) — English translation, dialogue, dense prose.

### Multi-Book Throughput Benchmark (5 Pages / Book)

| Book Title | Language Models | Pages Tested | Engine OCR Latency | Total Wall Latency | Latency / Page | Chars Extracted | Semantic Blocks | Chapters |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Laut Bercerita** | `id-ID`, `en-US` | 15 – 19 | 238.6 ms | 1,698 ms | **339.6 ms** | 6,625 | 28 | 1 |
| **Bicara Itu Ada Seninya** | `id-ID`, `en-US` | 31 – 35 | 233.9 ms | 1,656 ms | **331.2 ms** | 6,378 | 56 | 3 |
| **The Devotion of Suspect X** | `en-US`, `id-ID` | 11 – 15 | 235.0 ms | 1,568 ms | **313.6 ms** | 7,454 | 39 | 1 |

### Performance Budget Compliance

| Metric | Budget Target | Actual Measurement | Status |
| :--- | :--- | :--- | :---: |
| **OCR Latency per Page** | $\le 500\text{ ms/page}$ | **313.6 – 339.6 ms/page** | **PASS** |
| **Apple Neural Engine OCR Only** | $\le 300\text{ ms/page}$ | **233.9 – 238.6 ms/page** | **PASS** |
| **Memory RSS Delta (15 Full Pages)** | $\le 200\text{ MB}$ | **150.88 MB** | **PASS** |
| **Peak Process RSS** | $< 500\text{ MB}$ | **335.72 MB** | **PASS** |
| **Average Recognition Confidence** | $\ge 0.95$ | **0.998 – 1.000** | **PASS** |
| **UI Event Loop Yielding** | $\ge 10\text{ ms/page}$ | **10 ms deliberate delay** | **PASS** |

---

## 4. Qualitative Reconstruction Fidelity

### A. Scanned Indonesian Prose (*Laut Bercerita*, Page 15)
- **Input Page**: 958 $\times$ 1418 px scanned image with uneven photocopy curvature and dialogue hyphens.
- **OCR Engine Extraction**: 29 lines recognized with 1.00 confidence.
- **Hyphenation Reconciliation**: Line wrap `"se-"` + `"buah"` was seamlessly joined into `"sebuah"`; `"me-"` + `"narikku"` merged into `"menarikku"`.
- **Dialogue Recognition**: Quotes (`"..."`) and punctuation marks preserved accurately.
- **Reconstructed Sample**:
  > *"Setelah lebih dari sejam kami berada di atas mobil dengan mata yang masih ditutup dan tangan terikat, akhirnya si Manusia Pohon menarikku keluar mobil dan bersama yang lain..."*

### B. Structured Book Layout (*Bicara Itu Ada Seninya*, Page 33)
- **Input Page**: 595 $\times$ 842 pt scan with centered section titles, indented paragraph starters, and numbered advice items.
- **Indentation Handling**: Successfully distinguished 4 indented paragraph starters from 26 flush body lines.
- **Semantic Classification**: Correctly partitioned into 3 logical chapters/subsections with distinct headings.

### C. In-Book Searchability on Derived Content
- Verified with `InBookSearchEngine.search(document: readerDoc, query: 'mobil')`.
- Found exact match in node bound to `sourcePdfPage: 15`.
- Seamless cross-mode navigation: Clicking a search result jumps to Reflowable anchor, and switching to PDF mode navigates directly to page 15 of the original PDF.

---

## 5. Architectural Components Delivered

1. **Native Helper Tool**:
   - `macos/tools/vision_ocr.swift`: Swift CLI utilizing `Vision.framework` and `VNRecognizeTextRequest`.
   - `bin/vision_ocr`: Pre-compiled universal binary optimized with `-O`.
2. **Data Model & Services**:
   - `lib/features/processing/models/ocr_page_result.dart`: `OcrLine`, `OcrPageResult`, coordinate normalization and conversion to `ExtractedPageGeometry`.
   - `lib/features/processing/models/ocr_queue_state.dart`: Reactive queue status model (`idle`, `running`, `paused`, `completed`, `cancelled`, `error`), progress percentage, and time estimation.
   - `lib/features/processing/services/apple_vision_ocr_service.dart`: Process bridge for single-page and rendered PDF page OCR.
   - `lib/features/processing/services/background_ocr_queue.dart`: Memory-bounded streaming queue with pause, resume, cancel, and retry capabilities.
   - `lib/features/processing/services/ocr_semantic_pipeline.dart`: Bridges stored `OcrPages` with `SemanticDocumentReconstructor` and updates database.
   - `lib/features/processing/providers/background_ocr_provider.dart`: Riverpod integration for queue, progress stream, and semantic pipeline.
3. **Database Schema v4**:
   - `lib/core/database/tables.dart`: Added `OcrPages` table with cascading foreign key to `Books`.
   - `lib/core/database/app_database.dart`: Added migration to schema version 4 (`createTable(ocrPages)`).
   - `lib/core/database/database_service.dart`: Added CRUD methods: `insertOcrPage`, `getOcrPage`, `getOcrPagesForBook`, `watchOcrPagesForBook`, `deleteOcrPagesForBook`, `getCompletedOcrPageCount`, and `updateBookProcessedPath`.
4. **Reader & Library UI Enhancements**:
   - `lib/features/reader/presentation/screens/reading_screen.dart`:
     - Listens to background OCR queue stream.
     - Displays live non-intrusive progress pill in App Bar (`OCR: 15/379 (4%)`).
     - Offers "Mulai OCR" action pill when reflowable document is missing.
     - Auto-loads `_document` upon OCR completion, instantly revealing the "Book / PDF" toggle.
   - `lib/features/library/presentation/widgets/book_details_dialog.dart`:
     - Displays OCR and Reflowable availability status.
     - Shows live background OCR progress bar with Pause/Resume and Cancel controls.
     - Enables "Read Book" in Reflowable mode once OCR is completed.

---

## 6. Verification & Test Summary

All automated tests in the Digital Books repository passed:
- **Phase 3.1 Test Suite**: 19 / 19 tests passed (`flutter test test/phase_3_1_*.dart`).
- **Full Test Suite**: 272 / 272 tests passed across the entire project.
- **Static Analysis**: `flutter analyze` reports 0 issues.
- **Code Style & Formatting**: `git diff --check` clean.

**DECISION: PASS**.
The local-first background OCR pipeline is fully functional, stable, and ready for production use.
