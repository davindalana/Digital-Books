# Phase 1 Design Tokens and UX Strings

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus II — Modernization & Apple Books Polish (v1.2+)
> - **Fase**: Phase 1 (Centralized Design Tokens & Indonesian UX Strings)
> - **Tanggal**: 12 November 2026
> - **Target Platform**: macOS (Native Flutter)
> - **Status Verifikasi**: **PASS**

---

## 1. Latar Belakang & Masalah

Sebelum inisiatif modernisasi Siklus II, aplikasi Digital Books memiliki beberapa kelemahan konsistensi UI/UX:
1. **Magic Numbers**: Nilai margin, padding, border radius, dan batas breakpoint tersebar di berbagai widget secara acak (`padding: EdgeInsets.all(12)`, `EdgeInsets.all(16)`, `BorderRadius.circular(8)`).
2. **Inkonsistensi Bahasa**: Percampuran istilah bahasa Inggris dan bahasa Indonesia di layar perpustakaan dan dialog (misal: "Currently Reading" vs "Sedang Dibaca", "All Books" vs "Semua Buku").
3. **Ketiadaan Skala Breakpoint Terpusat**: Belum ada konstanta resmi untuk membagi form-factor jendela macOS menjadi ukuran Compact, Standard, dan Expansive.

---

## 2. Arsitektur & Solusi Implementasi

### 2.1 Centralized Design Tokens (`AppThemeTokens`)
Dibuat berkas [`lib/core/theme/app_theme_tokens.dart`](../../../lib/core/theme/app_theme_tokens.dart) yang menyediakan standar token desain terpusat:
- **Spacing Scale**:
  - `spaceXXS = 2.0`, `spaceXS = 4.0`, `spaceS = 8.0`, `spaceM = 12.0`, `spaceL = 16.0`, `spaceXL = 24.0`, `spaceXXL = 32.0`
- **Border Radius Scale**:
  - `radiusXS = 4.0`, `radiusS = 8.0`, `radiusM = 12.0`, `radiusL = 16.0`, `radiusFull = 999.0`
- **Window Breakpoint Scale**:
  - `breakpointCompact = 700.0` (Ambience single-column / minimal rail)
  - `breakpointStandard = 900.0` (Icon rail + multi-column grid)
  - `breakpointExpansive = 1280.0` (Full expanded native sidebar + dense grid)
- **Component Geometry**:
  - `sidebarWidth = 220.0`
  - `iconRailWidth = 64.0`

### 2.2 Centralized UX Strings Dictionary (`AppStrings`)
Dibuat berkas [`lib/core/constants/app_strings.dart`](../../../lib/core/constants/app_strings.dart) yang menstandarisasi seluruh istilah antarmuka bernuansa Apple Books:
- Navigasi: *Currently Reading*, *All Books*, *Collections*, *Bookmarks*, *Highlights & Notes*, *Settings*.
- Aksi Utama: *Add Book*, *Continue Reading*, *Start Reading*, *View All*, *Import PDF…*.
- Badge & Metadata: *Scanned*, *Digital Text*, *Unknown Author*, *Untitled*.
- Status Progres: *Unread*, *Just Started*, *Finished*.
- Mode Baca: *Book* (Reflowable), *PDF* (Original Document).

---

## 3. Verifikasi Pengujian

Rangkaian pengujian unit di [`test/app_theme_tokens_and_strings_test.dart`](../../../test/app_theme_tokens_and_strings_test.dart) menguji:
1. Urutan monotonic token spasi dan radius (`spaceXXS < spaceXS < ...`).
2. Validitas hierarki breakpoint jendela macOS (`compact < standard < expansive`).
3. Kelengkapan dan konsistensi terminologi `AppStrings`.

**Hasil Uji**:
- `flutter test test/app_theme_tokens_and_strings_test.dart`: **3/3 PASS** (100%).
- `flutter analyze`: **0 Issues**.
