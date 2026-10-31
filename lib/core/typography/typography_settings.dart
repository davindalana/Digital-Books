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
    FontStyle fontStyle = FontStyle.normal,
  }) {
    if (!GoogleFonts.config.allowRuntimeFetching) {
      String fallbackFamily = 'System';
      switch (this) {
        case ReadingFontFamily.georgia:
          fallbackFamily = 'Georgia';
          break;
        case ReadingFontFamily.palatino:
          fallbackFamily = 'Palatino';
          break;
        case ReadingFontFamily.serif:
          fallbackFamily = 'serif';
          break;
        case ReadingFontFamily.sansSerif:
          fallbackFamily = 'sans-serif';
          break;
        case ReadingFontFamily.system:
          fallbackFamily = 'System';
          break;
      }
      return TextStyle(
        fontFamily: fallbackFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }

    switch (this) {
      case ReadingFontFamily.georgia:
        try {
          return GoogleFonts.merriweather(
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        } catch (_) {
          return TextStyle(
            fontFamily: 'Georgia',
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
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
            fontStyle: fontStyle,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        } catch (_) {
          return TextStyle(
            fontFamily: 'Palatino',
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
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
            fontStyle: fontStyle,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        } catch (_) {
          return TextStyle(
            fontFamily: 'serif',
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
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
            fontStyle: fontStyle,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        } catch (_) {
          return TextStyle(
            fontFamily: 'sans-serif',
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          );
        }
      case ReadingFontFamily.system:
        return TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
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
  final double paragraphSpacing;
  final double letterSpacing;
  final TextAlign textAlign;
  final double horizontalMargin;
  final bool twoPageSpread;

  const TypographySettings({
    this.fontFamily = ReadingFontFamily.palatino,
    this.fontSize = 18.0,
    this.fontWeight = FontWeight.normal,
    this.lineSpacing = 1.65,
    this.paragraphSpacing = 14.0,
    this.letterSpacing = 0.2,
    this.textAlign = TextAlign.justify,
    this.horizontalMargin = 32.0,
    this.twoPageSpread = true,
  });

  TypographySettings copyWith({
    ReadingFontFamily? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    double? lineSpacing,
    double? paragraphSpacing,
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
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      textAlign: textAlign ?? this.textAlign,
      horizontalMargin: horizontalMargin ?? this.horizontalMargin,
      twoPageSpread: twoPageSpread ?? this.twoPageSpread,
    );
  }

  TextStyle bodyStyle({Color? color}) {
    return fontFamily.getTextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? Colors.black87,
      height: lineSpacing,
      letterSpacing: letterSpacing,
    );
  }

  TextStyle headingStyle({int level = 1, Color? color}) {
    final double scale = level == 1 ? 1.45 : (level == 2 ? 1.25 : 1.10);
    return fontFamily.getTextStyle(
      fontSize: fontSize * scale,
      fontWeight: FontWeight.bold,
      color: color ?? Colors.black,
      height: 1.3,
      letterSpacing: letterSpacing * 0.5,
    );
  }

  TextStyle quoteStyle({Color? color}) {
    return fontFamily.getTextStyle(
      fontSize: fontSize * 0.95,
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.italic,
      color: color ?? Colors.black54,
      height: lineSpacing * 1.05,
      letterSpacing: letterSpacing,
    );
  }

  String get cacheKey =>
      '${fontFamily.key}_${fontSize.toStringAsFixed(1)}_${lineSpacing.toStringAsFixed(2)}_${paragraphSpacing.toStringAsFixed(1)}_${letterSpacing.toStringAsFixed(2)}_${textAlign.name}_${horizontalMargin.toStringAsFixed(0)}_${twoPageSpread ? 1 : 0}';
}

