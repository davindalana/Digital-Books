# Changelog

All notable changes to the **Digital Books** application are documented in this file.

---

## [1.1.0-alpha.5] - Visual Regression & Pagination Stress Validation (Phase 2.8.1)

### Fixed
- **Geometry Alignment in `paginateDocument`**:
  - Aligned default non-content deduction in `PaginationEngine.paginateDocument` from 124 pt to 68 pt (`headerHeight = 28.0`, `footerHeight = 24.0`, `verticalPadding = 8.0`), matching `paginateChapter` and `ReflowablePageRenderer` to permanently eliminate the 56 pt artificial gap at the bottom of pages.
- **Max Content Width Clamping**:
  - Aligned maximum content width in `PaginationEngine` to `isTwoPageSpread ? 800.0 : 900.0 pt`, matching `PaginatedReflowableReader` and eliminating line wrapping discrepancies on ultrawide viewports.
- **Vertical Padding Budgeting**:
  - Calibrated heading vertical padding ($24.8\text{ pt}$), footnote vertical padding ($12.4\text{ pt}$), and quote container vertical padding ($8.0\text{ pt}$) to match exact widget decorations.
- **Elimination of Word-Slicing Fallback in `_findBestWordBreak`**:
  - Prevented forced 50% character-count split when remaining text slightly exceeds height budget. Slices now clamp to `text.length - 1` and walk backward to the nearest whitespace boundary, guaranteeing words are never cut in half.
- **Continuation Whitespace Elimination**:
  - Advances `charStart` past trailing spaces so continuation slices on facing pages do not begin with accidental indentation or stray whitespace.
- **Roman Numeral Chapter Heading Guard**:
  - Constrained standalone Roman numeral matching in `SemanticClassifier` to single-line blocks situated in the top 70% of a page, preventing false positive headings on outline items or tables.

### Added
- **Phase 2.8.1 Visual Regression & Pagination Stress Test Suite (`test/phase_2_8_1_visual_regression_test.dart`)**:
  - Mathematical 1:1 geometry alignment across narrow, medium, wide, and ultrawide viewports.
  - Word boundary preservation across font sizes (12, 16, 19, 24 pt) and line spacings (1.2, 1.5, 1.8).
  - Orphan heading prevention and caption in-stream budgeting.
  - Real-world document stress on *The Devotion of Suspect X* and *48 Laws of Power*.
  - 179/179 automated tests passing with 0 `flutter analyze` issues.

---

## [1.1.0-alpha.4] - Reading Quality Validation & Refinement (Phase 2.8)

### Fixed
- **Pagination Geometry & Double-Margin Elimination**:
  - Aligned non-content deductions between `PaginationEngine.paginateChapter` and `ReflowablePageRenderer` from 124 pt to 68 pt (`headerHeight = 28.0`, `footerHeight = 24.0`, `verticalPadding = 8.0`), eliminating the artificial dead-zone at the bottom of pages.
  - Removed redundant pre-halving and pre-margin deduction in `PaginatedReflowableReader._ensureLayout` and `_recalculateLayoutPreservingAnchor`, passing full layout constraints directly to `PaginationEngine` and eliminating line wrap measurement discrepancies.
- **Bidirectional Reading Position Synchronization**:
  - Synchronized reader switching between Reflowable and Original PDF modes:
    - Reflowable $\to$ PDF: Resolves active `ContentNode.sourcePdfPage` and sets `_pdfPage` directly to that exact physical PDF page.
    - PDF $\to$ Reflowable: Scans for the first `ContentNode` with `sourcePdfPage >= _pdfPage`, resolves anchor ID and chapter, and jumps smoothly to that position.
- **Referential Document Stability**:
  - Memoized `_readerDocument` in `ReadingScreen` (`_readerDocument ??= ReflowableEngine.normalizeDocument(...)`) to eliminate infinite layout re-render loops on frame builds.
- **Novel Heading Structure**:
  - Expanded `SemanticClassifier` H1 detection to recognize standalone non-standard headings common in novels: "Prolog", "Epilog", "Introduction", "Kata Pengantar", uppercase standalone chapter titles, and standalone Roman numerals (`I`, `II`, `III`, etc.).
