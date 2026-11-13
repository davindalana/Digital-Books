# Digital Books — Documentation Hub & Architecture Catalog

Selamat datang di direktori dokumentasi resmi **Digital Books**. Dokumen ini berfungsi sebagai peta navigasi utama, indeks arsitektur, dan katalog kronologis seluruh dokumen teknis, standar tata kelola (*governance*), spesifikasi sistem, serta laporan pengujian (*audit & benchmark reports*) proyek Digital Books.

---

## 1. Peta Jalan & Linimasa Dua Siklus (The Two-Cycle Evolution Roadmap)

Untuk memahami alur dan penomoran fase di Digital Books (mengapa terdapat **Phase 1, 2, dan 5 yang baru dikerjakan pada Siklus II**, sementara **Phase 3.0 s.d. 3.9A merupakan fase historis pada Siklus I**), perhatikan linimasa dua siklus rekayasa berikut:

```mermaid
flowchart TD
    subgraph S1["Siklus I: Core Engine & Document Pipeline (v1.0 - v1.1.0-alpha.8)"]
        direction TB
        P1_OLD["Phase 1 (v0.2)<br/>Fondasi SQLite & Migration"] --> P2_OLD["Phase 2.1 - 2.9<br/>PDFium C-FFI, Caching & Anti-Flash"]
        P2_OLD --> P3_OLD["Phase 3.0 - 3.5<br/>Apple Vision OCR, Dehyphenation & Search"]
        P3_OLD --> P3_BM["Book Mode Redesign<br/>Horizontal Pagination & Real Book Typography"]
        P3_BM --> P3_REL["Phase 3.6 - 3.9A<br/>Release Candidates, UI Audits & Glass Scrubber"]
    end

    subgraph S2["Siklus II: Modernization & Apple Books Polish (v1.2+) — November 2026"]
        direction TB
        P1_NEW["01 Phase 1 (Modern)<br/>Design Tokens & UX Strings Dictionary"] --> P2_NEW["02 Phase 2 (Modern)<br/>Responsive macOS Shell, Rail & Sidebar"]
        P2_NEW --> P3_NEW["Phase 3 - 4 (Modern)<br/>Metadata Dialog & Native Window Transitions"]
        P3_NEW --> P5_NEW["03 Phase 5 (Modern)<br/>Unified Reading Progress Calculator"]
    end

    S1 -.->|"Fondasi Engine Selesai & Stabil"| S2
```

### Penjelasan Dua Siklus Pengembangan:
1. **Siklus I — Core Engine & Document Pipeline (Fase Historis / v1.0 s.d. v1.1.0-alpha.8)**:
   - Dikerjakan selama fase perintisan arsitektur inti (Oktober – awal November 2026).
   - Fokus: Stabilitas rendering PDFium native, eliminasi *blank flash*, integrasi Apple Vision OCR lokal tanpa cloud, normalisasi paragraf, rekonsiliasi kata, pencarian semantik berkecepatan tinggi, paginasi horizontal Book Mode, dan rangkaian Release Candidate 3.6 s.d. 3.9A.
   - Lokasi berkas: [`docs/03 Reports/01 Historical Engine v1.1/`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1).
2. **Siklus II — Modernization & Apple Books Polish Initiative (Fase Terkini / v1.2+)**:
   - Berjalan aktif mulai **12 November 2026**.
   - Fokus: Peningkatan pengalaman desktop macOS asli (standar Apple Books), perancangan token desain (`AppThemeTokens`), tata letak adaptif 3 breakpoint (`compact < 700dp`, `standard 900dp`, `expansive >= 1280dp`), icon rail, sidebar native, kamus terminologi antarmuka terpusat (`AppStrings`), dan kalkulator progres membaca yang mode-aware (`ReadingProgressCalculator`).
   - Lokasi berkas: [`docs/03 Reports/02 Modernization v1.2/`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/02%20Modernization%20v1.2).

---

## 2. Struktur Direktori Dokumentasi Berurutan (Sequential Structure)

Seluruh nama folder dan berkas menggunakan **Title Case dengan spasi** dan diberi awalan nomor urut dua digit (`01`, `02`, `03`...) agar secara otomatis terurut secara kronologis dan logis di seluruh *file browser*:

