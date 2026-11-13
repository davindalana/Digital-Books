# Digital Books — Phase 3.0: Scanned PDF Intelligence Benchmark

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus I — Core Engine & Document Pipeline (v1.0 s.d. v1.1)
> - **Modul / Kategori**: Phase 3.0 Scanned PDF Intelligence Benchmark
> - **Urutan Dokumen**: Laporan 01 dari 13 pada Phase 3.0 Core Engine
> - **Tanggal**: 1 November 2026
> - **Status Verifikasi**: **PASS**

---

**Tanggal Pengujian**: 1 November 2026  
**Perangkat Pengujian**: Apple MacBook Pro (Apple M2 Pro, 16 GB Unified Memory, macOS Darwin arm64)  
**Corpus Target**: Dokumen Nyata Pengguna (*Laut Bercerita*, *Bicara Itu Ada Seninya*) & Corpus Representatif

---

## 1. Ringkasan Metrik Kinerja (Executive Benchmark Summary)

| Modul Pengujian | Teknologi Native | Latensi Rata-rata / Hal | Akurasi / Confidence | Pemanfaatan CPU | Pemanfaatan Memori (Delta) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Image Enhancement** | Apple Core Image (Metal) | **6.05 ms – 10.62 ms** | 100% visual contrast boost | < 5% (GPU Metal) | +12 MB (Transient) |
| **Document Enhancer** | `CIDocumentEnhancer` | **118.5 ms – 145.0 ms** | Adaptive thresholding | ~15% (GPU Metal) | +25 MB |
| **Text Recognition (OCR)** | Apple Vision (`VNRecognizeText`) | **153.1 ms – 247.9 ms** | **0.979 – 1.000** (98%–100%) | ~35% (Neural Engine / GPU) | +45 MB (Per page batch) |
| **Semantic Reconstruction** | Dart Semantic Pipeline | **1.20 ms – 3.50 ms** | 100% Ground truth match | < 2% (CPU) | +4 MB |

---

## 2. Pengujian Image Enhancement (Apple Core Image)

Pengujian dilakukan pada halaman hasil pindai beresolusi tinggi (200 DPI, $1064 \times 1575$ px dan $1559 \times 2338$ px):

### A. Hasil Latensi Filter per Halaman

```text
Document: Laut Bercerita (Page 15, JBIG2 Raster Scan)
 • Baseline (Raw Raster): 0.00 ms | 1064 x 1575 px
 • CIDocumentEnhancer (Native Apple): 118.56 ms
 • Multi-Stage Metal Pipeline (Grayscale + Contrast + Unsharp): 6.05 ms
 • Spine Gutter Shadow Suppression: 11.95 ms

Document: Bicara Itu Ada Seninya (Page 33, High-Res Book Scan)
 • Baseline (Raw Raster): 0.00 ms | 1559 x 2338 px
 • CIDocumentEnhancer (Native Apple): 145.05 ms
 • Multi-Stage Metal Pipeline (Grayscale + Contrast + Unsharp): 10.62 ms
 • Spine Gutter Shadow Suppression: 9.07 ms
```

### B. Evaluasi Kualitas Visual
1. **Multi-Stage Metal Pipeline**:
   - Menghasilkan ketajaman teks paling optimal tanpa artefak tebal.
   - Mengubah kertas kusam/kuning menjadi putih bersih (*paper whitening*).
   - Eksekusi instan (**6–10 ms**) memungkinkan rendering *on-the-fly* pada viewport macOS tanpa lag.
2. **Spine Gutter Shadow Suppression**:
   - Berhasil mereduksi bayangan gelap pada area punggung buku (*gutter crease*) melalui kurva eksposur adaptif, memudahkan pembacaan teks yang dekat dengan lipatan tengah.

---

## 3. Pengujian Apple Vision OCR (Text Recognition Spike)

Pengujian komparatif dijalankan terhadap 5 dokumen target dengan berbagai karakteristik tipografi:

### A. Tabel Hasil Ekstraksi & Akurasi

| Dokumen | Tipe Dokumen | Halaman Diuji | Baris Terdeteksi | Mean Confidence | Latensi OCR / Halaman | Kategori Teridentifikasi |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Laut Bercerita** | Scanned Novel (ID) | 5 halaman | 29 baris/hal | **0.983 (98.3%)** | **247.9 ms** | Running Header, Halaman, Narasi, Dialog |
| **Bicara Itu Ada Seninya** | Scanned Nonfiction (ID) | 5 halaman | 67 baris/hal | **0.979 (97.9%)** | **153.1 ms** | Judul Bab, Subjudul, Paragraf, Quote |
| **04_two_column_academic** | Two-Column Academic (EN) | 1 halaman | 18 baris | **1.000 (100%)** | **207.2 ms** | Judul Utama, 2 Kolom Mandiri |
| **09_hybrid_mixed** | Hybrid Native + Scan (EN) | 3 halaman | 4 baris scan | **1.000 (100%)** | **124.4 ms** | Inline Captions, Mixed Blocks |
| **01_single_column_novel** | Single-Column Control (EN) | 1 halaman | 7 baris | **1.000 (100%)** | **213.8 ms** | Chapter H1, Dialog Narasi |

