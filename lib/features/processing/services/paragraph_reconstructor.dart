import 'dart:math' as math;
import 'dart:ui' show Rect;
import 'package:syncfusion_flutter_pdf/pdf.dart' show PdfFontStyle;
import '../models/extracted_page_geometry.dart';
import 'reading_order_resolver.dart';

/// A reconstructed paragraph composed of one or more spatially and semantically unified text lines.
class ReconstructedParagraph {
  final String text;
  final int startPageIndex;
  final int endPageIndex;
  final Rect boundingBox;
  final double fontSize;
  final List<PdfFontStyle> fontStyles;
  final bool isBold;
  final bool isItalic;
  final int lineCount;
  final List<ExtractedTextLine> sourceLines;
  final bool startsWithIndent;
  final bool isDialogue;
  final bool isIsolated; // e.g. single line surrounded by large gaps
  final bool isOrderedList;
  final bool isUnorderedList;
  final bool isCopyright;
  final bool isCaption;

  const ReconstructedParagraph({
    required this.text,
    required this.startPageIndex,
    required this.endPageIndex,
    required this.boundingBox,
    required this.fontSize,
    required this.fontStyles,
    required this.isBold,
    required this.isItalic,
    required this.lineCount,
    required this.sourceLines,
    this.startsWithIndent = false,
    this.isDialogue = false,
    this.isIsolated = false,
    this.isOrderedList = false,
    this.isUnorderedList = false,
    this.isCopyright = false,
    this.isCaption = false,
  });
}

/// D2: Reconstructs coherent paragraphs from ordered text lines using spatial gaps,
/// indentations, punctuation continuity, and de-hyphenation.
class ParagraphReconstructor {
  /// Punctuation marks that signal sentence or paragraph completion.
  static final RegExp _sentenceTerminators = RegExp(r'[.!?…»”"][)\]"\s]*$');

  /// Dialogue openers: quotation marks, em-dash, guillemets.
  static final RegExp _dialogueOpeners = RegExp(r'^(["“‘«—\-]|--\s)');

  /// Ordered list items: "1.", "1)", "(1)", "a.", "i.", etc.
  static final RegExp _orderedListRegex =
      RegExp(r'^(\d+[\.\)]|[a-zA-Z][\.\)]|\([0-9a-zA-Z]+\))\s+');

  /// Unordered list items: bullet, dash, asterisk, en/em-dash
  static final RegExp _unorderedListRegex =
      RegExp(r'^([•\-\*–—]|[\u2022\u2023\u25E6\u2043\u2219])\s+');

  /// Copyright, imprint, and bibliographic metadata prefixes
  static final RegExp _copyrightMetaRegex = RegExp(
    r'^(hak cipta|all rights reserved|dilarang memfotokopi|katalog dalam terbitan|kdt|isbn|diterbitkan oleh|cetakan ke|desain sampul|penata letak|penerjemah|editor:|pemeriksa aksara|ilustrasi:)\b',
    caseSensitive: false,
  );

  /// Captions (figure, image, diagram, table)
  static final RegExp _captionRegex = RegExp(
    r'^(figure|fig\.|gambar|diagram|tabel|table|photo|foto|denah)\s+([0-9ivxlcdm\.]+)?:?',
    caseSensitive: false,
  );

  /// Chapter header markers
  static final RegExp _chapterHeaderRegex = RegExp(
    r'^(chapter|bab|bagian|part|act|hukum)\s*([0-9ivxlcdm]+|[a-z]+)',
    caseSensitive: false,
  );

  /// Location, direction, spatial, and temporal nouns that follow preposition "di" or "ke"
  /// and MUST ALWAYS remain separate words (never joined into a single word).
  static const Set<String> indonesianPrepositionComplements = {
    // Spatial & location nouns
    'rumah', 'kantor', 'sekolah', 'pasar', 'kampus', 'toko', 'gedung', 'kamar', 'ruang',
    'jalan', 'gang', 'lorong', 'kota', 'desa', 'dusun', 'kampung', 'negeri', 'negara',
    'darat', 'laut', 'pantai', 'gunung', 'sungai', 'danau', 'pulau', 'bumi', 'dunia',
    'meja', 'kursi', 'lemari', 'pintu', 'jendela', 'sudut', 'tepi', 'ujung', 'pangkal',
    'tempat', 'lokasi', 'posisi', 'daerah', 'wilayah', 'kawasan', 'lingkungan',
    'seberang', 'sekeliling', 'sekitar', 'sebelah', 'antara', 'tengah', 'samping',
    'depan', 'belakang', 'atas', 'bawah', 'dalam', 'luar', 'balik', 'muka', 'hadapan',
    // Pointers & pronouns
    'sini', 'situ', 'sana', 'mana', 'mana-mana',
    // Temporal nouns
    'hari', 'pagi', 'siang', 'sore', 'malam', 'senja', 'subuh', 'fajar',
    'saat', 'waktu', 'masa', 'kala', 'ketika', 'zaman', 'musim',
    'minggu', 'pekan', 'bulan', 'tahun', 'abad',
  };

