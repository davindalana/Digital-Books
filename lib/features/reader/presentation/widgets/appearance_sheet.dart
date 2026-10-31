import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/typography/typography_settings.dart';
import '../../providers/reader_settings_provider.dart';

class AppearanceSheet extends ConsumerWidget {
  const AppearanceSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(readingThemeStateProvider);
    final typoSettings = ref.watch(typographySettingsStateProvider);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: activeTheme.isDark
                ? const Color(0xFF1E1E20).withAlpha(230)
                : const Color(0xFFF9F9FB).withAlpha(235),
            border: Border(
              top: BorderSide(
                color: activeTheme.isDark
                    ? Colors.white.withAlpha(25)
                    : Colors.black.withAlpha(20),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag Handle
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
                const SizedBox(height: 18),

                // Theme Selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ReadingThemeType.values.map((theme) {
                    final isSelected = theme == activeTheme;
                    return GestureDetector(
                      onTap: () {
                        ref.read(readingThemeStateProvider.notifier).state = theme;
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
                const SizedBox(height: 24),

                // Font Size Controls (A- / A+)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                    .read(typographySettingsStateProvider.notifier)
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
                                  .read(typographySettingsStateProvider.notifier)
                                  .state = typoSettings.copyWith(fontSize: val);
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
                                    .read(typographySettingsStateProvider.notifier)
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
                              .state = typoSettings.copyWith(fontFamily: font);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
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
                                color: (typoSettings.textAlign == TextAlign.left ||
                                        typoSettings.textAlign == TextAlign.start)
                                    ? const Color(0xFF007AFF)
                                    : activeTheme.secondaryTextColor,
                              ),
                              onPressed: () {
                                ref
                                    .read(typographySettingsStateProvider.notifier)
                                    .state = typoSettings.copyWith(
                                  textAlign: TextAlign.left,
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.format_align_justify,
                                color: typoSettings.textAlign == TextAlign.justify
                                    ? const Color(0xFF007AFF)
                                    : activeTheme.secondaryTextColor,
                              ),
                              onPressed: () {
                                ref
                                    .read(typographySettingsStateProvider.notifier)
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
                    // Margin / Line Spacing toggle
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: activeTheme.isDark
                              ? Colors.white.withAlpha(18)
                              : Colors.black.withAlpha(10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Spacing',
                              style: TextStyle(
                                color: activeTheme.textColor,
                                fontSize: 13,
                              ),
                            ),
                            Row(
                              children: [
                                _SpacingButton(
                                  label: '1.4',
                                  isSelected: typoSettings.lineSpacing < 1.5,
                                  onTap: () {
                                    ref
                                        .read(typographySettingsStateProvider.notifier)
                                        .state = typoSettings.copyWith(
                                      lineSpacing: 1.4,
                                    );
                                  },
                                  activeTheme: activeTheme,
                                ),
                                const SizedBox(width: 4),
                                _SpacingButton(
                                  label: '1.7',
                                  isSelected: typoSettings.lineSpacing >= 1.5 &&
                                      typoSettings.lineSpacing < 1.9,
                                  onTap: () {
                                    ref
                                        .read(typographySettingsStateProvider.notifier)
                                        .state = typoSettings.copyWith(
                                      lineSpacing: 1.7,
                                    );
                                  },
                                  activeTheme: activeTheme,
                                ),
                                const SizedBox(width: 4),
                                _SpacingButton(
                                  label: '2.0',
                                  isSelected: typoSettings.lineSpacing >= 1.9,
                                  onTap: () {
                                    ref
                                        .read(typographySettingsStateProvider.notifier)
                                        .state = typoSettings.copyWith(
                                      lineSpacing: 2.0,
                                    );
                                  },
                                  activeTheme: activeTheme,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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

