import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ReadingFontFamily {
  georgia('Georgia', 'Georgia'),
  palatino('Palatino', 'Palatino'),
  serif('Serif', 'Serif'),
  sansSerif('Sans-Serif', 'Sans-Serif'),
  system('System', 'System');

  final String label;
  final String key;
  const ReadingFontFamily(this.label, this.key);

  TextStyle getTextStyle({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    required double height,
    required double letterSpacing,
  }) {
    switch (this) {
      case ReadingFontFamily.georgia:
        try {
          return GoogleFonts.merriweather(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        } catch (_) {
          return TextStyle(
            fontFamily: 'Georgia',
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        }
      case ReadingFontFamily.palatino:
        try {
          return GoogleFonts.literata(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        } catch (_) {
          return TextStyle(
            fontFamily: 'Palatino',
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        }
      case ReadingFontFamily.serif:
        try {
          return GoogleFonts.notoSerif(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        } catch (_) {
          return TextStyle(
            fontFamily: 'serif',
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        }
      case ReadingFontFamily.sansSerif:
        try {
          return GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        } catch (_) {
          return TextStyle(
            fontFamily: 'sans-serif',
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        }
      case ReadingFontFamily.system:
        return TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          height: height,
          letterSpacing: letterSpacing,
        );
    }
  }
}

class TypographySettings {
  final ReadingFontFamily fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final double lineSpacing;
  final double letterSpacing;
  final TextAlign textAlign;
  final double horizontalMargin;
  final bool twoPageSpread;

  const TypographySettings({
    this.fontFamily = ReadingFontFamily.palatino,
    this.fontSize = 18.0,
    this.fontWeight = FontWeight.normal,
    this.lineSpacing = 1.65,
    this.letterSpacing = 0.2,
    this.textAlign = TextAlign.start,
    this.horizontalMargin = 32.0,
    this.twoPageSpread = true,
  });

  TypographySettings copyWith({
    ReadingFontFamily? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    double? lineSpacing,
    double? letterSpacing,
    TextAlign? textAlign,
    double? horizontalMargin,
    bool? twoPageSpread,
  }) {
    return TypographySettings(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      textAlign: textAlign ?? this.textAlign,
      horizontalMargin: horizontalMargin ?? this.horizontalMargin,
      twoPageSpread: twoPageSpread ?? this.twoPageSpread,
    );
  }
}

