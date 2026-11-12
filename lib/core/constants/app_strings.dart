/// Centralized English UX strings for Digital Books.
/// Ensures consistent nomenclature, eliminate duplicate terms,
/// and provide friendly action-oriented messaging.
abstract final class AppStrings {
  // --- App Name ---
  static const String appName = 'Digital Books';
  static const String appNameShort = 'Books';

  // --- Sidebar Category Headers ---
  static const String categoryPustaka = 'LIBRARY';
  static const String categoryKoleksi = 'COLLECTIONS';
  static const String categoryCatatan = 'NOTES';

  // --- Navigation Section Labels ---
  static const String navSedangDibaca = 'Currently Reading';
  static const String navSemuaBuku = 'All Books';
  static const String navSelesai = 'Finished';
  static const String navKoleksi = 'Collections';
  static const String navPenanda = 'Bookmarks';
  static const String navSorotanCatatan = 'Highlights & Notes';
  static const String navPengaturan = 'Settings';

  // --- Primary Action Buttons & CTAs ---
  static const String actionTambahBuku = 'Add Book';
  static const String actionTambahBukuTooltip = 'Add a PDF to your library';
  static const String actionImporPdf = 'Import PDF…';
  static const String actionLanjutkan = 'Continue Reading';
  static const String actionMulai = 'Start Reading';
  static const String actionLihatSemua = 'View All';
  static const String actionHapus = 'Delete';
  static const String actionBatal = 'Cancel';
  static const String actionSimpan = 'Save';
  static const String actionUbahNama = 'Rename';
  static const String actionTutup = 'Close';
  static const String actionKoleksiBaru = 'New Collection';

  // --- Book Metadata Fallbacks & Labels ---
  static const String unknownAuthor = 'Unknown Author';
  static const String unknownTitle = 'Untitled';
  static const String formatHalaman = 'Pages';
  static const String formatBuku = 'books';

  // --- Reading Shelves & Sections ---
  static const String shelfBukuLainSedangDibaca = 'More Books You’re Reading';
  static const String shelfBelumDimulai = 'Not Started';
  static const String shelfBaruDitambahkan = 'Recently Added';

  // --- Reading Progress Statuses ---
  static const String statusBelumDibaca = 'Unread';
  static const String statusSelesai = 'Finished';
  static const String statusBaruDimulai = 'Just Started';

  // --- Badges ---
  static const String badgePindai = 'Scanned';
  static const String badgeHasilPindai = 'Scanned';
  static const String badgeHasilPindaiTooltip =
      'This book contains scanned pages. Run OCR to enable text search and reflowable reading.';
  static const String badgePindaiOcrTooltip =
      'Scanned document • Text recognized (OCR)';
  static const String badgePindaiNeedsOcrTooltip =
      'Scanned document • OCR required';
  static const String badgeTeksDigital = 'Digital Text';

  // --- Search ---
  static const String searchHint = 'Search titles, authors, or collections…';
  static const String searchTooltip = 'Search (⌘K)';
  static const String searchClear = 'Clear search';
  static String searchResultsFor(String query) => 'Search results for "$query"';
  static String searchNoResults(String query) =>
      'No books match "$query". Try another search.';

  // --- Sort Options ---
  static const String sortLabel = 'Sort';
  static const String sortTooltip = 'Sort books';
  static const String sortRecentlyAdded = 'Recently Added';
  static const String sortOldestAdded = 'Oldest First';
  static const String sortTitleAsc = 'Title (A–Z)';
  static const String sortTitleDesc = 'Title (Z–A)';
  static const String sortAuthorAsc = 'Author (A–Z)';
  static const String sortProgressDesc = 'Progress (Highest)';
  static const String sortProgressAsc = 'Progress (Lowest)';

  // --- View Mode ---
  static const String viewModeGrid = 'Grid view';
  static const String viewModeList = 'List view';

  // --- Collections ---
  static const String collectionsHeader = 'Collections';
  static const String createCollectionTitle = 'New Collection';
  static const String createCollectionHint =
      'Collection name (e.g. Philosophy, Science, Fiction)';
  static const String renameCollectionTitle = 'Rename Collection';
  static const String deleteCollectionTitle = 'Delete Collection?';
  static String deleteCollectionMessage(String name) =>
      'Are you sure you want to delete "$name"? Books in this collection will remain safely in your library.';
  static const String deleteCollectionConfirm = 'Delete Collection';

  // --- Empty States ---
  static const String emptyLibraryTitle = 'Your Library Is Empty';
  static const String emptyLibrarySubtitle =
      'Add a PDF from your device to start reading in the native macOS app.';

  static const String emptySedangDibacaTitle = 'Nothing in Progress';
  static const String emptySedangDibacaSubtitle =
      'Choose a book from All Books to start reading and track your progress here.';

  static const String emptySemuaBukuTitle = 'No Books in Your Library';
  static const String emptySemuaBukuSubtitle =
      'Select “Add Book” to import a PDF into Digital Books.';

  static const String emptySelesaiTitle = 'No Finished Books Yet';
  static const String emptySelesaiSubtitle =
      'Books you finish reading will appear here.';

  static const String emptyKoleksiTitle = 'No Collections Yet';
  static const String emptyKoleksiSubtitle =
      'Group your favorite books, research, or topics for quick access.';

  static const String emptyKoleksiItemTitle = 'This Collection Is Empty';
  static const String emptyKoleksiItemSubtitle =
      'Open a book’s options (•••) and choose “Manage Collections” to add it here.';

  static const String emptyPenandaTitle = 'No Bookmarks Yet';
  static const String emptyPenandaSubtitle =
      'Use the bookmark button while reading to save favorite pages here.';

  static const String emptySorotanTitle = 'No Highlights or Notes Yet';
  static const String emptySorotanSubtitle =
      'Highlight key passages and add notes while reading digital text.';

  // --- Reader Mode & Chrome (for Phase 4 prep & integration) ---
  static const String readerModeTeks = 'Book';
  static const String readerModeTeksTooltip =
      'Reflowable text mode: adjust the font size and page layout.';
  static const String readerModePdfAsli = 'PDF';
  static const String readerModePdfAsliTooltip =
      'Original document mode: preserves the PDF page layout.';
  static const String readerDaftarIsi = 'Table of Contents';
  static const String readerKembali = 'Back';
  static const String readerCari = 'Find in Book';
  static const String readerAnotasi = 'Highlights & Notes';
  static const String readerTampilan = 'Appearance';
  static const String readerPenanda = 'Bookmark';
  static const String readerPilihanLainnya = 'More Options';

  // --- Dialog & Delete Confirmation ---
  static const String deleteBookTitle = 'Delete Book?';
  static String deleteBookMessage(String title) =>
      'Are you sure you want to delete "$title"? The PDF, cover, and reading progress will be permanently removed.';
  static const String deleteBookConfirm = 'Delete Book';
}