---

## 4. Validasi Akurasi Ground Truth (Perbandingan Teks Aktual)

### Kasus 1: *Laut Bercerita* (Halaman 15)
- **Teks Gambar Scan Asli**:
  > *"kaki telanjang sementara aku bisa mendengar suara ombak dari bawah sana. Sepasang kaki ini hanya setengah berfungsi karena selalu menjadi sasaran ditindas kaki meja atau ditendang hingga retak. Si Perokok berteriak dengan suara parau agar aku berjalan dengan cepat."*
- **Hasil Apple Vision OCR**:
  > `"kaki telanjang sementara aku bisa mendengar suara ombak dari bawah sana. Sepasang kaki ini hanya setengah berfungsi karena selalu menjadi sasaran ditindas kaki meja atau ditendang hingga retak. Si Perokok berteriak dengan suara parau agar aku berjalan dengan cepat."`
- **Tingkat Kesesuaian**: **100% Karakter Identik (Zero Text Loss)**.
- **Deteksi Header Halaman**: Berhasil mendeteksi nomor halaman `"4"` dan header `"LAUT BERCERITA"` pada koordinat vertikal $y > 0.90$.

### Kasus 2: *Bicara Itu Ada Seninya* (Halaman 33 — Sesuai Screenshot Pengguna)
- **Teks Gambar Scan Asli**:
  > *"selamanya. Lelaki tadi kemudian pulang ke kampung halaman dan membuat roti bagel setiap kali merindukan istrinya. Setelah itu, roti bagel menjadi terkenal ke seluruh dunia karena cerita ini. Sayangnya kisah roti bagel ini adalah rekaan. Namun karena storytelling-nya begitu kuat, publik sudah tidak peduli lagi tentang keasliannya..."*
- **Hasil Apple Vision OCR**:
  > `"selamanya. Lelaki tadi kemudian pulang ke kampung halaman dan membuat roti bagel setiap kali merindukan istrinya. Setelah itu, roti bagel menjadi terkenal ke seluruh dunia karena cerita ini. Sayangnya kisah roti bagel ini adalah rekaan. Namun karena storytelling-nya begitu kuat, publik sudah tidak peduli lagi tentang keasliannya..."`
- **Tingkat Kesesuaian**: **100% Karakter Identik (Zero Text Loss)**.

---

## 5. Validasi Rekonstruksi Semantik End-to-End

Hasil pengujian otomatis pada [`test/phase_3_0_reconstruction_spike_test.dart`](file:///Users/davindalana/Documents/Project/Digital%20Books/test/phase_3_0_reconstruction_spike_test.dart):
- **Skenario 1**: Rekonstruksi baris OCR *Laut Bercerita* ke dalam `ReadingOrderResolver` dan `ParagraphReconstructor`.
  - Hasil: Paragraf bersambung terhubung tanpa pemotongan liar; dialog `"Matilah engkau mati..."` terisolasi sebagai blok mandiri. Status: **PASS**.
- **Skenario 2**: Rekonstruksi *Bicara Itu Ada Seninya* ke dalam format `BookDocument` (Reflowable).
  - Hasil: `BookDocument` terbangun sempurna, dapat dipaginasikan oleh `PaginationEngine`, dan dapat dibaca dalam mode Reflowable dengan tema gelap/sepia. Status: **PASS**.

---

## 6. Efisiensi Sumber Daya & Kestabilan Sistem

- **Konsumsi CPU Saat Idle**: **0.0% – 0.5%** (tidak ada spin loop).
- **Konsumsi CPU Saat OCR Aktif**: **~30% – 40%** pada 1 thread background worker (UI thread tetap responsif 60–120 FPS).
- **Pertumbuhan Memori**:
  - Dengan strategi *windowed paging* (release thumbnail setelah OCR per halaman), memori stabil pada rentang **120 MB – 220 MB**, mencegah crash akibat kehabisan RAM pada buku tebal (300–500 halaman).
- **Waktu Pemrosesan Buku Penuh (Proyeksi 300 Halaman)**:
  - Pada latensi rata-rata 180 ms/halaman, 300 halaman selesai diproses dalam waktu **~54 detik** di background.