```text
docs/
├── README.md                                  # Katalog Utama & Peta Navigasi Sistem
├── 01 Governance/                             # Standar Tata Kelola & Rekayasa Perangkat Lunak
│   ├── 01 Development Workflow.md             # Siklus 13 Langkah Baku & Commit Policy
│   └── 02 Versioning Policy.md                # Spesifikasi SemVer 2.0.0 & Release Gates
├── 02 Architecture/                           # Cetak Biru Sistem & Roadmap Desain Inti
│   ├── 01 Phase 3.0 Architecture.md           # Arsitektur Dual-Engine & Cache Bitmap
│   ├── 02 Phase 3.1 Architecture Plan.md      # Desain Pipeline OCR & Rekonstruksi Teks
│   ├── 03 Complete Reading Experience Overhaul.md # Blueprint Redesain Tipografi & Layout
│   └── 04 Book Mode Finalization Roadmap.md   # Peta Jalan Penyelesaian Book Mode
├── 03 Reports/                                # Seluruh Laporan Validasi, Audit & Benchmark
│   ├── 01 Historical Engine v1.1/             # [SIKLUS I — HISTORIS] Pipeline Mesin Inti
│   │   ├── 01 Phase 3.0 Core Engine/          # 13 Laporan Phase 3.0, 3.0.1, 3.0.1.1
│   │   ├── 02 Phase 3.1 Apple Vision OCR/     # 3 Laporan Apple Vision OCR
│   │   ├── 03 Phase 3.2 In-Book Search/       # 2 Laporan In-Book Search & Traversal
│   │   ├── 04 Phase 3.3 Annotations/          # 1 Laporan Anotasi, Sorotan & Catatan
│   │   ├── 05 Phase 3.5 Real Corpus Validation/ # 4 Laporan Validasi Korpus Riil & Audit
│   │   ├── 06 Book Mode/                      # 5 Laporan Redesain Paginasi & Layout Buku
│   │   └── 07 Release Candidates 3.6 to 3.9A/ # 8 Laporan Release Candidate & UI Audits
│   └── 02 Modernization v1.2/                 # [SIKLUS II — TERKINI] Modernisasi UI/UX macOS
│       ├── 01 Phase 1 Design Tokens and Strings.md
│       ├── 02 Phase 2 macOS Responsive Shell.md
│       └── 03 Phase 5 Reading Progress Calculator.md
└── visual_evidence/                           # Artefak Visual Tangkapan Layar Native macOS
```

---

## 3. Standar Tata Kelola Rekayasa (`01 Governance/`)

| Nomor | Dokumen | Deskripsi & Isi Utama | Tautan |
| :---: | :--- | :--- | :--- |
| **01** | **Development Workflow** | 13 langkah siklus pengembangan baku, Conventional Commits, aturan `CHANGELOG.md`, prosedur regression test, mitigasi rollback, dan proteksi integritas data. | [`01 Development Workflow.md`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/01%20Governance/01%20Development%20Workflow.md) |
| **02** | **Versioning Policy** | Skema SemVer 2.0.0 (`MAJOR.MINOR.PATCH-PRERELEASE+BUILD`), tahapan siklus rilis (Alpha, Beta, RC, Stable), dan aturan kenaikan nomor rilis. | [`02 Versioning Policy.md`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/01%20Governance/02%20Versioning%20Policy.md) |

---

## 4. Cetak Biru Arsitektur Sistem (`02 Architecture/`)

| Nomor | Dokumen | Deskripsi & Cakupan | Tautan |
| :---: | :--- | :--- | :--- |
| **01** | **Phase 3.0 Architecture** | Spesifikasi Dual-Engine Reading System (Original PDFium C-FFI vs Reflowable TextPainter), layer caching bitmap dua tingkat, dan state management Riverpod. | [`01 Phase 3.0 Architecture.md`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/02%20Architecture/01%20Phase%203.0%20Architecture.md) |
| **02** | **Phase 3.1 Architecture Plan** | Arsitektur pipeline pemrosesan dokumen lokal: Image Enhancement LUT, Apple Vision OCR, dehyphenation bahasa Indonesia, dan Semantic Reconstruction. | [`02 Phase 3.1 Architecture Plan.md`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/02%20Architecture/02%20Phase%203.1%20Architecture%20Plan.md) |
| **03** | **Complete Reading Experience Overhaul** | Cetak biru perombakan total pengalaman membaca: estetika tipografi Apple Books, mode bentang halaman (single/two-page spread), dan fluid navigation. | [`03 Complete Reading Experience Overhaul.md`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/02%20Architecture/03%20Complete%20Reading%20Experience%20Overhaul.md) |
| **04** | **Book Mode Finalization Roadmap** | Peta jalan penyelesaian Book Mode: paginasi horizontal presisi kata, pembatasan orphan/widow, kalkulasi waktu tersisa bab, dan rendering spread adaptif. | [`04 Book Mode Finalization Roadmap.md`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/02%20Architecture/04%20Book%20Mode%20Finalization%20Roadmap.md) |

