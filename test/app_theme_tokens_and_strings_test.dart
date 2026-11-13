import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/app_theme_tokens.dart';
import 'package:digital_books/core/constants/app_strings.dart';

void main() {
  group('Phase 1 — Design Tokens and Centralized Strings Verification', () {
    test(
      'AppThemeTokens spacing and radius scales conform to design system',
      () {
        expect(AppThemeTokens.space4, equals(4.0));
        expect(AppThemeTokens.space8, equals(8.0));
        expect(AppThemeTokens.space12, equals(12.0));
        expect(AppThemeTokens.space16, equals(16.0));
        expect(AppThemeTokens.space24, equals(24.0));
        expect(AppThemeTokens.space32, equals(32.0));

        expect(AppThemeTokens.radius10, equals(10.0));
        expect(AppThemeTokens.radius14, equals(14.0));
        expect(AppThemeTokens.radius20, equals(20.0));
      },
    );

    test('AppThemeTokens responsive breakpoints and layout specifications', () {
      expect(AppThemeTokens.breakpointExpansive, equals(1100.0));
      expect(AppThemeTokens.breakpointStandard, equals(760.0));

      expect(AppThemeTokens.sidebarExpansiveWidth, equals(240.0));
      expect(AppThemeTokens.sidebarStandardWidth, equals(200.0));
      expect(AppThemeTokens.sidebarCompactWidth, equals(64.0));
      expect(AppThemeTokens.contentMaxWidth, equals(1200.0));

      expect(AppThemeTokens.titlebarHeight, equals(52.0));
      expect(AppThemeTokens.trafficLightAreaWidth, equals(80.0));
      expect(AppThemeTokens.minInteractiveTarget, equals(28.0));
    });

    test('AppStrings contains consistent UX terminology', () {
      expect(AppStrings.navSedangDibaca, equals('Currently Reading'));
      expect(AppStrings.navSemuaBuku, equals('All Books'));
      expect(AppStrings.navSelesai, equals('Finished'));
      expect(AppStrings.navKoleksi, equals('Collections'));
      expect(AppStrings.navPenanda, equals('Bookmarks'));
      expect(AppStrings.navSorotanCatatan, equals('Highlights & Notes'));
      expect(AppStrings.navPengaturan, equals('Settings'));

      expect(AppStrings.actionTambahBuku, equals('Add Book'));
      expect(AppStrings.actionLanjutkan, equals('Continue Reading'));
      expect(AppStrings.unknownAuthor, equals('Unknown Author'));
      expect(AppStrings.badgeHasilPindai, equals('Scanned'));
      expect(AppStrings.readerModeTeks, equals('Book'));
      expect(AppStrings.readerModePdfAsli, equals('PDF'));
    });
  });
}
