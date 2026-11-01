import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/typography/typography_settings.dart';
import '../../providers/reader_settings_provider.dart';

class AppearanceSheet extends ConsumerWidget {
  final String? bookId;
  final bool isDialog;
  const AppearanceSheet({super.key, this.bookId, this.isDialog = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(readingThemeStateProvider);
    final typoSettings = ref.watch(typographySettingsStateProvider);
    final isPdf = bookId != null
        ? ref.watch(activeReadingModeProvider(bookId!)) ==
            ReadingMode.originalPdf
        : false;

    return ClipRRect(
      borderRadius: isDialog
          ? BorderRadius.circular(16)
          : const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            color: activeTheme.isDark
                ? const Color(0xFF1E1E20).withAlpha(235)
                : const Color(0xFFF9F9FB).withAlpha(240),
            borderRadius: isDialog ? BorderRadius.circular(16) : null,
            border: Border.all(
              color: activeTheme.isDark
                  ? Colors.white.withAlpha(25)
                  : Colors.black.withAlpha(20),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header / Drag Handle
                  if (isDialog)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pengaturan Tampilan',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: activeTheme.textColor,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: activeTheme.secondaryTextColor,
                            size: 18,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          splashRadius: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    )
                  else
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: activeTheme.isDark
                              ? Colors.white.withAlpha(50)
                              : Colors.black.withAlpha(30),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),

                  // Theme Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ReadingThemeType.values.map((theme) {
                      final isSelected = theme == activeTheme;
                      return GestureDetector(
                        onTap: () {
                          ref.read(readingThemeStateProvider.notifier).state =
                              theme;
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.backgroundColor,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF007AFF)
                                  : Colors.grey.withAlpha(100),
                              width: isSelected ? 3 : 1,
                            ),
                            boxShadow: [
                              if (isSelected)
                                BoxShadow(
                                  color: const Color(0xFF007AFF).withAlpha(70),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'A',
                              style: TextStyle(
                                color: theme.textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'serif',
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),

                  // In-App Night Brightness Dimmer
                  Consumer(
                    builder: (context, ref, _) {
                      final dimmer = ref.watch(readerBrightnessDimmerProvider);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: activeTheme.isDark
                              ? Colors.white.withAlpha(18)
                              : Colors.black.withAlpha(10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.brightness_low,
                              size: 18,
                              color: activeTheme.secondaryTextColor,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: const Color(0xFF007AFF),
                                  inactiveTrackColor: activeTheme.isDark
                                      ? Colors.white.withAlpha(40)
                                      : Colors.black.withAlpha(30),
                                  thumbColor: Colors.white,
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                ),
                                child: Slider(
                                  value: (1.0 - dimmer).clamp(0.4, 1.0),
                                  min: 0.4,
                                  max: 1.0,
                                  onChanged: (val) {
                                    ref
                                            .read(
                                              readerBrightnessDimmerProvider
                                                  .notifier,
                                            )
                                            .state =
                                        1.0 - val;
                                  },
                                ),
                              ),
                            ),
                            Icon(
                              Icons.brightness_high,
                              size: 20,
                              color: activeTheme.secondaryTextColor,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Page Layout Selector (Paginated vs Continuous Scroll)
                  Text(
                    'TATA LETAK HALAMAN',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: activeTheme.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Consumer(
                    builder: (context, ref, _) {
                      final pdfViewMode = ref.watch(pdfViewModeProvider);
                      final isPdf = bookId != null
                          ? ref.watch(activeReadingModeProvider(bookId!)) ==
                                ReadingMode.originalPdf
                          : true;
                      final reflowableLayout = bookId != null
                          ? ref.watch(reflowableLayoutModeProvider(bookId!))
                          : ReflowableLayoutMode.paginated;

                      final isPaginated = isPdf
                          ? pdfViewMode == PdfViewMode.paginated
                          : reflowableLayout == ReflowableLayoutMode.paginated;

                      return Container(
                        decoration: BoxDecoration(
                          color: activeTheme.isDark
                              ? Colors.white.withAlpha(18)
                              : Colors.black.withAlpha(10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  if (isPdf) {
                                    ref
                                            .read(pdfViewModeProvider.notifier)
                                            .state =
                                        PdfViewMode.paginated;
                                  } else if (bookId != null) {
                                    ref
                                            .read(
                                              reflowableLayoutModeProvider(
                                                bookId!,
                                              ).notifier,
                                            )
                                            .state =
                                        ReflowableLayoutMode.paginated;
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPaginated
                                        ? const Color(0xFF007AFF)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.view_carousel_outlined,
                                        size: 16,
                                        color: isPaginated
                                            ? Colors.white
                                            : activeTheme.textColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Halaman',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isPaginated
                                                ? Colors.white
                                                : activeTheme.textColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  if (isPdf) {
                                    ref
                                            .read(pdfViewModeProvider.notifier)
                                            .state =
                                        PdfViewMode.continuous;
                                  } else if (bookId != null) {
                                    ref
                                            .read(
                                              reflowableLayoutModeProvider(
                                                bookId!,
                                              ).notifier,
                                            )
                                            .state =
                                        ReflowableLayoutMode.scrolling;
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !isPaginated
                                        ? const Color(0xFF007AFF)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.view_headline_rounded,
                                        size: 16,
                                        color: !isPaginated
                                            ? Colors.white
                                            : activeTheme.textColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Gulir Vertikal',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: !isPaginated
                                                ? Colors.white
                                                : activeTheme.textColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  if (isPdf) ...[
                    // Scanned PDF Enhancement Settings
                    Text(
                      'PENINGKATAN KUALITAS PINDAIAN',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: activeTheme.secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Consumer(
                      builder: (context, ref, _) {
                        if (bookId == null) return const SizedBox.shrink();
                        final config = ref.watch(
                          scanEnhancementConfigProvider(bookId!),
                        );
                        final notifier = ref.read(
                          scanEnhancementConfigProvider(bookId!).notifier,
                        );

                        return Container(
                          decoration: BoxDecoration(
                            color: activeTheme.isDark
                                ? Colors.white.withAlpha(18)
                                : Colors.black.withAlpha(10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile.adaptive(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 2,
                                ),
                                title: Text(
                                  'Tingkatkan Kualitas Pindaian',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: activeTheme.textColor,
                                  ),
                                ),
                                subtitle: Text(
                                  'Mempertajam teks, memutihkan latar kertas, dan meratakan kontras.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: activeTheme.secondaryTextColor,
                                  ),
                                ),
                                value: config.isEnabled,
                                activeTrackColor: const Color(0xFF007AFF),
                                onChanged: (val) {
                                  notifier.state = config.copyWith(
                                    isEnabled: val,
                                  );
                                },
                              ),
                              if (config.isEnabled) ...[
                                const Divider(
                                  height: 1,
                                  indent: 14,
                                  endIndent: 14,
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    12,
                                    14,
                                    6,
                                  ),
                                  child: Text(
                                    'TINGKAT PENINGKATAN',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.1,
                                      color: activeTheme.secondaryTextColor,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children:
                                        ScanEnhancementIntensity.values.map((
                                          intensity,
                                        ) {
                                          final isSelected =
                                              config.intensity == intensity;
                                          return Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 3,
                                                  ),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                onTap: () {
                                                  notifier.state =
                                                      config.copyWith(
                                                        intensity: intensity,
                                                      );
                                                },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? const Color(
                                                            0xFF007AFF,
                                                          )
                                                        : (activeTheme.isDark
                                                                ? Colors.white
                                                                : Colors.black)
                                                            .withAlpha(12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    intensity.label,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isSelected
                                                          ? Colors.white
                                                          : activeTheme
                                                              .textColor,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SwitchListTile.adaptive(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  title: Text(
                                    'Reduksi Bayangan Lipatan (Gutter)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: activeTheme.textColor,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Meringankan bayangan gelap di area punggung buku.',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: activeTheme.secondaryTextColor,
                                    ),
                                  ),
                                  value: config.removeGutterShadow,
                                  activeTrackColor: const Color(0xFF007AFF),
                                  onChanged: (val) {
                                    notifier.state = config.copyWith(
                                      removeGutterShadow: val,
                                    );
                                  },
                                ),
                                SwitchListTile.adaptive(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  title: Text(
                                    'Mode Hitam Putih (Grayscale)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: activeTheme.textColor,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Mengubah halaman ke hitam putih untuk kontras maksimal.',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: activeTheme.secondaryTextColor,
                                    ),
                                  ),
                                  value: config.toGrayscale,
                                  activeTrackColor: const Color(0xFF007AFF),
                                  onChanged: (val) {
                                    notifier.state = config.copyWith(
                                      toGrayscale: val,
                                    );
                                  },
                                ),
                                const SizedBox(height: 6),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: activeTheme.isDark
                            ? Colors.white.withAlpha(12)
                            : Colors.black.withAlpha(8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: activeTheme.secondaryTextColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Pengaturan ukuran font dan tipografi teks berlaku dalam mode Buku (Reflowable).',
                              style: TextStyle(
                                fontSize: 12,
                                color: activeTheme.secondaryTextColor,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Font Size Controls (A- / A+)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: activeTheme.isDark
                            ? Colors.white.withAlpha(18)
                            : Colors.black.withAlpha(10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Text(
                            'A',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: activeTheme.textColor,
                            ),
                          ),
                          onPressed: typoSettings.fontSize > 13
                              ? () {
                                  ref
                                      .read(
                                        typographySettingsStateProvider
                                            .notifier,
                                      )
                                      .state = typoSettings.copyWith(
                                    fontSize: typoSettings.fontSize - 1.5,
                                  );
                                }
                              : null,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: const Color(0xFF007AFF),
                              inactiveTrackColor: activeTheme.isDark
                                  ? Colors.white.withAlpha(40)
                                  : Colors.black.withAlpha(30),
                              thumbColor: Colors.white,
                              trackHeight: 3,
                            ),
                            child: Slider(
                              value: typoSettings.fontSize,
                              min: 12.0,
                              max: 32.0,
                              divisions: 10,
                              onChanged: (val) {
                                ref
                                    .read(
                                      typographySettingsStateProvider.notifier,
                                    )
                                    .state = typoSettings.copyWith(
                                  fontSize: val,
                                );
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Text(
                            'A',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: activeTheme.textColor,
                            ),
                          ),
                          onPressed: typoSettings.fontSize < 30
                              ? () {
                                  ref
                                      .read(
                                        typographySettingsStateProvider
                                            .notifier,
                                      )
                                      .state = typoSettings.copyWith(
                                    fontSize: typoSettings.fontSize + 1.5,
                                  );
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Font Family Selector
                  Text(
                    'FONT',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: activeTheme.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: activeTheme.isDark
                          ? Colors.white.withAlpha(18)
                          : Colors.black.withAlpha(10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: ReadingFontFamily.values.map((font) {
                        final isSelected = typoSettings.fontFamily == font;
                        return InkWell(
                          onTap: () {
                            ref
                                .read(typographySettingsStateProvider.notifier)
                                .state = typoSettings.copyWith(
                              fontFamily: font,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  font.label,
                                  style: font.getTextStyle(
                                    fontSize: 16,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: activeTheme.textColor,
                                    height: 1.2,
                                    letterSpacing: 0,
                                  ),
                                ),
                                const Spacer(),
                                if (isSelected)
                                  const Icon(
                                    Icons.check,
                                    color: Color(0xFF007AFF),
                                    size: 18,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Line Height & Alignment Controls
                  Row(
                    children: [
                      // Text Alignment
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: activeTheme.isDark
                                ? Colors.white.withAlpha(18)
                                : Colors.black.withAlpha(10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.format_align_left,
                                  color:
                                      (typoSettings.textAlign ==
                                              TextAlign.left ||
                                          typoSettings.textAlign ==
                                              TextAlign.start)
                                      ? const Color(0xFF007AFF)
                                      : activeTheme.secondaryTextColor,
                                ),
                                onPressed: () {
                                  ref
                                      .read(
                                        typographySettingsStateProvider
                                            .notifier,
                                      )
                                      .state = typoSettings.copyWith(
                                    textAlign: TextAlign.left,
                                  );
                                },
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.format_align_justify,
                                  color:
                                      typoSettings.textAlign ==
                                          TextAlign.justify
                                      ? const Color(0xFF007AFF)
                                      : activeTheme.secondaryTextColor,
                                ),
                                onPressed: () {
                                  ref
                                      .read(
                                        typographySettingsStateProvider
                                            .notifier,
                                      )
                                      .state = typoSettings.copyWith(
                                    textAlign: TextAlign.justify,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Line Spacing toggle
                      Expanded(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: activeTheme.isDark
                                ? Colors.white.withAlpha(18)
                                : Colors.black.withAlpha(10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _SpacingButton(
                                label: '1.4',
                                isSelected: typoSettings.lineSpacing < 1.5,
                                onTap: () {
                                  ref
                                      .read(
                                        typographySettingsStateProvider
                                            .notifier,
                                      )
                                      .state = typoSettings.copyWith(
                                    lineSpacing: 1.4,
                                  );
                                },
                                activeTheme: activeTheme,
                              ),
                              _SpacingButton(
                                label: '1.7',
                                isSelected:
                                    typoSettings.lineSpacing >= 1.5 &&
                                    typoSettings.lineSpacing < 1.9,
                                onTap: () {
                                  ref
                                      .read(
                                        typographySettingsStateProvider
                                            .notifier,
                                      )
                                      .state = typoSettings.copyWith(
                                    lineSpacing: 1.7,
                                  );
                                },
                                activeTheme: activeTheme,
                              ),
                              _SpacingButton(
                                label: '2.0',
                                isSelected: typoSettings.lineSpacing >= 1.9,
                                onTap: () {
                                  ref
                                      .read(
                                        typographySettingsStateProvider
                                            .notifier,
                                      )
                                      .state = typoSettings.copyWith(
                                    lineSpacing: 2.0,
                                  );
                                },
                                activeTheme: activeTheme,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpacingButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ReadingThemeType activeTheme;

  const _SpacingButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.activeTheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF007AFF)
              : (activeTheme.isDark
                    ? Colors.white.withAlpha(25)
                    : Colors.black.withAlpha(15)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : activeTheme.textColor,
          ),
        ),
      ),
    );
  }
}
