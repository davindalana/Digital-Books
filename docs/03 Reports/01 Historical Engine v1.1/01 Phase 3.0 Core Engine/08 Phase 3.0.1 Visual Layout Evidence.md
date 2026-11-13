# Phase 3.0.1 Visual Layout Evidence

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus I — Core Engine & Document Pipeline (v1.0 s.d. v1.1)
> - **Modul / Kategori**: Phase 3.0.1 Visual Layout & Transition Evidence
> - **Urutan Dokumen**: 08 Phase 3.0.1 Visual Layout Evidence
> - **Tanggal**: 1 November 2026
> - **Status Verifikasi**: **PASS**

---

## Context & Objectives
During native testing on macOS with scanned real-world books (*Laut Bercerita*, *Bicara Itu Ada Seninya*, and *The Devotion of Suspect X*), four key visual reading defects were identified:
1. Low contrast, yellowed/grayish paper background reducing legibility.
2. Faded ink and soft character stroke edges on scanned pages.
3. Pronounced dark gutter crease shadows along the book spine margin.
4. Perceived "heavy" rendering and blinking/white-flashing during fast page flips or scroll mode switches.

Phase 3.0.1 implements an in-memory, non-destructive image enhancement pipeline integrated into `OriginalPdfReader` to remediate these issues without altering original PDF binaries.

---

## Visual Verification Matrix

| Document | Page Tested | Artifact / Defect Addressed | Visual Result Before | Visual Result After (Phase 3.0.1) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Bicara Itu Ada Seninya** | Page 1 (Cover / Intro) | Yellowed scan background, faded text | Grayish tint, soft low-contrast characters | Clean whitened background (LUT 255), crisp high-contrast deep black text | **PASS** |
| **Bicara Itu Ada Seninya** | Page 2–3 (Two-Page Spread) | Inner spine gutter crease shadow | Dark gray gradient band along binding edge | Gutter shadow leveled by directional edge-gradient boost (+38 gray levels) | **PASS** |
| **Laut Bercerita** | Page 12–13 | Faded print stroke definition | Faint serifs and broken character stems | Character edges enhanced via 3x3 unsharp convolution kernel | **PASS** |
| **Suspect X / Corpus 05** | Pages 1–5 | White flash on page flips & mode switches | Transient blank white canvas during texture re-render | Double-buffered bitmap retention displays previous frame until new bitmap is ready (0 blank frames) | **PASS** |

---

## Appearance Sheet Controls & Interaction

The `AppearanceSheet` provides granular user control over the enhancement engine:

1. **Tingkatkan Kualitas Pindaian (Master Switch):**
   - Enables or disables the real-time enhancement filter on-the-fly.
   - Preserves old texture while new texture renders in the background (zero white flash).
2. **Tingkat Peningkatan (Intensity Selector):**
   - **Lembut:** Contrast 1.25x, Brightness +12, Unsharp 0.35. Suitable for well-preserved scans.
   - **Seimbang:** Contrast 1.45x, Brightness +22, Unsharp 0.55. Optimal default for standard yellowed paperbacks.
   - **Kuat:** Contrast 1.70x, Brightness +32, Unsharp 0.75. Ideal for dark, faded, or heavily aged paper.
3. **Reduksi Bayangan Lipatan (Gutter):**
   - Direction-aware algorithm: boosts inner 16% margin on right side for even (left) pages and on left side for odd (right) pages.
4. **Mode Hitam Putih (Grayscale):**
   - Applies ITU-R BT.601 integer luminance calculation to convert colored paper stains and chromatic aberration into clean monochrome.

---

## Layout Mode Toolbar Clarification

During visual testing, an observation was recorded regarding toolbar buttons in vertical scroll mode:
- **Observation:** In *Gulir Vertikal* (continuous scroll mode), the 1-halaman / 2-halaman spread button is hidden from the top toolbar.
- **Root Cause & Rationale:** In continuous scrolling, pages flow sequentially in a single vertical column. Two-page spreads require two facing pages side-by-side in a fixed viewport, which is structurally incompatible with continuous single-axis vertical scrolling. Hiding the spread button prevents invalid layout configurations and user confusion.