  /// Common Indonesian ordinal numbers and nouns taking the 'ke-' prefix.
  static const Set<String> indonesianKePrefixComplements = {
    'satu', 'dua', 'tiga', 'empat', 'lima', 'enam', 'tujuh', 'delapan', 'sembilan', 'sepuluh',
    'sebelas', 'seratus', 'seribu', 'tua', 'kasih', 'hendak',
  };

  /// Known Indonesian coordinate compounds (kata majemuk setara), rhyming reduplications
  /// (dwilingga salin suara), and loan compounds that must retain their hyphen.
  static const Set<String> indonesianPairedCompounds = {
    // Coordinate antonymous & complementary compounds (kata majemuk setara)
    'siang-malam', 'malam-siang',
    'ibu-bapak', 'bapak-ibu',
    'ayah-bunda', 'bunda-ayah',
    'orang-tua',
    'tua-muda', 'muda-tua',
    'suami-istri', 'istri-suami',
    'pria-wanita', 'wanita-pria',
    'putra-putri', 'putri-putra',
    'laki-bini', 'bini-laki',
    'suka-duka', 'duka-suka',
    'jual-beli', 'beli-jual',
    'tanya-jawab', 'jawab-tanya',
    'maju-mundur', 'mundur-maju',
    'naik-turun', 'turun-naik',
    'keluar-masuk', 'masuk-keluar',
    'pulang-pergi', 'pergi-pulang',
    'hidup-mati', 'mati-hidup',
    'besar-kecil', 'kecil-besar',
    'panjang-pendek', 'pendek-panjang',
    'tinggi-rendah', 'rendah-tinggi',
    'luar-dalam', 'dalam-luar',
    'hulu-hilir', 'hilir-hulu',
    'timur-barat', 'utara-selatan',
    'kaya-miskin', 'miskin-kaya',
    'cerdik-pandai',
    'hancur-lebur',
    'alim-ulama',
    'kasih-sayang',
    'belas-kasih',
    'jiwa-raga',
    'harta-benda',
    'sanak-saudara',
    'kaum-kerabat',
    'handai-taulan',
    'caci-maki',
    'budi-pekerti',
    'sopan-santun',
    'ramah-tamah',
    'gotong-royong',
    'asal-usul',

    // Rhyming / ablaut reduplications (dwilingga salin suara)
    'sayur-mayur',
    'lauk-pauk',
    'mondar-mandir',
    'bolak-balik',
    'morat-marit',
    'pontang-panting',
    'serba-serbi',
    'seluk-beluk',
    'warna-warni',
    'desas-desus',
    'cerai-berai',
    'kelap-kelip',
    'kocar-kacir',
    'tunggang-langgang',
    'porak-poranda',
    'tindak-tanduk',
    'hiruk-pikuk',
    'gerak-gerik',
    'terang-benderang',
    'teka-teki',
    'simpang-siur',
    'sunyi-senyap',
    'gelap-gulita',
    'lemah-gemulai',
    'basa-basi',
    'liku-liku',
    'selang-seling',
    'sorak-sorai',
    'corat-coret',
    'compang-camping',
    'riang-gembira',
    'kelang-kabut',
    'kusut-masai',
    'remuk-redam',

    // Common loanword / English hyphenated compounds
    'well-known',
    'self-esteem',
    'long-term',
    'short-term',
    'high-tech',
    'decision-making',
    'problem-solving',
    'state-of-the-art',
    'non-fiction',
    'non-fiksi',
  };