---

## 5. Laporan Siklus I — Core Engine & Pipeline Historis v1.1 (`03 Reports/01 Historical Engine v1.1/`)

### 5.1 Sub-Fase 3.0 & 3.0.1 (`01 Phase 3.0 Core Engine/`)

| No | Dokumen | Kategori | Ringkasan Isi | Tautan |
| :---: | :--- | :--- | :--- | :--- |
| **01** | `01 Phase 3.0 Benchmark.md` | Benchmark | Pengukuran baseline performa render PDFium, alokasi memori, dan efisiensi paginasi awal. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/01%20Phase%203.0%20Benchmark.md) |
| **02** | `02 Phase 3.0.1 Implementation.md` | Milestone | Implementasi stabilisasi cache bitmap ganda, eliminasi double white flash, dan unblocking gesture. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/02%20Phase%203.0.1%20Implementation.md) |
| **03** | `03 Phase 3.0.1 Benchmark.md` | Benchmark | Tolok ukur latensi perpindahan halaman dan konsumsi RAM pasca perbaikan cache. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/03%20Phase%203.0.1%20Benchmark.md) |
| **04** | `04 Phase 3.0.1 Reader Quality.md` | Quality | Evaluasi kualitas keterbacaan, pemilihan font macOS native, dan kontras warna pada 4 palet membaca. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/04%20Phase%203.0.1%20Reader%20Quality.md) |
| **05** | `05 Phase 3.0.1 Semantic Reconstruction.md` | Engine | Validasi normalisasi paragraf, deteksi heading bab (H1–H3), dan penanganan tanda hubung kata ulang. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/05%20Phase%203.0.1%20Semantic%20Reconstruction.md) |
| **06** | `06 Phase 3.0.1 PDF Transition Validation.md` | Validation | Uji transisi kurva kubik pada perpindahan halaman PDF ganda tanpa frame drop. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/06%20Phase%203.0.1%20PDF%20Transition%20Validation.md) |
| **07** | `07 Phase 3.0.1 Performance.md` | Perf | Profiling CPU dan raster thread selama navigasi cepat 60 FPS pada monitor Retina. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/07%20Phase%203.0.1%20Performance.md) |
| **08** | `08 Phase 3.0.1 Visual Validation.md` | Visual | Bukti tangkapan layar transisi halaman, rendering halaman ganda, dan visual palet tema. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/08%20Phase%203.0.1%20Visual%20Validation.md) |
| **09** | `09 Phase 3.0.1 Final Acceptance.md` | Acceptance | Laporan kelayakan rilis checkpoint Phase 3.0.1 dengan 240/240 automated test passing. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/09%20Phase%203.0.1%20Final%20Acceptance.md) |
| **10** | `10 Phase 3.0.1.1 Enhancement Fix.md` | Fix | Perbaikan algoritma tone-mapping S-curve LUT untuk dokumen pindaian fotokopi kontras rendah. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/10%20Phase%203.0.1.1%20Enhancement%20Fix.md) |
| **11** | `11 Phase 3.0.1.1 Gutter Validation.md` | Validation | Validasi flattening kelengkungan gutter (punggung buku) pada buku pindaian tebal. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/11%20Phase%203.0.1.1%20Gutter%20Validation.md) |
| **12** | `12 Phase 3.0.1.1 Native Transition Validation.md` | Validation | Validasi efek curl 3D native macOS dan retensi permukaan halaman selama animasi buka buku. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/12%20Phase%203.0.1.1%20Native%20Transition%20Validation.md) |
| **13** | `13 Phase 3.0.1.1 Performance.md` | Perf | Pengukuran latensi enhancement LUT (18 ms per halaman 8.1 MB) di bawah anggaran 35 ms. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/01%20Phase%203.0%20Core%20Engine/13%20Phase%203.0.1.1%20Performance.md) |

---

### 5.2 Sub-Fase 3.1 Apple Vision OCR (`02 Phase 3.1 Apple Vision OCR/`)