- **Paragraph Cross-Page Continuity**:
  - Refined `ParagraphReconstructor` boundary rules to prevent accidental fragmentation of continuous sentences spanning across physical PDF page breaks.

### Added
- **Phase 2.8 Reading Quality & Mode Switch Test Suite (`test/phase_2_8_reading_quality_test.dart`)**:
  - Validates novel heading recognition (`Prolog`, `III`, `Epilogue`).
  - Validates exact single-deduction geometry in `PaginationEngine`.
  - Validates bidirectional mode switching and page mapping in `ReadingScreen`.
  - Validates real-world structural integrity across imported library books (e.g. *The Devotion of Suspect X* with 20 chapters and 1,907 paragraphs).
  - 171/171 automated tests passing with 0 `flutter analyze` issues.

### Added
- **End-to-End Modernized Pipeline**: Integrated `GeometryAwarePdfExtractor` and `SemanticDocumentReconstructor` into `PdfProcessingPipeline.processAndImportPdf()`, retiring legacy plain-text splitting.
- **Natural Paragraph Integrity Protection**: Added `reconstructionQuality` guards in `BookTextNormalizer` and `ReflowableEngine` to preserve natural paragraph bounds (>280 chars) without artificial regex slicing.
- **Footnote Semantic Rendering**: Added `ContentNodeType.footnote` across `ReaderDocument`, `PaginationEngine`, `ReflowablePageRenderer`, and `ScrollingReflowableReader` with 85% typography scale, italic styling, and secondary text contrast.
- **Image & Caption In-Stream Presentation**: Updated `PaginationEngine` and page renderers to compute dynamic vertical overhead for captions (+28 pt) and display captions beneath illustrations.
- **Intelligent Reader Tier Recommendation Banner**: Added dismissible `QualityRecommendationBanner` in `ReadingScreen` for scanned or partial documents, including an immediate `[Buka PDF Asli]` switch action.
- **Real-World Document Benchmarking Suite (`test/phase_2_7e_real_world_validation_test.dart`)**:
  - Validated *The Let Them Theory* (265 pages, native vector text): geometry extracted in 2,782 ms (10.5 ms/page), semantic reconstruction in 52 ms, 0.97 quality score.
  - Validated scanned fallback (*Laut Bercerita*, 394 pages, JBIG2): detected as scanned, triggering the original PDF recommendation banner without layout disruption.
  - 167/167 automated tests passing with 0 `flutter analyze` issues.

---

## [1.1.0-alpha.2] - Semantic Reconstruction Engine (Phase 2.7D)

### Added
- **Reading Order Reconstruction (`ReadingOrderResolver`)**: Spatially aware line clustering, two-column gutter detection ($\ge 14.0\text{ pt}$), full-width title/banner precedence, and strictly separated column flows without line interleaving.
- **Paragraph Reconstruction (`ParagraphReconstructor`)**: Line gap analysis ($\Delta Y > 1.45 \times \text{modalGap}$), first-line indent detection, de-hyphenation, dialogue preservation, and cross-page sentence stitching while filtering running chrome.
- **Semantic Classification (`SemanticClassifier`)**: Document-wide modal font analysis, H1-H3 heading hierarchy, block quotes, footnote isolation via index markers and smaller font size, and header/footer filtering.
- **Image Placement & Caption Binding (`ImagePlacementResolver`)**: Spatial caption matching to embedded images, role classification (`coverImage`, `diagram`, `fullPageIllustration`, `inlineFigure`), and in-stream positioning.
- **Reconstruction Quality Assessment (`ReconstructionQualityAnalyzer`)**: Quantitative scoring (0.0 to 1.0) and tier recommendation (`good`, `partial`, `poor`) routing low-confidence or scanned books to `Original PDF Reader`.
- **Master Orchestrator (`SemanticDocumentReconstructor`)**: Unified service coordinating D1–D5 and outputting `ReconstructedDocument` convertible to `BookDocument`.
- **Automated Regression Suite (`test/phase_2_7d_semantic_reconstruction_test.dart`)**: 12 comprehensive tests covering all 10 corpus categories plus the real-world 394-page book *Laut Bercerita*.