  /// Evaluates whether two words form a valid Indonesian reduplication.
  static bool isIndonesianReduplication(String p1Lower, String p2Lower) {
    if (p1Lower == p2Lower) return true;
    if (p1Lower.endsWith(p2Lower) && p2Lower.length >= 3) return true;

    const prefixes = [
      'ber', 'ter', 'per', 'se', 'meng', 'meny', 'men', 'mem', 'me',
      'peng', 'peny', 'pen', 'pem', 'pe', 'di', 'ke'
    ];

    for (final prefix in prefixes) {
      if (p1Lower.startsWith(prefix) && p1Lower.length > prefix.length) {
        if (p1Lower.substring(prefix.length) == p2Lower) return true;
      }
      if (p2Lower.startsWith(prefix) && p2Lower.length > prefix.length) {
        if (p2Lower.substring(prefix.length) == p1Lower) return true;
      }
    }

    // Morphological nasalization in reciprocal verbs (e.g. tarik-menarik, kejar-mengejar)
    if (p2Lower.startsWith('men') && p2Lower.length > 3 && 't${p2Lower.substring(3)}' == p1Lower) {
      return true;
    }
    if (p2Lower.startsWith('meng') && p2Lower.length > 4 && 'k${p2Lower.substring(4)}' == p1Lower) {
      return true;
    }
    if (p2Lower.startsWith('mem') && p2Lower.length > 3 && 'p${p2Lower.substring(3)}' == p1Lower) {
      return true;
    }
    if (p2Lower.startsWith('meny') && p2Lower.length > 4 && 's${p2Lower.substring(4)}' == p1Lower) {
      return true;
    }

    // Suffix -an (e.g. mobil-mobilan, anak-anakan)
    if (p2Lower.endsWith('an') && p2Lower.length > 2) {
      if (p2Lower.substring(0, p2Lower.length - 2) == p1Lower) return true;
    }

    return false;
  }

  /// Cleans OCR artifacts, normalizes ligatures/unicode, and resolves glued or split words.
  static String cleanOcrText(String raw) => ReconstructedParagraphBuilder.cleanOcrText(raw);

  /// Reconstructs paragraphs across all pages of a document.
  static List<ReconstructedParagraph> reconstructDocument(
    List<PageReadingOrderResult> pageResults,
  ) {
    final allParagraphs = <ReconstructedParagraph>[];
    ReconstructedParagraphBuilder? currentBuilder;

    for (int pIdx = 0; pIdx < pageResults.length; pIdx++) {
      final pageResult = pageResults[pIdx];
      final lines = pageResult.orderedLines;
      if (lines.isEmpty) continue;

      // Calculate the typical (modal) line height and line gap for this page
      final modalMetrics = _calculatePageLineMetrics(lines);

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        // Obvious running headers or page numbers are isolated in place
        if (_isPageNumberOrRunningChrome(line)) {
          if (currentBuilder != null && currentBuilder.lines.isNotEmpty) {
            allParagraphs.add(currentBuilder.build());
            currentBuilder = null;
          }
          allParagraphs.add(ReconstructedParagraphBuilder(line).build());
          continue;
        }

        if (currentBuilder == null) {
          currentBuilder = ReconstructedParagraphBuilder(line);
          continue;
        }

        final prevLine = currentBuilder.lastLine;
        final shouldBreak = _shouldBreakParagraph(
          prevLine: prevLine,
          currentLine: line,
          prevPage: prevLine.pageIndex,
          currentPage: line.pageIndex,
          modalLineGap: modalMetrics.modalGap,
          modalLineHeight: modalMetrics.modalHeight,
        );

        if (shouldBreak) {
          allParagraphs.add(currentBuilder.build());
          currentBuilder = ReconstructedParagraphBuilder(line);
        } else {
          currentBuilder.appendLine(line);
        }
      }
    }

    if (currentBuilder != null && currentBuilder.lines.isNotEmpty) {
      allParagraphs.add(currentBuilder.build());
    }

