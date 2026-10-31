import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/reading_theme.dart';
import '../../../core/typography/typography_settings.dart';

enum ReadingMode {
  reflowable,
  originalPdf,
}

final readingThemeStateProvider =
    StateProvider<ReadingThemeType>((ref) => ReadingThemeType.black);

final typographySettingsStateProvider =
    StateProvider<TypographySettings>((ref) => const TypographySettings());

final activeReadingModeProvider =
    StateProvider.family<ReadingMode, String>((ref, bookId) => ReadingMode.reflowable);

