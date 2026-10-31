# Changelog

All notable changes to the **Digital Books** application are documented in this file.

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