    return allParagraphs;
  }

  /// Reconstructs paragraphs for a single page in isolation.
  static List<ReconstructedParagraph> reconstructPage(
    PageReadingOrderResult pageResult,
  ) {
    return reconstructDocument([pageResult]);
  }

  /// Determines whether a new paragraph should begin between prevLine and currentLine.
  static bool _shouldBreakParagraph({
    required ExtractedTextLine prevLine,
    required ExtractedTextLine currentLine,
    required int prevPage,
    required int currentPage,
    required double modalLineGap,
    required double modalLineHeight,
  }) {
    final currentTrimmed = currentLine.text.trim();
    final prevTrimmed = prevLine.text.trim();

    // 1. List Item checks (Ordered and Unordered):
    // A line starting with 1., 2., a., •, -, * always begins a distinct list item!
    if (_orderedListRegex.hasMatch(currentTrimmed) ||
        _unorderedListRegex.hasMatch(currentTrimmed)) {
      return true;
    }
    // If previous line was a list item and either finished or has vertical separation
    if (_orderedListRegex.hasMatch(prevTrimmed) ||
        _unorderedListRegex.hasMatch(prevTrimmed)) {
      if (_sentenceTerminators.hasMatch(prevTrimmed) ||
          currentLine.bounds.top - prevLine.bounds.bottom >= modalLineGap * 0.9) {
        return true;
      }
    }

    // 2. Copyright, Publishing & Bibliographic Metadata isolation:
    if (_copyrightMetaRegex.hasMatch(currentTrimmed) ||
        _copyrightMetaRegex.hasMatch(prevTrimmed)) {
      return true;
    }

    // 3. Caption isolation (Figure, Gambar, Tabel, Diagram):
    if (_captionRegex.hasMatch(currentTrimmed) ||
        _captionRegex.hasMatch(prevTrimmed)) {
      return true;
    }

    // 4. Chapter markers and prominent standalone title headings:
    if (_chapterHeaderRegex.hasMatch(currentTrimmed) ||
        _chapterHeaderRegex.hasMatch(prevTrimmed)) {
      return true;
    }

    final isPrevAllCapTitle = prevTrimmed.length <= 60 &&
        prevTrimmed == prevTrimmed.toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(prevTrimmed) &&
        !RegExp(r'^\d+$').hasMatch(prevTrimmed);
    final isCurrAllCapTitle = currentTrimmed.length <= 60 &&
        currentTrimmed == currentTrimmed.toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(currentTrimmed) &&
        !RegExp(r'^\d+$').hasMatch(currentTrimmed);
    if (isPrevAllCapTitle != isCurrAllCapTitle) {
      return true;
    }
    if (isPrevAllCapTitle && isCurrAllCapTitle) {
      if (prevPage != currentPage) return true;
      final verticalGap = currentLine.bounds.top - prevLine.bounds.bottom;
      final maxAllowedGap = math.max(currentLine.fontSize * 2.2, 70.0);
      if (verticalGap > maxAllowedGap) return true;
      final fontDiff = (currentLine.fontSize - prevLine.fontSize).abs();
      if (fontDiff >= 2.0) return true;
      return false; // consecutive lines of the same multi-line title
    }

    // 5. Significant Left Margin Indentation or Block Quote offset:
    final leftDiff = (currentLine.bounds.left - prevLine.bounds.left).abs();
    if (leftDiff >= 16.0) {
      return true;
    }

    // 6. Font size change: Headings or captions with distinct font sizes never merge into body text
    final fontDiff = (currentLine.fontSize - prevLine.fontSize).abs();
    if (fontDiff >= 1.5) {
      return true;
    }

    // 7. Bold / Italic transition: e.g. bold heading above plain text body
    if (prevLine.isBold != currentLine.isBold && fontDiff >= 0.8) {
      return true;
    }

    // 8. Dialogue check: If current line starts with dialogue quotation, start new paragraph
    if (_dialogueOpeners.hasMatch(currentTrimmed)) {
      if (_sentenceTerminators.hasMatch(prevTrimmed)) {
        return true;
      }
    }

    // 9. Same page vertical gap analysis
    if (prevPage == currentPage) {
      final verticalGap = currentLine.bounds.top - prevLine.bounds.bottom;

      // If gap is noticeably larger than modal line spacing (e.g. > 1.35x), it's a paragraph break
      // For large heading/title lines, scale the allowed vertical gap to the font size
      final isTitleLines = isPrevAllCapTitle && isCurrAllCapTitle;
      final threshold = isTitleLines
          ? math.max(currentLine.fontSize * 1.6, 45.0)
          : math.max(modalLineGap * 1.35, 5.5);
      if (verticalGap > threshold) {
        return true;
      }

      // First-line Indentation signal:
      final indentDiff = currentLine.bounds.left - prevLine.bounds.left;
      if (indentDiff >= 8.0 && _sentenceTerminators.hasMatch(prevTrimmed)) {
        return true;
      }

      // Right margin termination signal:
      final prevLineEndedPunctuation = _sentenceTerminators.hasMatch(prevTrimmed);
      final widthRatio = prevLine.bounds.width / math.max(currentLine.bounds.width, 1.0);
      if (prevLineEndedPunctuation && widthRatio < 0.80 && verticalGap >= modalLineGap * 0.85) {
        return true;
      }
    } else {
      // 10. Across page boundary:
      if (prevLine.fontSize > 13.0 || prevLine.isBold) {
        return true;
      }

      final isDialogue = _dialogueOpeners.hasMatch(currentTrimmed);
      final indentDiff = currentLine.bounds.left - prevLine.bounds.left;
      final hasFirstLineIndent = indentDiff >= 8.0;

      if (isDialogue || hasFirstLineIndent) {
        return true;
      }

      final prevEndsSentence = _sentenceTerminators.hasMatch(prevTrimmed);
      final startsFarDown = currentLine.bounds.top > 120.0;
      if (prevEndsSentence && startsFarDown) {
        return true;
      }
    }

    // Default: lines belong to the same continuing paragraph!
    return false;
  }

  /// Calculates modal line height and vertical gap between adjacent lines.
  static _LineMetrics _calculatePageLineMetrics(List<ExtractedTextLine> lines) {
    if (lines.length < 2) {
      return _LineMetrics(modalHeight: 12.0, modalGap: 4.0);
    }

    final heights = <double>[];
    final gaps = <double>[];

    for (int i = 0; i < lines.length - 1; i++) {
      final a = lines[i];
      final b = lines[i + 1];
      heights.add(a.bounds.height);

      final gap = b.bounds.top - a.bounds.bottom;
      if (gap > 0 && gap < 30) {
        gaps.add(gap);
      }
    }

    final modalHeight = heights.isNotEmpty ? _findMedian(heights) : 12.0;
    final modalGap = gaps.isNotEmpty ? _findMedian(gaps) : 4.0;

    return _LineMetrics(modalHeight: modalHeight, modalGap: modalGap);
  }

  static double _findMedian(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[mid];
    }
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  /// Identifies obvious standalone page numbers or headers for isolating during paragraph joining.
  static bool _isPageNumberOrRunningChrome(ExtractedTextLine line) {
    final trimmed = line.text.trim();
    // 1. Standalone page numbers in header or footer
    if (RegExp(
      r'^(page\s+\d+(\s+of\s+\d+)?|\d+|-\s*\d+\s*|hal\.?\s*\d+|[ivxlcdm]+)$',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }

    // 2. Running header at the extreme top of page (must be short and all uppercase or chapter heading)
    if (line.bounds.top < 52.0 && line.fontSize <= 11.0 && trimmed.length <= 45) {
      final isAllUpper = trimmed == trimmed.toUpperCase() &&
          RegExp(r'[A-Z]').hasMatch(trimmed) &&
          !trimmed.endsWith(',') &&
          !trimmed.endsWith(';');
      if (isAllUpper) {
        return true;
      }
    }
    return false;
  }
}

