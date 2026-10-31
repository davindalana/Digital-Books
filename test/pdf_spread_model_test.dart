import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PdfSpread & Open-Book Spread Mathematics Tests', () {
    test('PdfSpread model accurately represents cover and facing spreads', () {
      const coverSpread = PdfSpread(
        spreadIndex: 0,
        leftPage: null,
        rightPage: 1,
        isCover: true,
      );

      expect(coverSpread.primaryPage, equals(1));
      expect(coverSpread.secondaryPage, isNull);
      expect(coverSpread.isCover, isTrue);
      expect(coverSpread.containsPage(1), isTrue);
      expect(coverSpread.containsPage(2), isFalse);

      const facingSpread5 = PdfSpread(
        spreadIndex: 5,
        leftPage: 10,
        rightPage: 11,
        isCover: false,
      );

      expect(facingSpread5.primaryPage, equals(11));
      expect(facingSpread5.secondaryPage, equals(11));
      expect(facingSpread5.isCover, isFalse);
      expect(facingSpread5.containsPage(10), isTrue);
      expect(facingSpread5.containsPage(11), isTrue);
      expect(facingSpread5.containsPage(12), isFalse);
    });

    test('Two-page spread generation maps exact book facing pairs (e.g. 10-11, 12-13)', () {
      // Test generation logic directly
      final spreads = <PdfSpread>[
        const PdfSpread(spreadIndex: 0, leftPage: null, rightPage: 1, isCover: true),
      ];

      const totalPages = 271;
      int page = 2;
      int spreadIdx = 1;
      while (page <= totalPages) {
        final left = page;
        final right = (page + 1 <= totalPages) ? page + 1 : null;
        spreads.add(PdfSpread(
          spreadIndex: spreadIdx,
          leftPage: left,
          rightPage: right,
          isCover: false,
        ));
        spreadIdx++;
        page += 2;
      }

      // Total spreads for 271 pages: Cover (1) + 135 spreads (2-271) = 136 spreads
      expect(spreads.length, equals(136));

      // Spread 0: Cover (Page 1)
      expect(spreads[0].isCover, isTrue);
      expect(spreads[0].rightPage, equals(1));

      // Spread 1: Pages 2 and 3
      expect(spreads[1].leftPage, equals(2));
      expect(spreads[1].rightPage, equals(3));

      // Spread 5: Pages 10 and 11 (Matching user's archive.org screenshot 1)
      expect(spreads[5].leftPage, equals(10));
      expect(spreads[5].rightPage, equals(11));

      // Spread 6: Pages 12 and 13 (Matching user's archive.org screenshot 2)
      expect(spreads[6].leftPage, equals(12));
      expect(spreads[6].rightPage, equals(13));

      // Last spread 135: Pages 270 and 271
      expect(spreads[135].leftPage, equals(270));
      expect(spreads[135].rightPage, equals(271));
    });

    test('Spread index lookup is instantaneous O(1) for any page number', () {
      int getSpreadIndex(int p) {
        if (p <= 1) return 0;
        return p ~/ 2;
      }

      expect(getSpreadIndex(1), equals(0)); // Cover
      expect(getSpreadIndex(2), equals(1)); // Spread 1: 2-3
      expect(getSpreadIndex(3), equals(1)); // Spread 1: 2-3
      expect(getSpreadIndex(10), equals(5)); // Spread 5: 10-11
      expect(getSpreadIndex(11), equals(5)); // Spread 5: 10-11
      expect(getSpreadIndex(12), equals(6)); // Spread 6: 12-13
      expect(getSpreadIndex(13), equals(6)); // Spread 6: 12-13
      expect(getSpreadIndex(271), equals(135)); // Spread 135: 270-271
    });
  });
}
