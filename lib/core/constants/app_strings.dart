/// Centralized Indonesian UX strings for Digital Books.
/// Ensures consistent nomenclature, eliminate duplicate terms,
/// and provide friendly action-oriented messaging.
abstract final class AppStrings {
  // --- App Name ---
  static const String appName = 'Digital Books';
  static const String appNameShort = 'Buku';

  // --- Sidebar Category Headers ---
  static const String categoryPustaka = 'PUSTAKA';
  static const String categoryKoleksi = 'KOLEKSI';
  static const String categoryCatatan = 'CATATAN';

  // --- Navigation Section Labels ---
  static const String navSedangDibaca = 'Sedang Dibaca';
  static const String navSemuaBuku = 'Semua Buku';
  static const String navSelesai = 'Selesai';
  static const String navKoleksi = 'Koleksi';
  static const String navPenanda = 'Penanda';
  static const String navSorotanCatatan = 'Sorotan & Catatan';
  static const String navPengaturan = 'Pengaturan';

  // --- Primary Action Buttons & CTAs ---
  static const String actionTambahBuku = 'Tambah Buku';
  static const String actionTambahBukuTooltip = 'Tambah buku PDF ke pustaka';
  static const String actionImporPdf = 'Impor PDF…';
  static const String actionLanjutkan = 'Lanjutkan';
  static const String actionMulai = 'Mulai';
  static const String actionLihatSemua = 'Lihat semua';
  static const String actionHapus = 'Hapus';
  static const String actionBatal = 'Batal';
  static const String actionSimpan = 'Simpan';
  static const String actionUbahNama = 'Ubah Nama';
  static const String actionTutup = 'Tutup';
  static const String actionKoleksiBaru = 'Koleksi Baru';

  // --- Book Metadata Fallbacks & Labels ---
  static const String unknownAuthor = 'Penulis tidak diketahui';
  static const String unknownTitle = 'Tanpa Judul';
  static const String formatHalaman = 'Halaman';
  static const String formatBuku = 'buku';

  // --- Reading Shelves & Sections ---
  static const String shelfBukuLainSedangDibaca =
      'Buku lain yang sedang kamu baca';
  static const String shelfBaruDitambahkan = 'Baru ditambahkan';

  // --- Badges ---
  static const String badgeHasilPindai = 'Hasil pindai';
  static const String badgeHasilPindaiTooltip =
      'Buku ini berasal dari pindaian gambar dan membutuhkan OCR untuk pencarian kata dan teks fleksibel.';
  static const String badgeTeksDigital = 'Teks Digital';

  // --- Search ---
  static const String searchHint = 'Cari judul, penulis, atau koleksi…';
  static const String searchTooltip = 'Cari (⌘K)';
  static const String searchClear = 'Hapus pencarian';
  static String searchResultsFor(String query) =>
      'Hasil pencarian untuk "$query"';
  static String searchNoResults(String query) =>
      'Tidak ada buku yang cocok dengan "$query". Coba kata kunci lain.';

  // --- Sort Options ---
  static const String sortLabel = 'Urutkan';
  static const String sortTooltip = 'Urutkan buku';
  static const String sortRecentlyAdded = 'Baru Ditambahkan';
  static const String sortOldestAdded = 'Paling Awal Ditambahkan';
  static const String sortTitleAsc = 'Judul (A ke Z)';
  static const String sortTitleDesc = 'Judul (Z ke A)';
  static const String sortAuthorAsc = 'Penulis (A ke Z)';
  static const String sortProgressDesc = 'Progres (Tertinggi)';
  static const String sortProgressAsc = 'Progres (Terendah)';

  // --- View Mode ---
  static const String viewModeGrid = 'Tampilan Kisi';
  static const String viewModeList = 'Tampilan Daftar';

  // --- Collections ---
  static const String collectionsHeader = 'Koleksi';
  static const String createCollectionTitle = 'Koleksi Baru';
  static const String createCollectionHint =
      'Nama koleksi (mis. Filsafat, Sains, Novel)';
  static const String renameCollectionTitle = 'Ubah Nama Koleksi';
  static const String deleteCollectionTitle = 'Hapus Koleksi?';
  static String deleteCollectionMessage(String name) =>
      'Apakah Anda yakin ingin menghapus koleksi "$name"? Buku dalam koleksi ini tetap tersimpan aman di pustaka Anda.';
  static const String deleteCollectionConfirm = 'Hapus Koleksi';

  // --- Empty States ---
  static const String emptyLibraryTitle = 'Pustaka Anda Masih Kosong';
  static const String emptyLibrarySubtitle =
      'Tambahkan buku PDF dari perangkat Anda untuk mulai membaca dengan pengalaman native macOS.';

  static const String emptySedangDibacaTitle =
      'Belum Ada Buku yang Sedang Dibaca';
  static const String emptySedangDibacaSubtitle =
      'Pilih buku dari Semua Buku untuk mulai membaca dan melihat progres bacaan Anda di sini.';

  static const String emptySemuaBukuTitle = 'Belum Ada Buku di Pustaka';
  static const String emptySemuaBukuSubtitle =
      'Klik tombol "Tambah Buku" untuk memasukkan file PDF ke dalam Digital Books.';

  static const String emptySelesaiTitle = 'Belum Ada Buku yang Selesai';
  static const String emptySelesaiSubtitle =
      'Buku yang telah Anda baca hingga tuntas akan tersimpan rapi di sini.';

  static const String emptyKoleksiTitle = 'Belum Ada Koleksi';
  static const String emptyKoleksiSubtitle =
      'Kelompokkan buku favorit, riset, atau topik tertentu untuk akses yang lebih rapi.';

  static const String emptyKoleksiItemTitle = 'Koleksi Ini Masih Kosong';
  static const String emptyKoleksiItemSubtitle =
      'Buka opsi buku (•••) dan pilih "Kelola Koleksi" untuk menambahkan buku ke koleksi ini.';

  static const String emptyPenandaTitle = 'Belum Ada Penanda';
  static const String emptyPenandaSubtitle =
      'Gunakan tombol penanda saat membaca untuk menyimpan halaman favorit di sini.';

  static const String emptySorotanTitle = 'Belum Ada Sorotan atau Catatan';
  static const String emptySorotanSubtitle =
      'Sorot kalimat penting dan simpan catatan saat membaca buku teks fleksibel.';

  // --- Reader Mode & Chrome (for Phase 4 prep & integration) ---
  static const String readerModeTeks = 'Teks';
  static const String readerModeTeksTooltip =
      'Mode teks fleksibel (reflowable): ukuran huruf dan tata letak dapat disesuaikan.';
  static const String readerModePdfAsli = 'PDF Asli';
  static const String readerModePdfAsliTooltip =
      'Mode dokumen asli: mempertahankan tata letak halaman asli PDF.';
  static const String readerDaftarIsi = 'Daftar Isi';
  static const String readerKembali = 'Kembali';
  static const String readerCari = 'Cari dalam buku';
  static const String readerAnotasi = 'Sorotan & Catatan';
  static const String readerTampilan = 'Tampilan';
  static const String readerPenanda = 'Penanda';
  static const String readerPilihanLainnya = 'Pilihan Lainnya';

  // --- Dialog & Delete Confirmation ---
  static const String deleteBookTitle = 'Hapus Buku?';
  static String deleteBookMessage(String title) =>
      'Apakah Anda yakin ingin menghapus "$title"? File PDF, cover, dan progres membaca akan dihapus secara permanen.';
  static const String deleteBookConfirm = 'Hapus Buku';
}