class _LineMetrics {
  final double modalHeight;
  final double modalGap;
  _LineMetrics({required this.modalHeight, required this.modalGap});
}

/// Helper class to accumulate text lines and build a unified ReconstructedParagraph.
class ReconstructedParagraphBuilder {
  final List<ExtractedTextLine> lines = [];

  ReconstructedParagraphBuilder(ExtractedTextLine initialLine) {
    lines.add(initialLine);
  }

  ExtractedTextLine get lastLine => lines.last;

  void appendLine(ExtractedTextLine line) {
    lines.add(line);
  }

  /// Cleans OCR artifacts, normalizes ligatures/unicode, and resolves glued or split words.
  static String cleanOcrText(String raw) {
    if (raw.isEmpty) return raw;

    var s = raw;

    // 1. Unicode normalization: Non-breaking spaces and invisible characters
    s = s.replaceAll(RegExp(r'[\u00A0\u200B\uFEFF\u200E\u200F]'), ' ');

    // 2. Ligature expansion
    s = s
        .replaceAll('ﬁ', 'fi')
        .replaceAll('ﬂ', 'fl')
        .replaceAll('ﬀ', 'ff')
        .replaceAll('ﬃ', 'ffi')
        .replaceAll('ﬄ', 'ffl')
        .replaceAll('œ', 'oe')
        .replaceAll('æ', 'ae');

    // 3. Dotless-i artifact from photocopy / scanned print (e.g. "dıtutup" -> "ditutup", "hasıl" -> "hasil")
    s = s.replaceAllMapped(
      RegExp(r'([a-zA-Z])ı|ı([a-zA-Z])'),
      (m) => m.group(0)!.replaceAll('ı', 'i'),
    );
    s = s.replaceAll('ı', 'i');

    // 4. Fix glued punctuation without space: e.g. "kata.Namun" -> "kata. Namun"
    s = s.replaceAllMapped(
      RegExp(r'([a-z0-9])([.,!?;:])([A-Z])'),
      (m) => '${m.group(1)}${m.group(2)} ${m.group(3)}',
    );

    // 5. Fix words split with hyphen and spurious space inside lines:
    // e.g. "se- buah" -> "sebuah", "peng- alaman" -> "pengalaman"
    // BUT preserve Indonesian reduplications: "anak- anak" -> "anak-anak", "mengira- ngira" -> "mengira-ngira"
    // and coordinate compounds: "siang- malam" -> "siang-malam"
    s = s.replaceAllMapped(
      RegExp(r'\b([a-zA-Z]{1,20})[-\u2010\u2013\u2014]\s+([a-zA-Z]{1,20})\b'),
      (m) {
        final part1 = m.group(1)!;
        final part2 = m.group(2)!;
        final p1Lower = part1.toLowerCase();
        final p2Lower = part2.toLowerCase();

        // 5a. Check if reduplication (e.g. anak-anak, tiba-tiba, kata-kata, mengira-ngira)
        if (ParagraphReconstructor.isIndonesianReduplication(p1Lower, p2Lower)) {
          return '$part1-$part2';
        }

        // 5b. Common Indonesian affixes that were split by OCR hyphenation
        const affixes = {
          'se', 'di', 'ke', 'me', 'pe', 'ber', 'ter', 'per', 'men', 'mem',
          'peng', 'meng', 'meny', 'pen', 'pem'
        };
        if (affixes.contains(p1Lower)) {
          // Strictly protect Indonesian prepositional phrases: "di rumah", "ke rumah", "di mana", "di sini"
          if ((p1Lower == 'di' || p1Lower == 'ke') &&
              ParagraphReconstructor.indonesianPrepositionComplements.contains(p2Lower)) {
            return '$part1 $part2';
          }
          if (p1Lower == 'ke' &&
              !ParagraphReconstructor.indonesianKePrefixComplements.contains(p2Lower)) {
            return '$part1 $part2';
          }
          return '$part1$part2';
        }

        // 5c. Check if known Indonesian coordinate compound or rhyming reduplication
        final compoundKey = '$p1Lower-$p2Lower';
        if (ParagraphReconstructor.indonesianPairedCompounds.contains(compoundKey)) {
          return '$part1-$part2';
        }

        // 5d. Default: generic syllable or word split by line break hyphen: join without hyphen!
        // e.g. "dok- umen" -> "dokumen", "kom- puter" -> "komputer", "sta- bilitas" -> "stabilitas"
        return '$part1$part2';
      },
    );

    // 6. Fix Indonesian passive prefix 'di-' split with space before transitive verbs:
    // e.g. "di tutup" -> "ditutup", "di tendang" -> "ditendang", "di dorong" -> "didorong"
    // CRITICAL: Explicitly verbs only. NEVER matches prepositional complements (di rumah, di mana, di sini).
    s = s.replaceAllMapped(
      RegExp(
        r'\bdi\s+('
        r'tutup|tendang|dorong|buka|baca|tulis|temukan|lakukan|buat|ambil|dengar|'
        r'paksa|belah|tarik|giring|sebut|terima|kirim|lihat|rasakan|hadapi|tunjuk|'
        r'mulai|tambah|kurang|nyatakan|pastikan|kenal|pahami|ketahui|sadari|alami|'
        r'kira|sangka|anggap|duga|ingat|lupa|harapkan|butuhkan|perlukan|'
        r'bentuk|susun|bangun|ubah|ganti|pasang|atur|kelola|rawat|jaga|'
        r'tahan|lepas|tinggal|buang|simpan|taruh|letakkan|jadikan'
        r')\b',
        caseSensitive: false,
      ),
      (m) => 'di${m.group(1)}',
    );

    // 7. Multiple spaces collapsing
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');

    return s.trim();
  }