| No | Dokumen | Kategori | Ringkasan Isi | Tautan |
| :---: | :--- | :--- | :--- | :--- |
| **01** | `01 Phase 3.1 OCR Acceptance.md` | Acceptance | Integrasi Apple Vision OCR lokal pada macOS tanpa cloud API. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/02%20Phase%203.1%20Apple%20Vision%20OCR/01%20Phase%203.1%20OCR%20Acceptance.md) |
| **02** | `02 Phase 3.1.1 Full Book Acceptance.md` | Acceptance | Uji ekstraksi dan rekonstruksi semantik buku utuh multi-bab. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/02%20Phase%203.1%20Apple%20Vision%20OCR/02%20Phase%203.1.1%20Full%20Book%20Acceptance.md) |
| **03** | `03 Phase 3.1.2 Full Book Reading Quality.md` | Quality | Audit tipografi, keterbacaan paragraf terjustifikasi, dan preservasi dialog. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/02%20Phase%203.1%20Apple%20Vision%20OCR/03%20Phase%203.1.2%20Full%20Book%20Reading%20Quality.md) |

---

### 5.3 Sub-Fase 3.2 s.d. 3.5 (`03 Phase 3.2`, `04 Phase 3.3`, `05 Phase 3.5`)

| No | Folder & Dokumen | Kategori | Ringkasan Isi | Tautan |
| :---: | :--- | :--- | :--- | :--- |
| **01** | `03 Phase 3.2 .../01 Phase 3.2 OCR Search.md` | Feature | Integrasi in-book search pada struktur semantik terekonstruksi. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/03%20Phase%203.2%20In-Book%20Search/01%20Phase%203.2%20OCR%20Search.md) |
| **02** | `03 Phase 3.2 .../02 Phase 3.2.1 Search Accuracy Audit.md` | Audit | Audit akurasi fuzzy match, bounding box PDF, dan navigasi siklis. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/03%20Phase%203.2%20In-Book%20Search/02%20Phase%203.2.1%20Search%20Accuracy%20Audit.md) |
| **03** | `04 Phase 3.3 .../01 Phase 3.3 Annotations Report.md` | Milestone | Text selection toolbar, palet sorotan 6-warna, dan panel catatan. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/04%20Phase%203.3%20Annotations/01%20Phase%203.3%20Annotations%20Report.md) |
| **04** | `05 Phase 3.5 .../01 Phase 3.5 Real World Product Validation.md` | Validation | Evaluasi performa OCR pada 7 kategori korpus buku riil. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/05%20Phase%203.5%20Real%20Corpus%20Validation/01%20Phase%203.5%20Real%20World%20Product%20Validation.md) |
| **05** | `05 Phase 3.5 .../02 Phase 3.5.1 Independent Release Audit.md` | Audit | Audit independen: temuan dehyphenation (CRIT-01) dan metrik (CRIT-02). | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/05%20Phase%203.5%20Real%20Corpus%20Validation/02%20Phase%203.5.1%20Independent%20Release%20Audit.md) |
| **06** | `05 Phase 3.5 .../03 Phase 3.5.2 Remediation Verification.md` | Verification | Verifikasi penyelesaian temuan audit dengan tabel leksem tertutup. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/05%20Phase%203.5%20Real%20Corpus%20Validation/03%20Phase%203.5.2%20Remediation%20Verification.md) |
| **07** | `05 Phase 3.5 .../04 Phase 3.5.3 Native and E2E Validation.md` | E2E | Uji kestabilan memori native dan penjelajahan dokumen panjang. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/05%20Phase%203.5%20Real%20Corpus%20Validation/04%20Phase%203.5.3%20Native%20and%20E2E%20Validation.md) |

---

### 5.4 Sub-Fase Book Mode Redesign (`06 Book Mode/`)

