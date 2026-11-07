import '../models/semantic_reconstruction_models.dart';

/// Text after OCR correction and the traceable list of changes that produced it.
class OcrCorrectionResult {
  final String text;
  final List<Map<String, String>> corrections;

  const OcrCorrectionResult({required this.text, required this.corrections});

  bool get changed => corrections.isNotEmpty;
}

/// Applies a small, traceable set of corrections to OCR text.
///
/// This pass deliberately does not try to "improve" prose. It only repairs
/// artefacts that are unambiguous in the scanned edition:
///
/// * isolated `i` characters that Apple Vision emitted around italic passages;
/// * a handful of repeated-letter and single-word OCR errors that were verified
///   against the surrounding sentence.
///
/// Every change is recorded in [SemanticReconstructedBlock.metadata] under
/// `ocrCorrections`, so a reader can audit exactly which words were altered.
/// Rules are intentionally narrow: no dictionary guessing and no rewriting.
class OcrCorrectionPass {
  /// Exact token corrections observed once in the scanned book. Word-boundary
  /// matching prevents these from firing inside longer words (for example the
  /// correct `diungkapkan` must not become `dungkapkan`).
  static const Map<String, String> _tokenCorrections = {
    'iproses': 'proses',
    'imenentukan': 'menentukan',
    'imembentuk': 'membentuk',
    'isitilah': 'istilah',
    'iungkapkan': 'ungkapkan',
    'ijika': 'jika',
    'merekai': 'mereka',
    'diperbaikii': 'diperbaiki',
    'sayaii': 'saya',
    'berbicarai': 'berbicara',
    'beritaii': 'berita',
    'konsumeni': 'konsumen',
    'hebati': 'hebat',
    'terbaiki': 'terbaik',
    'tepati': 'tepat',
    'Weddingi': 'Wedding',
    'Seteve': 'Steve',
    'mengggunakan': 'menggunakan',
    'Kcepatan': 'Kecepatan',
    'yanga': 'yang',
    // Verified against the source scan: a common OCR glyph substitution in
    // the BAB III heading (`I` was recognized as `H`).
    'MEMHAK': 'MEMIHAK',
    // Additional doubled/tripled `i` artefacts verified in the same scan.
    'memujii': 'memuji',
    'dimulaii': 'dimulai',
    'Kompetisii': 'Kompetisi',
    'bumiii': 'bumi',
    // Verified TOC glyph truncation from overlapping dot leaders (p. 13 line 7).
    'Sentuha': 'Sentuhan',
  };

  /// Product names that legitimately start with `i` and must not be treated as
  /// an italic/quote marker.
  static const List<String> _protectedIBrands = [
    'Pod',
    'Phone',
    'Pad',
    'Mac',
    'Tunes',
    'Cloud',
    'Viva',
  ];

  /// Corrects a single text fragment without touching block structure.
  static OcrCorrectionResult correct(String text) {
    if (text.isEmpty) return OcrCorrectionResult(text: text, corrections: const []);

    var result = text;
    final corrections = <Map<String, String>>[];

    void record(String rule, String original, String replacement) {
      corrections.add({
        'rule': rule,
        'original': original,
        'corrected': replacement,
      });
    }

    // 1. Verified exact-token repairs.
    for (final entry in _tokenCorrections.entries) {
      final pattern = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b');
      if (!pattern.hasMatch(result)) continue;
      result = result.replaceAllMapped(pattern, (match) {
        record('token', match.group(0)!, entry.value);
        return entry.value;
      });
    }

    // 2. An `i` marker immediately before a capitalised word after punctuation
    // or whitespace. `pandangan.iAku` -> `pandangan. Aku`, `berkata, iKalau`
    // -> `berkata, Kalau`. Brands such as `iPod` and `iPhone` are skipped.
    final leadingMarker = RegExp(r'(^|[\s,;:!?\.])(i)(?=[A-Z][a-z])');
    result = result.replaceAllMapped(leadingMarker, (match) {
      final prefix = match.group(1)!;
      final following = result.substring(match.end);
      if (_protectedIBrands.any(following.startsWith)) {
        return match.group(0)!;
      }
      final replacement = prefix.trim().isEmpty ? prefix : '$prefix ';
      record('italicMarker', '${prefix}i', replacement);
      return replacement;
    });

    // 3. An `i` marker left after a closing quote or sentence punctuation.
    // `... tidak berbicarai"i` -> `... tidak berbicara"` and `mana?i` ->
    // `mana?`.
    final trailingMarker = RegExp(r'(["”’]|[.!?,;:])(i)(?=\s|$)');
    result = result.replaceAllMapped(trailingMarker, (match) {
      final prefix = match.group(1)!;
      record('italicMarker', '${prefix}i', prefix);
      return prefix;
    });

    return OcrCorrectionResult(
      text: result,
      corrections: List.unmodifiable(corrections),
    );
  }

  /// Applies [correct] to every block and attaches the change log as metadata.
  static List<SemanticReconstructedBlock> apply(
    List<SemanticReconstructedBlock> blocks,
  ) {
    final output = <SemanticReconstructedBlock>[];
    for (final block in blocks) {
      output.add(_correctedBlock(block) ?? block);
    }
    return output;
  }

  static SemanticReconstructedBlock? _correctedBlock(
    SemanticReconstructedBlock block,
  ) {
    if (block.text.trim().isEmpty) return null;
    final result = correct(block.text);
    if (!result.changed) return null;
    return SemanticReconstructedBlock(
      id: block.id,
      type: block.type,
      text: result.text,
      headingLevel: block.headingLevel,
      sourcePageIndex: block.sourcePageIndex,
      sourceBounds: block.sourceBounds,
      image: block.image,
      captionText: block.captionText,
      confidence: block.confidence,
      metadata: {
        ...block.metadata,
        'ocrCorrections': result.corrections,
      },
    );
  }
}
