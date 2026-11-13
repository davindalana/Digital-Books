# Phase 5 Reading Progress Calculator

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus II — Modernization & Apple Books Polish (v1.2+)
> - **Fase**: Phase 5 (Unified Reading Progress Calculator & Mode-Aware Formatting)
> - **Tanggal**: 12 November 2026
> - **Target Komponen**: `ReadingProgressCalculator`, `LibraryScreen`, `ReadingScreen`, `BookDetailsDialog`
> - **Status Verifikasi**: **PASS**

---

## 1. Latar Belakang & Masalah

Sebelum Phase 5, representasi progres membaca (*reading progress*) memiliki inkonsistensi matematis dan semantik:
1. **Pencampuran Metrik Halaman vs Persentase**: Pada mode *Reflowable* (Book Mode), jumlah halaman bergantung pada ukuran font, line-spacing, dan ukuran jendela. Menampilkan label *"Halaman 40 dari 120"* pada mode reflowable membingungkan pembaca saat mereka mengubah ukuran font dan total halaman berubah drastis.
2. **Kalkulasi Fraksi PDF**: Pembagian halaman PDF mentah dapat menghasilkan pembagian nol (*divide-by-zero*) atau nilai persentase di luar rentang $[0.0, 1.0]$.
3. **Format Label Tersebar**: Kode pemformatan teks progres (`${(pct * 100).toInt()}%`) terduplikasi di `library_screen.dart`, `book_details_dialog.dart`, `book_list_tile.dart`, dan `reading_screen.dart`.

---

## 2. Arsitektur & Solusi Implementasi

### 2.1 Kalkulator Terpusat (`ReadingProgressCalculator`)
Dibuat kelas utilitas [`lib/core/utils/reading_progress_calculator.dart`](file:///Users/davindalana/Documents/Project/Digital%20Books/lib/core/utils/reading_progress_calculator.dart) dengan logika mode-aware:

1. **Original PDF Mode**:
   - Berbasis nomor halaman fisik PDFium: `calculatePdfFraction(lastVisiblePage, totalPages)`.
   - Format: *"Hal. X dari Y"* atau bentang *"Hal. X–Z dari Y"*.
2. **Reflowable / Book Mode**:
   - Berbasis persentase teks dan nama bab semantik:
     Format: *"X% • Bab Y"* atau *"X% Selesai • [Judul Bab]"*.
   - Tidak memaksakan nomor halaman statis pada teks yang fleksibel mengalir.
3. **Status Kategori Progres**:
   - $0.0\% \to$ *Belum dibaca* (`AppStrings.statusBelumDibaca`)
   - $\ge 99.5\% \to$ *Selesai* (`AppStrings.statusSelesai`)
   - $0.1\% - 99.4\% \to$ *X% Selesai*

### 2.2 Estimasi Waktu Tersisa Bab
- Perhitungan kata per menit (WPM 200–250) untuk memperkirakan waktu baca tersisa dalam bab aktif: `±N mnt tersisa`.
- Dilengkapi `Tooltip` informatif untuk menjelaskan dasar estimasi waktu kepada pengguna.

---

## 3. Hasil Pengujian Otomatis

Rangkaian unit test komprehensif di [`test/reading_progress_calculator_test.dart`](file:///Users/davindalana/Documents/Project/Digital%20Books/test/reading_progress_calculator_test.dart) mencakup:
- Boundary conditions: $0$ halaman, total halaman negatif, posisi melebihi total.
- Pembulatan persentase matematis dan batas ambang *Selesai*.
- Formatting label mode original PDF vs reflowable book mode.
- Estimasi waktu membaca per bab.

**Hasil Uji**:
- `flutter test test/reading_progress_calculator_test.dart`: **PASS** (100%).
- `flutter analyze`: **0 Issues**.
