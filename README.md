# Digital Books for macOS • Version 1.1.0-alpha.8+9

A local-first digital library and reading application for macOS, built with Flutter, Drift (SQLite), and PDFium. This repository is currently preparing a macOS beta; Android and iOS are not release targets for this beta.

---

## Key Highlights

- **Dual-Engine Reading System**:
  - **Reflowable Engine**: Precise `TextPainter` word-level pagination with single-page and dual-page responsive spreads, continuous vertical scrolling, and sub-millisecond anchor synchronization.
  - **Native PDF Engine**: High-fidelity PDF rendering powered by PDFium, crisp vector text, zoom controls, and smooth pan navigation.
- **Apple Books Aesthetic & Comfort**:
  - Four curated reading palettes: **Light, Sepia, Night, and OLED Charcoal**.
  - Font choices tailored for macOS typography: Literata, Merriweather, Georgia, Inter, and SF Pro.
  - Granular control over font scale (12pt–32pt), line spacing (1.2–2.2), and reading spread mode.
- **Reading Interactions & Annotations**:
  - Contextual text selection with 5 highlight colors (Yellow, Green, Blue, Pink, Purple).
  - Note attachments linked directly to text spans.
  - Bookmarks with duplicate prevention and fast jump navigation.
  - 5-tier fuzzy anchor resolution (`exactText`, `surroundingContext`, `paragraphIndex`, `chapterIndex`, `bookStart`) that gracefully withstands document reflows.
- **Discovery & Navigation**:
  - Multi-level hierarchical Table of Contents (H1–H3) with collapse/expand and live section tracking.
  - In-book search scanning the normalized semantic document structure (not raw widgets), with instant highlight traversal.
  - Scoped bidirectional navigation history (Cmd+[ / Cmd+]) with return breadcrumbs.
- **Enterprise-Grade Data Resilience**:
  - Local Drift (SQLite) database with strict foreign keys and cascading deletes.
  - Atomic, transactional Backup & Restore (`.json` metadata bundle and self-contained `.bundle` with physical PDFs).
  - Non-destructive restore conflict resolution with monotonic timestamp protection (`lastReadAt`).
  - SHA-256 book checksum validation and automated PDF relink recovery.
  - 10-second background auto-save timer and `AppLifecycleState` flush protection.

---

## Architectural Overview

```
Digital Books Architecture
┌────────────────────────────────────────────────────────┐
│               macOS Presentation Layer                 │
│  LibraryScreen · ReadingScreen · AnnotationsHub · TOC  │
└───────────────────────────┬────────────────────────────┘
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
┌────────────────────────┐      ┌────────────────────────┐
│ Reflowable Engine      │      │ Native PDF Engine      │
│ · TextPainter Paginator│      │ · PDFium Native Lib    │
│ · Single/Two Spread    │      │ · High-DPI Cover Gen   │
│ · Vertical Continuous  │      │ · Original Page Canvas │
└───────────┬────────────┘      └───────────┬────────────┘
            │                               │
            └───────────────┬───────────────┘
                            ▼
┌────────────────────────────────────────────────────────┐
│                 Reading State & Anchors                │
│  Anchor Synchronization · Highlight/Note Span Mapping  │
└───────────────────────────┬────────────────────────────┘
                            ▼
┌────────────────────────────────────────────────────────┐
│           Persistence & Durability (Drift/SQLite)      │
│  Schema v6 · Cascade Delete · Atomic Backup & Restore  │
└────────────────────────────────────────────────────────┘
```

---

## Performance Benchmarks

Measured on macOS (ARM64 / Apple Silicon):

| Benchmark Scenario | Dataset / Workload | Latency / Metric | Performance Target | Result |
| :--- | :--- | :--- | :--- | :--- |
| **Cold Document Deserialization** | 130,000 words, 50 chapters (0.94 MB JSON) | **10.02 ms** | < 100 ms | **PASSED** |
| **Reflowable Pagination Engine** | 1,224 computed pages (650x850 pt) | **363 ms** (0.30 ms/page) | < 16.6 ms/page (60 FPS) | **PASSED** |
| **Full-Text In-Book Search** | 250 matches across 130,000 words | **4.35 ms** | < 50 ms | **PASSED** |
| **Multi-Book Sequential Switching** | 10 full document loads + paginations + searches | **22 ms** (2.2 ms/book) | < 200 ms/book | **PASSED** |
| **Memory RSS Delta (10 Switches)** | Sequential disposal & layout cache clearing | **+39.80 MB** | < 100 MB | **PASSED** |

---

## Getting Started

### Prerequisites
- macOS 12.0 (Monterey) or higher
- Flutter SDK 3.41.6 / Dart 3.11.4 (the currently verified toolchain)
- Xcode 15+ & CocoaPods

### Running the App Locally
```bash
# Clone the repository
git clone https://github.com/davindalana/digital-books.git
cd "Digital Books"

# Fetch dependencies
flutter pub get

# Run on macOS
flutter run -d macos
```

### Running the Verification Suites
```bash
# Static analysis (0 issues required)
flutter analyze

# Full unit, widget, and stability test suite
flutter test --reporter expanded

# Native macOS integration tests are listed under integration_test/.
# Run the selected scenario on a macOS desktop target.
flutter test integration_test/macos_phase_2_8_4_native_visual_acceptance_test.dart -d macos
```

The native interaction and visual acceptance checklist still requires a human run on macOS. Passing Flutter tests alone does not complete beta acceptance.

---

## Documentation Suite

- [Documentation Hub & Catalog](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/README.md)
- [Installation & Release Notes](file:///Users/davindalana/Documents/Project/Digital%20Books/INSTALLATION.md)
- [Backup & Disaster Recovery Guide](file:///Users/davindalana/Documents/Project/Digital%20Books/BACKUP_AND_RESTORE.md)
- [Release Changelog](file:///Users/davindalana/Documents/Project/Digital%20Books/CHANGELOG.md)
- [Known Issues & Technical Disclosures](file:///Users/davindalana/Documents/Project/Digital%20Books/KNOWN_ISSUES.md)