  ReconstructedParagraph build() {
    if (lines.isEmpty) {
      throw StateError('Cannot build paragraph from empty lines');
    }

    final buffer = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final text = line.text.trim();

      if (i == 0) {
        buffer.write(text);
      } else {
        final prevText = lines[i - 1].text.trim();
        // Cross-line de-hyphenation: check if prevLine ends with a hyphen or dash
        final hyphenMatch =
            RegExp(r'([a-zA-Z]+)[-\u2010\u2013\u2014]$').firstMatch(prevText);
        if (hyphenMatch != null &&
            text.isNotEmpty &&
            RegExp(r'^[a-zA-Z]').hasMatch(text)) {
          final prefixWord = hyphenMatch.group(1)!;
          final nextFirstWordMatch = RegExp(r'^([a-zA-Z]+)').firstMatch(text);
          final nextFirstWord = nextFirstWordMatch?.group(1) ?? '';

          final p1Lower = prefixWord.toLowerCase();
          final p2Lower = nextFirstWord.toLowerCase();

          // Is it an Indonesian reduplication across lines? (e.g. mengira- \n ngira)
          final isRedup = ParagraphReconstructor.isIndonesianReduplication(p1Lower, p2Lower);

          // Is it a known Indonesian paired compound across lines? (e.g. siang- \n malam)
          final isCompound = ParagraphReconstructor.indonesianPairedCompounds.contains('$p1Lower-$p2Lower');

          // Is it an Indonesian preposition complement across lines? (e.g. di- \n rumah)
          final isPrepositionSplit = (p1Lower == 'di' || p1Lower == 'ke') &&
              ParagraphReconstructor.indonesianPrepositionComplements.contains(p2Lower);

          final currentBufferStr = buffer.toString();
          final lastHyphenIdx = currentBufferStr.lastIndexOf(
            RegExp(r'[-\u2010\u2013\u2014]'),
          );
          if (lastHyphenIdx != -1) {
            buffer.clear();
            buffer.write(currentBufferStr.substring(0, lastHyphenIdx));
            if (isRedup || isCompound) {
              buffer.write('-$text');
            } else if (isPrepositionSplit) {
              buffer.write(' $text');
            } else {
              buffer.write(text);
            }
          } else {
            buffer.write(' ');
            buffer.write(text);
          }
        } else {
          buffer.write(' ');
          buffer.write(text);
        }
      }
    }

