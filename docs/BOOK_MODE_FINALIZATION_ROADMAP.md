# BOOK MODE CONTENT FIDELITY & READING QUALITY FINALIZATION

**Project**: Digital Books (macOS Native E-Reader)  
**Status**: ACTIVE ROADMAP  
**Author**: Davin Dalana  
**Date**: 7 November 2026  

---

## 1. Prinsip Utama: Kualitas Pembacaan Manusia

> **Peringatan Kritis**: 419/419 test lulus membuktikan perilaku yang diuji berjalan, **bukan** membuktikan buku hasil rekonstruksi sudah nyaman dibaca manusia.

Tiga klaim yang wajib dibatasi dan diuji ulang secara empiris:
1. **Representasi CER/WER**: Angka CER 0,05% dan WER 0,34% hanya berasal dari 3 kutipan manual, belum mewakili variasi 255 halaman fisik.
2. **Cakupan Pengujian**: 419 tes hijau tidak otomatis memvalidasi keharmonisan tata letak seluruh bab, subbab, dan alur antar-paragraf.
3. **Rendering Native macOS vs Runner**: Screenshot integrasi Flutter runner berbeda dengan kondisi jendela native macOS sesungguhnya (skala window, subpixel rendering, font fallback, dan dynamic resizing).

---

## 2. Pemisahan Tanggung Jawab Arsitektur (Separation of Concerns)

Hindari menyelesaikan masalah secara serampangan menggunakan *ad-hoc regex* atau aturan global yang mengorbankan buku lain. Arsitektur pemrosesan buku dipisahkan secara tegas ke dalam tiga lapisan independen:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. OCR CORRECTION                                               │
│ Tanggung Jawab: Memperbaiki glif/karakter yang salah dikenali.  │
│ Aturan: Harus traceable (bukan blind string replacement).       │
│ Contoh: 'MEMHAK' -> 'MEMIHAK' via kamus audit OCR.              │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. SEMANTIC RECONSTRUCTION                                      │
│ Tanggung Jawab: Mengklasifikasikan blok (kicker, bab, subjudul, │
│ paragraf, daftar hukum, kutipan, TOC, caption ilustrasi).       │
│ Aturan: Penggabungan paragraf terpotong batas halaman MILIK     │
│ lapisan ini (bukan dipaksa di font atau renderer).              │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. PAGINATION & COMPOSITION                                     │
│ Tanggung Jawab: Menentukan penempatan elemen ke halaman layar. │
│ Aturan: Layout adaptif, pencegahan orphan/widow heading,        │
│ pembagian halaman seimbang, margin, line-height, dan ruang teks.│
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Backlog Pekerjaan Terpadu

### P0 — Kualitas Isi & Struktur (Prioritas Tertinggi)
- [ ] **Rekonstruksi Paragraf Lanjutan**: Perbaiki 45 paragraf yang diawali huruf kecil akibat pemotongan batas halaman fisik pada tahap *Semantic Reconstruction*.
- [ ] **Normalisasi Paragraf Pendek**: Kurangi 55 fragmen paragraf yang terlalu pendek tanpa menggabungkan dialog atau paragraf yang memang sengaja terpisah secara semantik.
- [ ] **Akurasi TOC**: Sempurnakan rekonstruksi baris TOC, khususnya indeks testimoni, nomor bab, dan perataan titik pemimpin (*dot leaders*).
- [ ] **Koreksi OCR Terlacak**: Perbaiki kesalahan OCR spesifik (`MEMHAK` $\rightarrow$ `MEMIHAK`) melalui mekanisme koreksi yang memiliki audit trail jelas.

### P1 — Visual & Komposisi Halaman (Prioritas Tinggi)
- [ ] **Keseimbangan Halaman Legal**: Perbaiki layout halaman hak cipta dan klausul hukum agar tidak menyisakan ruang kosong yang janggal (*sparse page*).
- [ ] **Pencegahan Heading Yatim (Orphan Headings)**: Pastikan judul atau subjudul bab terikat kuat dengan paragraf pembukanya dan tidak menggantung di baris terakhir halaman.
- [ ] **Alur Pemenggalan Paragraf**: Pastikan transisi paragraf antar-halaman membaca secara alami tanpa potongan kata atau pemecahan sintaks yang canggung.
- [ ] **Harmonisasi Tipografi**: Kalibrasi margin vertikal/horizontal, *line-height*, ukuran font baca, dan ruang antar-blok untuk sesi membaca panjang.

### P2 — Kelengkapan Buku (Prioritas Lanjutan)
- [ ] **Ekstraksi Gambar/Ilustrasi**: Pipeline ekstraksi gambar dari PDF asli dan penempatannya ke dalam aliran teks digital.
- [ ] **Penempatan Caption & Elemen Visual**: Menjaga asosiasi antara gambar dan caption penjelasnya.
- [ ] **Dukungan Halaman Khusus**: Penanganan halaman dengan layout tabel, diagram, atau ornamen visual khusus.

---

## 4. Kriteria Selesai & Gerbang Penerimaan (Acceptance Gate)

- [ ] **Human Reading Verification**: Pengujian membaca langsung oleh manusia pada **BAB I sampai BAB V (minimal 30–60 menit)** di jendela aplikasi native macOS.
- [ ] **Nol Paragraf Terpenggal Sembarangan**: Alur kalimat antar-halaman mengalir alami.
- [ ] **Navigasi Horizontal Murni**: Pembacaan tetap sepenuhnya horizontal tanpa ada scroll vertikal atau lompatan konten.
- [ ] **Feature Freeze**: Dilarang menambahkan animasi pembalik halaman (page-turn curl), ringkasan AI, atau dekorasi kosmetik lain sebelum fondasi teks dan struktur membaca di atas selesai 100%.