| No | Dokumen | Kategori | Ringkasan Isi | Tautan |
| :---: | :--- | :--- | :--- | :--- |
| **01** | `01 Book Mode Horizontal Pagination Report.md` | Milestone | Paginasi horizontal kolom ganda dan resolusi anchor kata presisi. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/06%20Book%20Mode/01%20Book%20Mode%20Horizontal%20Pagination%20Report.md) |
| **02** | `02 Book Mode Reading Experience Redesign Report.md` | Redesign | Redesain Book Mode bergaya buku cetak mewah (margin, drop cap, TOC leaders). | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/06%20Book%20Mode/02%20Book%20Mode%20Reading%20Experience%20Redesign%20Report.md) |
| **03** | `03 Real Book Acceptance Report.md` | Acceptance | Uji visual buku riil bahasa Indonesia (Bab I–V, halaman legal). | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/06%20Book%20Mode/03%20Real%20Book%20Acceptance%20Report.md) |
| **04** | `04 Final Product Acceptance Report.md` | Acceptance | Evaluasi kesiapan produk menyeluruh lintas mode membaca dan tema. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/06%20Book%20Mode/04%20Final%20Product%20Acceptance%20Report.md) |
| **05** | `05 Final Release Readiness Report.md` | Release | Pemeriksaan checklist akhir sebelum pembuatan Release Candidate. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/06%20Book%20Mode/05%20Final%20Release%20Readiness%20Report.md) |

---

### 5.5 Sub-Fase Release Candidates & UI Audits (`07 Release Candidates 3.6 to 3.9A/`)

| No | Dokumen | Kategori | Ringkasan Isi | Tautan |
| :---: | :--- | :--- | :--- | :--- |
| **01** | `01 Phase 3.6 Release Candidate Report.md` | Release Candidate | Laporan Release Candidate Phase 3.6 dengan uji multi-buku 1.238 halaman. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/07%20Release%20Candidates%203.6%20to%203.9A/01%20Phase%203.6%20Release%20Candidate%20Report.md) |
| **02** | `02 Phase 3.7 Independent Audit Report.md` | Audit | Audit verifikasi independen atas metrik evaluasi buku dan pemurnian test suite Phase 3.6. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/07%20Release%20Candidates%203.6%20to%203.9A/02%20Phase%203.7%20Independent%20Audit%20Report.md) |
| **03** | `03 Phase 3.8 Artifact Integrity Report.md` | Integrity | Uji integritas backup, restore, dan relink PDF pada format bundle mandiri. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/07%20Release%20Candidates%203.6%20to%203.9A/03%20Phase%203.8%20Artifact%20Integrity%20Report.md) |
| **04** | `04 Phase 3.9A OCR Pilot Report.md` | Pilot | Uji percontohan throughput pemrosesan background OCR berbasis Apple Vision pada macOS. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/07%20Release%20Candidates%203.6%20to%203.9A/04%20Phase%203.9A%20OCR%20Pilot%20Report.md) |
| **05** | `05 Phase 3.9A Reader UI Audit.md` | UI Audit | Audit ergonomi UI layar pembaca, hierarchy tombol, dan konsistensi status bar. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/07%20Release%20Candidates%203.6%20to%203.9A/05%20Phase%203.9A%20Reader%20UI%20Audit.md) |
| **06** | `06 Reader Minimalist UI Report.md` | UI Design | Implementasi antarmuka baca minimalis dengan auto-hide bar atas dan indikator hover tepi. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/07%20Release%20Candidates%203.6%20to%203.9A/06%20Reader%20Minimalist%20UI%20Report.md) |
| **07** | `07 Reader Typography Refinement Report.md` | Typography | Pemurnian tipografi, pengaturan spasi baris, dan penyesuaian font multi-resolusi. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/07%20Release%20Candidates%203.6%20to%203.9A/07%20Reader%20Typography%20Refinement%20Report.md) |
| **08** | `08 Reader UI Alignment and Glass Progress Bar.md` | UI Design | Penyesuaian alignment top bar, glass-effect progress bar, dan konsistensi inset antar panel. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/01%20Historical%20Engine%20v1.1/07%20Release%20Candidates%203.6%20to%203.9A/08%20Reader%20UI%20Alignment%20and%20Glass%20Progress%20Bar.md) |

---

## 6. Laporan Siklus II — Modernisasi UI/UX v1.2+ (`03 Reports/02 Modernization v1.2/`)

> [!NOTE]
> Ini adalah rangkaian inisiatif modernisasi antarmuka dan pengalaman pengguna desktop macOS yang aktif dikembangkan pada **November 2026**.

