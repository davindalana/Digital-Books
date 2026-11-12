# Phase 2 — macOS Native Responsive Shell, Icon Rail & Sidebar Navigation

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus II — Modernization & Apple Books Polish (v1.2+)
> - **Fase**: Phase 2 (Responsive macOS Shell, Icon Rail & Native Sidebar)
> - **Tanggal**: 12 November 2026
> - **Target Platform**: macOS (Native Flutter & AppKit Window API)
> - **Status Verifikasi**: **PASS**

---

## 1. Latar Belakang & Masalah

Sebelum Phase 2, layar perpustakaan (`LibraryScreen`) memiliki batasan ergonomi pada macOS desktop:
1. **Tata Letak Kaku**: Tampilan tidak beradaptasi mulus saat jendela diubah ukurannya (*window resizing*). Pada ukuran kecil, elemen mengalami overflow, sementara pada monitor ultrawide/expansive, ruang kosong tidak termanfaatkan.
2. **Ketiadaan Pola Navigasi Desktop**: Tidak ada Sidebar native seperti Apple Books macOS yang dapat dilipat (*collapsible*) menjadi Icon Rail ramping atau disembunyikan pada jendela kompak.
3. **Akses Cepat Rak "Sedang Dibaca"**: Rak buku aktif memerlukan alur navigasi khusus agar pembaca dapat langsung melanjutkan buku terakhir tanpa harus mencari di seluruh daftar buku.

---

## 2. Arsitektur & Solusi Implementasi

### 2.1 Tiga Mode Tata Letak Adaptif (Responsive Breakpoints)
Sesuai token [`AppThemeTokens`](file:///Users/davindalana/Documents/Project/Digital%20Books/lib/core/theme/app_theme_tokens.dart), `LibraryScreen` dipecah menjadi 3 mode visual adaptif:

| Breakpoint | Lebar Jendela | Mode Navigasi | Lebar Nav | Karakteristik Grid |
| :--- | :--- | :--- | :--- | :--- |
| **Compact** | $< 700\text{ dp}$ | Header Selector | $0\text{ dp}$ (Tanpa Sidebar) | Kolom tunggal / 2 kolom compact |
| **Standard** | $700\text{ dp} - 1280\text{ dp}$ | Icon Rail | $64\text{ dp}$ | 3–4 kolom buku dengan label ringkas |
| **Expansive** | $\ge 1280\text{ dp}$ | Full Native Sidebar | $220\text{ dp}$ | 5–6 kolom buku dengan hero cover |

### 2.2 Sinkronisasi Filter & Header Aksi Rak
- Implementasi filter dua arah antara Sidebar, Icon Rail, dan tombol aksi cepat *"Lihat Semua"* pada header rak `Sedang Dibaca`.
- Ketika tombol *"Lihat Semua"* ditekan, seleksi sidebar otomatis beralih ke navigasi `Sedang Dibaca` (`NavigationSection.currentlyReading`).

---

## 3. Bukti Visual Pengujian Native macOS

Bukti visual tangkapan layar asli macOS Retina dihasilkan oleh:
- Flutter Widget Driver: [`test/library_shell_visual_capture_test.dart`](file:///Users/davindalana/Documents/Project/Digital%20Books/test/library_shell_visual_capture_test.dart) $\to$ [`docs/visual_evidence/phase_2_shell/`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/visual_evidence/phase_2_shell)
- Native Swift Screencapture Tool: [`tools/capture_native_windows.swift`](file:///Users/davindalana/Documents/Project/Digital%20Books/tools/capture_native_windows.swift) $\to$ [`docs/visual_evidence/phase_2_native/`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/visual_evidence/phase_2_native)

Daftar artefak visual terverifikasi:
1. `01_compact_700_sedang_dibaca.png`: Tampilan compact $700\text{ dp}$ pada rak Sedang Dibaca.
2. `02_compact_700_semua_buku.png`: Tampilan compact $700\text{ dp}$ pada daftar Semua Buku.
3. `03_standard_900_sedang_dibaca.png`: Tampilan standard $900\text{ dp}$ dengan Icon Rail $64\text{ dp}$.
4. `04_standard_900_semua_buku.png`: Tampilan standard $900\text{ dp}$ Semua Buku dengan Icon Rail.
5. `05_expansive_1280_sedang_dibaca.png`: Tampilan expansive $1280\text{ dp}$ dengan Sidebar penuh $220\text{ dp}$.
6. `06_expansive_1280_semua_buku.png`: Tampilan expansive $1280\text{ dp}$ Semua Buku dengan Sidebar penuh.

---

## 4. Hasil Pengujian Otomatis

- `test/library_shell_and_sidebar_responsive_test.dart`: **PASS** (10 skenario responsive).
- `test/library_shell_visual_capture_test.dart`: **PASS** (6 artefak gambar dirender).
- `flutter analyze`: **0 Issues**.