---

## [1.1.0-alpha.1] - Representative PDF Corpus & Geometry-Aware Extraction (Phase 2.7B & 2.7C)

### Added
- **Representative PDF Corpus & Generator**: Programmatic corpus generator (`test/helpers/corpus_pdf_generator.dart`) creating 10 test PDF categories (single column novel, illustrated novel, diagrams/maps, two-column academic, headers/footers, footnotes, tables/figures, scanned image, hybrid, and multi-heading styles) plus corpus manifest (`test/fixtures/pdf_corpus_manifest.md`).
- **Intermediate Geometry Extraction Models**: Introduced `ExtractedPageGeometry`, `ExtractedTextLine`, `ExtractedTextWord`, `ExtractedImage`, and `PageLayerType` (`nativeText`, `scannedImage`, `hybrid`, `emptyOrUnsupported`) in `lib/features/processing/models/extracted_page_geometry.dart`.
- **Geometry-Aware PDF Extractor**: Implemented `GeometryAwarePdfExtractor` (`lib/features/processing/services/geometry_aware_pdf_extractor.dart`) utilizing `extractTextLines()` for precise 2D line and word bounding boxes, font attributes, and direct `/XObject /Image` DCTDecode stream harvesting directly to disk without lossy re-encoding.
- **Page-Level Layer Classifier**: Per-page classification distinguishing native vector text, scanned pure-image pages, and hybrid pages to route documents intelligently.
- **Automated Regression & Benchmark Suite**: 9 unit tests (`test/phase_2_7_extraction_test.dart`), corpus baseline report (`test/corpus_baseline_extraction_test.dart`), performance benchmarking (12.07 ms/page, +31.14 MB RSS in `test/phase_2_7_extraction_performance_test.dart`), and real-book verification on 394-page *Laut Bercerita* (`test/real_book_extraction_test.dart`).

---

## [1.0.0] - Version 1.0.0 Release (Phase 2.6)

### Added
- **Full Library Bundle Export**: Added capability to export a self-contained `.bundle` containing library metadata (`manifest.json`) alongside physical copies of all active PDF files (`originals/`).
- **Dual Export UI**: Differentiated "Export Library Metadata (.json)" and "Export Full Library Bundle (with original PDFs)" directly within the Backup & Restore modal dialog.
- **Timestamp-Protected Restore Concurrency**: Added `lastReadAt` monotonic comparison in `mergeUpdateExisting` restore mode. If local reading progress is newer than the backup record, local progress is preserved while non-destructively merging all annotations.
- **Durability Auto-Save Timer**: Integrated a periodic 10-second background flush timer in `ReadingScreen` that commits reading progress to Drift/SQLite, complementing `WidgetsBindingObserver` app pause/inactive state triggers.
- **Comprehensive Backup Validation Suite**: 12 automated test scenarios verifying empty database restores, skip existing, merge existing, newer local progress, newer backup progress, missing source PDFs, corrupt JSON files, unsupported schema version protection, and atomic transaction rollbacks (`test/phase_2_6_release_test.dart`).
- **Holistic Performance Profiling**: Benchmarking suite testing cold document deserialization (10.02 ms), `TextPainter` pagination engine (0.30 ms/page), full-text search (4.35 ms), and multi-book sequential switching (2.2 ms/book, +39.80 MB RSS delta).
- **Release Documentation Suite**: `README.md`, `CHANGELOG.md`, `INSTALLATION.md`, `BACKUP_AND_RESTORE.md`, and `KNOWN_ISSUES.md`.

### Changed
- Bumped application version to `1.0.0+1` across `pubspec.yaml`, `backup_restore_service.dart`, and `library_screen.dart`.
- Refined `BackupRestoreService` validation logic to reject non-JSON payloads or unsupported schema versions prior to initiating SQLite transactions.