    // Compute bounding box spanning all lines
    double minLeft = lines.first.bounds.left;
    double minTop = lines.first.bounds.top;
    double maxRight = lines.first.bounds.right;
    double maxBottom = lines.first.bounds.bottom;

    for (final l in lines) {
      minLeft = math.min(minLeft, l.bounds.left);
      minTop = math.min(minTop, l.bounds.top);
      maxRight = math.max(maxRight, l.bounds.right);
      maxBottom = math.max(maxBottom, l.bounds.bottom);
    }

    final firstLine = lines.first;
    final isBold = lines.every((l) => l.isBold);
    final isItalic = lines.every((l) => l.isItalic);
    final fontStyles = firstLine.fontStyle;

    final cleanedText = cleanOcrText(buffer.toString());

    return ReconstructedParagraph(
      text: cleanedText,
      startPageIndex: firstLine.pageIndex,
      endPageIndex: lines.last.pageIndex,
      boundingBox: Rect.fromLTRB(minLeft, minTop, maxRight, maxBottom),
      fontSize: firstLine.fontSize,
      fontStyles: fontStyles,
      isBold: isBold,
      isItalic: isItalic,
      lineCount: lines.length,
      sourceLines: List.unmodifiable(lines),
      isDialogue: RegExp(r'^(["“‘«—\-]|--\s)').hasMatch(cleanedText),
      isIsolated: lines.length == 1,
      isOrderedList: ParagraphReconstructor._orderedListRegex.hasMatch(cleanedText),
      isUnorderedList: ParagraphReconstructor._unorderedListRegex.hasMatch(cleanedText),
      isCopyright: ParagraphReconstructor._copyrightMetaRegex.hasMatch(cleanedText) ||
          RegExp(r'\b(isbn|katalog dalam terbitan|kdt)\b', caseSensitive: false).hasMatch(cleanedText),
      isCaption: ParagraphReconstructor._captionRegex.hasMatch(cleanedText),
    );
  }
}