| No | Dokumen | Topik & Cakupan | Tautan |
| :---: | :--- | :--- | :--- |
| **01** | `01 Phase 1 Design Tokens and Strings.md` | Sentralisasi skala spasi (`AppThemeTokens`), skala radius, konstanta breakpoint macOS, dan kamus terminologi UX terpadu (`AppStrings`). | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/02%20Modernization%20v1.2/01%20Phase%201%20Design%20Tokens%20and%20Strings.md) |
| **02** | `02 Phase 2 macOS Responsive Shell.md` | Shell adaptif desktop macOS dengan 3 breakpoint (`compact < 700dp`, `standard 900dp`, `expansive >= 1280dp`), Icon Rail ramping ($64\text{ dp}$), Native Sidebar ($220\text{ dp}$), dan sinkronisasi rak buku aktif. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/02%20Modernization%20v1.2/02%20Phase%202%20macOS%20Responsive%20Shell.md) |
| **03** | `03 Phase 5 Reading Progress Calculator.md` | Kalkulator progres membaca mode-aware (`ReadingProgressCalculator`), pemisahan metrik fisik (PDF) vs semantik (Book Mode), dan estimasi waktu baca per bab. | [`Buka`](file:///Users/davindalana/Documents/Project/Digital%20Books/docs/03%20Reports/02%20Modernization%20v1.2/03%20Phase%205%20Reading%20Progress%20Calculator.md) |

---

## 7. Bukti Visual Pengujian Native macOS (`visual_evidence/`)

> [!IMPORTANT]
> **Dilarang memindahkan atau mengubah nama direktori `docs/visual_evidence/`!**
> Direktori ini diakses secara langsung oleh rangkaian tes otomatis (`test/*_test.dart`) dan alat native Swift (`tools/capture_native_windows.swift`) untuk memverifikasi regresi visual tata letak macOS.

Sub-direktori bukti visual:
- `phase_2_shell/` & `phase_2_native/`: Screenshot shell window macOS responsive (compact 700dp, standard 900dp, expansive 1280dp) yang dihasilkan dari inisiatif modernisasi Siklus II.
- `book_mode_acceptance/`: Tangkapan layar spread bab 1–5 Book Mode.
- `book_mode_redesign/`: Perbandingan before/after perombakan tampilan Book Mode.
- `enhancement_fix/`: Visual komparasi preset enhancement (Gentle, Balanced, Strong, Original).
- `minimalist_ui/`: Bukti visual auto-hide controls, hover strip, tema, dan responsivitas window.
- `native_transitions/`: Frame demi frame kurva kubik transisi curl native (0 ms hingga 340 ms).
- `phase_3_1_1/` & `phase_3_1_2/`: Bukti visual perbandingan scan asli vs reflowable layout.
- `phase_3_2/` & `phase_3_2_1/`: Visual in-book search, highlight traversal, dan cycling match.
- `phase_3_3/`: Visual text selection toolbar, color picker 6-warna, dan panel anotasi.
- `phase_3_5/` & `phase_3_6/`: Visual korpus uji buku nyata multi-genre.
- `scan_enhancement/`: Bukti filter kontras dan penghapusan paper noise.
- `transitions/`: Sequence transisi spread rendering PDFium.

---

## 8. Pedoman Penulisan Dokumentasi Baru

Setiap penambahan dokumen baru wajib mengikuti konvensi baku:

1. **Format Penamaan Berkas & Folder**:
   - Gunakan format judul bersih menggunakan spasi tanpa garis bawah (`_`), diawali dengan dua digit nomor urut (`01`, `02`, `03`...), contoh: `04 Phase 4 Native Transitions.md`.
2. **Penentuan Lokasi Folder**:
   - Standar Tata Kelola $\to$ `docs/01 Governance/`
   - Spesifikasi Arsitektur / Blueprint $\to$ `docs/02 Architecture/`
   - Laporan Pipeline Mesin Historis (v1.1) $\to$ `docs/03 Reports/01 Historical Engine v1.1/`
   - Laporan Inisiatif Modernisasi (v1.2+) $\to$ `docs/03 Reports/02 Modernization v1.2/`
   - Screenshot Uji Coba $\to$ `docs/visual_evidence/<kategori>/`
3. **Format Metadata Dokumen**:
   Sertakan blok metadata pada awal setiap laporan:
   ```markdown
   # Judul Dokumen

   > **Metadata Dokumen**
   > - **Siklus / Inisiatif**: Siklus II — Modernization & Apple Books Polish (v1.2+)
   > - **Modul / Kategori**: Phase X (...)
   > - **Urutan Dokumen**: Dokumen X dari Y pada ...
   > - **Tanggal**: DD MMMM YYYY
   > - **Status Verifikasi**: PASS / CONDITIONAL PASS / FAIL
   ```
4. **Pencatatan ke Indeks**:
   - Daftarkan dokumen baru ke tabel yang relevan di dalam `docs/README.md`.
