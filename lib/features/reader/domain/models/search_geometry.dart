import 'dart:ui' show Rect;

/// Represents the geometric location and character bounds of a single searchable word or token.
class SearchTokenGeometry {
  final String text;
  final int start;
  final int end;
  final Rect box; // Normalized coordinates: left, top, width, height in [0, 1]
  final bool isChrome; // Running header, running footer, or standalone page number

  const SearchTokenGeometry({
    required this.text,
    required this.start,
    required this.end,
    required this.box,
    this.isChrome = false,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'start': start,
        'end': end,
        'box': [box.left, box.top, box.width, box.height],
        'isChrome': isChrome,
      };

  factory SearchTokenGeometry.fromJson(Map<String, dynamic> json) {
    final b = (json['box'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [0.0, 0.0, 0.0, 0.0];
    return SearchTokenGeometry(
      text: json['text'] as String? ?? '',
      start: json['start'] as int? ?? 0,
      end: json['end'] as int? ?? 0,
      box: Rect.fromLTWH(b[0], b[1], b[2], b[3]),
      isChrome: json['isChrome'] as bool? ?? false,
    );
  }
}
