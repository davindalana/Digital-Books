# Known Issues & Technical Disclosures • Digital Books v1.0.0

This document outlines known limitations, architectural boundaries, and intended behaviors in Version 1.0.0.

---

## 1. App Sandbox & Direct File Access Permissions

### Context
In macOS App Sandbox (configured in `macos/Runner/Release.entitlements`), direct access to user files outside the app container is sandboxed.
- When a user imports a PDF file from an arbitrary directory (such as `~/Downloads` or external USB drives), macOS generates security-scoped bookmarks or provides temporary access while the app is active.
- If the application is packaged with strict sandboxing enabled, original PDFs located outside the sandbox directory (`~/Library/Containers/com.davindalana.digitalBooks`) may become inaccessible if user permissions are revoked or file paths change.

### Mitigation in v1.0.0
- Digital Books extracts and caches extracted text structure and high-resolution cover thumbnails directly inside its internal application support directory (`~/Library/Application Support/com.davindalana.digitalBooks/`).
- Users can use the **Full Library Bundle Export** feature, which bundles all PDF originals alongside the metadata manifest, ensuring 100% portability regardless of sandboxing.

---

## 2. Reflowable Annotations vs Native PDF Mode

### Context
- Annotations (Highlights, Bookmarks, Sticky Notes) created in the **Reflowable Reading Engine** utilize semantic fuzzy anchor resolution (`chapterId`, `paragraphIndex`, `exactText`, `prefixContext`, `suffixContext`).
- In **Native PDF Mode**, text is rendered directly from PDFium raster/vector streams.

### Scope in v1.0.0
- Text highlighting and in-place note attachment are optimized for the **Reflowable Engine**.
- When viewing a book in Native PDF mode, users can bookmark pages and view reading progress; fine-grained vector text highlights directly baked into PDF binary streams are scheduled for a future release.

---

## 3. Large PDF Ingestion Memory Spike

### Context
When importing scanned or image-dense PDF files exceeding 500 pages:
- High-DPI cover rendering and full-text extraction via PDFium temporarily utilizes system memory during the initial background ingestion worker.

### Mitigation in v1.0.0
- Ingestion occurs asynchronously on an isolated worker thread without blocking the Flutter UI.
- Once ingestion completes, PDFium page pointers are immediately released, returning system memory back to normal idle baseline levels (< 80 MB RSS).

---

## 4. Complex Mathematical LaTeX & Multi-Column Layouts

### Context
- The Reflowable reading engine is optimized for narrative prose, non-fiction, academic articles, and standard book layouts.
- Highly complex multi-column scientific layouts or deeply nested mathematical formulas embedded as raw PDF vector paths may be normalized into linear paragraphs during text extraction.

### Recommendation
- Users reading complex multi-column scientific journals or mathematical textbooks can toggle **Native PDF Mode** from the reader toolbar to view the original unaltered publication layout.