---

## [0.2.6] - Stability, Backup/Restore & Safe Relinking (Phase 2.5)

### Added
- **Backup & Restore Service**: JSON-based library metadata export/import covering books, reading progress, bookmarks, highlights, notes, collections, and reader preferences.
- **PDF Relink Protection**: SHA-256 checksum verification when relinking moved or missing source PDFs, alerting users if file contents have changed.
- **Empty State Polish**: Refined empty library views with macOS iconography, typography hints, and direct action triggers.
- **Reading Comfort Transitions**: Smooth theme switching and layout preference updates across reader views.

---

## [0.2.4] - Hierarchical TOC, Search & Navigation History (Phase 2.4)

### Added
- **Hierarchical Table of Contents**: H1–H3 section tree navigation with collapse/expand, active section highlighting, and chapter progress indicators.
- **In-Book Search Engine**: Full-text scanning on normalized semantic `ReaderDocument` DOM nodes rather than raw rendered widgets.
- **Search Highlight Coexistence**: Visual coexistence of active search result highlights with permanent user annotations.
- **Bidirectional Navigation History**: Scoped per-book back stack with return breadcrumbs and keyboard shortcuts (Cmd+[ / Cmd+]).

---

## [0.2.3] - Annotations & Reading Interactions (Phase 2.3)

### Added
- **Text Selection & Highlighting**: 5 Apple Books-inspired color palettes (Yellow, Green, Blue, Pink, Purple).
- **Sticky Note Sheets**: Modal note composer linked directly to highlighted text anchors.
- **Bookmark Hub**: Duplicate-prevented bookmarking with quick-jump navigation.
- **5-Tier Fuzzy Anchor Resolution**: Fallback resolution strategy resilient against typography changes and dynamic reflows (`exactText` -> `surroundingContext` -> `paragraphIndex` -> `chapterIndex` -> `bookStart`).
- **Centralized Annotations View**: Dedicated library tab aggregating all highlights, notes, and bookmarks with filter and search capabilities.

---

## [0.2.2] - Paginated & Scrolling Reader UI (Phase 2.2)

### Added
- **Paginated Reader**: Full-featured paginated reading view with keyboard shortcuts (Arrow Left/Right, Space, Page Up/Down) and smooth page transitions.
- **Responsive Spread Layout**: Single-page view for compact windows, automatic dual-page spread for displays wider than 900pt.
- **Continuous Vertical Scrolling**: Alternative reading mode with seamless anchor-based position sync when toggling between modes.
- **Adaptive Reading Themes**: Light, Sepia, Night, and OLED Charcoal colorways.

---

## [0.2.1] - Reflowable Reading Engine Foundation (Phase 2.1)

### Added
- **`TextPainter` Pagination Engine**: Deterministic paragraph-level and word-level text layout computation.
- **Semantic DOM Model**: Structured `ReaderDocument`, `ReaderChapter`, and `ReaderParagraph` hierarchy.
- **Reading Progress Anchor Model**: Sub-millisecond anchor synchronization across viewport resizes.

---

## [0.1.5] - File Lifecycle & Duplicate Detection (Phase 1.5)

### Added
- **Safe File Deletion**: Complete cleanup of extracted text, cached covers, and database entries with active file lock safeguards.
- **Duplicate Detection**: SHA-256 byte-level hash verification preventing duplicate imports while distinguishing distinct editions of the same title.
- **Database Schema v2**: Drift migration introducing strict foreign keys and cascade delete rules.

---

## [0.1.0] - Foundation & Library Management (Phase 1.0)

### Added
- **Library Grid & List Views**: macOS-styled library interface with sorting (Title, Author, Date Added, Progress) and live search filtering.
- **Sidebar Navigation**: Navigation rails for All Books, Collections, Bookmarks, and Annotations.
- **Metadata Editing**: In-app editing for title, author, and description metadata.
- **Many-to-Many Collections**: Flexible tag and folder organization for user libraries.
- **PDFium Integration**: Native PDF rendering and automated high-DPI cover thumbnail extraction.

