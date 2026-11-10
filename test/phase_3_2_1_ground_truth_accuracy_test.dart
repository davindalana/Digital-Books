// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/models/search_geometry.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 3.2.1 — Search Ground Truth Precision, Recall & F1 Audit', () {
    test('1. Digital Vector PDF Ground Truth Benchmark (30 Queries)', () async {
      final gtFile = File(
        'test/fixtures/search_ground_truth/digital_ground_truth.json',
      );
      expect(gtFile.existsSync(), isTrue);

      final gtJson =
          jsonDecode(gtFile.readAsStringSync()) as Map<String, dynamic>;
      final queries = gtJson['queries'] as List<dynamic>;

      const bookId = 'book_digital_gt';
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(bookId),
          title: const drift.Value('Digital Corpus Novel & Sherlock'),
          author: const drift.Value('Test Author'),
          originalPdfPath: const drift.Value('/dummy/digital.pdf'),
          totalPages: const drift.Value(3),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      // Index pages corresponding to 05_headers_footers.pdf and 01_single_column_novel.pdf
      // Page 1: Chapter 1 Novel + Sherlock Section 1
      final p1Tokens = [
        const SearchTokenGeometry(
          text: 'Chapter',
          start: 0,
          end: 7,
          box: Rect.fromLTWH(0.1, 0.08, 0.1, 0.03),
        ),
        const SearchTokenGeometry(
          text: '1:',
          start: 8,
          end: 10,
          box: Rect.fromLTWH(0.21, 0.08, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'The',
          start: 11,
          end: 14,
          box: Rect.fromLTWH(0.25, 0.08, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Beginning',
          start: 15,
          end: 24,
          box: Rect.fromLTWH(0.31, 0.08, 0.12, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'It',
          start: 25,
          end: 27,
          box: Rect.fromLTWH(0.1, 0.13, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'was',
          start: 28,
          end: 31,
          box: Rect.fromLTWH(0.14, 0.13, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'a',
          start: 32,
          end: 33,
          box: Rect.fromLTWH(0.2, 0.13, 0.02, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'dark',
          start: 34,
          end: 38,
          box: Rect.fromLTWH(0.23, 0.13, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'and',
          start: 39,
          end: 42,
          box: Rect.fromLTWH(0.3, 0.13, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'stormy',
          start: 43,
          end: 49,
          box: Rect.fromLTWH(0.36, 0.13, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'night',
          start: 50,
          end: 55,
          box: Rect.fromLTWH(0.45, 0.13, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'when',
          start: 56,
          end: 60,
          box: Rect.fromLTWH(0.53, 0.13, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 61,
          end: 64,
          box: Rect.fromLTWH(0.6, 0.13, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'messenger',
          start: 65,
          end: 74,
          box: Rect.fromLTWH(0.66, 0.13, 0.12, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'finally',
          start: 75,
          end: 82,
          box: Rect.fromLTWH(0.79, 0.13, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'arrived',
          start: 83,
          end: 90,
          box: Rect.fromLTWH(0.1, 0.17, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'at',
          start: 91,
          end: 93,
          box: Rect.fromLTWH(0.2, 0.17, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 94,
          end: 97,
          box: Rect.fromLTWH(0.24, 0.17, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'gates',
          start: 98,
          end: 103,
          box: Rect.fromLTWH(0.3, 0.17, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'of',
          start: 104,
          end: 106,
          box: Rect.fromLTWH(0.38, 0.17, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 107,
          end: 110,
          box: Rect.fromLTWH(0.42, 0.17, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'ancient',
          start: 111,
          end: 118,
          box: Rect.fromLTWH(0.48, 0.17, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'estate.',
          start: 119,
          end: 126,
          box: Rect.fromLTWH(0.58, 0.17, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'He',
          start: 127,
          end: 129,
          box: Rect.fromLTWH(0.67, 0.17, 0.04, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'carried',
          start: 130,
          end: 137,
          box: Rect.fromLTWH(0.72, 0.17, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'news',
          start: 138,
          end: 142,
          box: Rect.fromLTWH(0.82, 0.17, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'that',
          start: 143,
          end: 147,
          box: Rect.fromLTWH(0.1, 0.21, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'would',
          start: 148,
          end: 153,
          box: Rect.fromLTWH(0.17, 0.21, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'change',
          start: 154,
          end: 160,
          box: Rect.fromLTWH(0.25, 0.21, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 161,
          end: 164,
          box: Rect.fromLTWH(0.34, 0.21, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'destiny',
          start: 165,
          end: 172,
          box: Rect.fromLTWH(0.4, 0.21, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'of',
          start: 173,
          end: 175,
          box: Rect.fromLTWH(0.5, 0.21, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 176,
          end: 179,
          box: Rect.fromLTWH(0.54, 0.21, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'kingdom',
          start: 180,
          end: 187,
          box: Rect.fromLTWH(0.6, 0.21, 0.1, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'forever.',
          start: 188,
          end: 196,
          box: Rect.fromLTWH(0.71, 0.21, 0.1, 0.03),
        ),
        const SearchTokenGeometry(
          text: '"Open',
          start: 197,
          end: 202,
          box: Rect.fromLTWH(0.1, 0.25, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 203,
          end: 206,
          box: Rect.fromLTWH(0.19, 0.25, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'gates!"',
          start: 207,
          end: 214,
          box: Rect.fromLTWH(0.25, 0.25, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'cried',
          start: 215,
          end: 220,
          box: Rect.fromLTWH(0.35, 0.25, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 221,
          end: 224,
          box: Rect.fromLTWH(0.43, 0.25, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'guard',
          start: 225,
          end: 230,
          box: Rect.fromLTWH(0.49, 0.25, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'The',
          start: 231,
          end: 234,
          box: Rect.fromLTWH(0.1, 0.29, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'heavy',
          start: 235,
          end: 240,
          box: Rect.fromLTWH(0.16, 0.29, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'iron',
          start: 241,
          end: 245,
          box: Rect.fromLTWH(0.24, 0.29, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'hinges',
          start: 246,
          end: 252,
          box: Rect.fromLTWH(0.3, 0.29, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'groaned',
          start: 253,
          end: 260,
          box: Rect.fromLTWH(0.39, 0.29, 0.1, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'roaring',
          start: 261,
          end: 268,
          box: Rect.fromLTWH(0.1, 0.33, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'fire',
          start: 269,
          end: 273,
          box: Rect.fromLTWH(0.2, 0.33, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'crackled',
          start: 274,
          end: 282,
          box: Rect.fromLTWH(0.26, 0.33, 0.1, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'stone',
          start: 283,
          end: 288,
          box: Rect.fromLTWH(0.37, 0.33, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'hearth',
          start: 289,
          end: 295,
          box: Rect.fromLTWH(0.45, 0.33, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'dancing',
          start: 296,
          end: 303,
          box: Rect.fromLTWH(0.54, 0.33, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'shadows',
          start: 304,
          end: 311,
          box: Rect.fromLTWH(0.64, 0.33, 0.1, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'examining',
          start: 312,
          end: 321,
          box: Rect.fromLTWH(0.1, 0.37, 0.12, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'an',
          start: 322,
          end: 324,
          box: Rect.fromLTWH(0.23, 0.37, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'old',
          start: 325,
          end: 328,
          box: Rect.fromLTWH(0.27, 0.37, 0.04, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'parchment',
          start: 329,
          end: 338,
          box: Rect.fromLTWH(0.32, 0.37, 0.12, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'map.',
          start: 339,
          end: 343,
          box: Rect.fromLTWH(0.45, 0.37, 0.06, 0.03),
        ),
        // Running Header Chrome
        const SearchTokenGeometry(
          text: 'THE',
          start: 344,
          end: 347,
          box: Rect.fromLTWH(0.1, 0.02, 0.05, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'ADVENTURES',
          start: 348,
          end: 358,
          box: Rect.fromLTWH(0.16, 0.02, 0.15, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'OF',
          start: 359,
          end: 361,
          box: Rect.fromLTWH(0.32, 0.02, 0.04, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'SHERLOCK',
          start: 362,
          end: 370,
          box: Rect.fromLTWH(0.37, 0.02, 0.12, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'HOLMES',
          start: 371,
          end: 377,
          box: Rect.fromLTWH(0.5, 0.02, 0.1, 0.02),
          isChrome: true,
        ),
        // Sherlock Section 1
        const SearchTokenGeometry(
          text: 'Section',
          start: 378,
          end: 385,
          box: Rect.fromLTWH(0.1, 0.42, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: '1:',
          start: 386,
          end: 388,
          box: Rect.fromLTWH(0.2, 0.42, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'The',
          start: 389,
          end: 392,
          box: Rect.fromLTWH(0.24, 0.42, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Investigation',
          start: 393,
          end: 406,
          box: Rect.fromLTWH(0.3, 0.42, 0.16, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Continues',
          start: 407,
          end: 416,
          box: Rect.fromLTWH(0.47, 0.42, 0.12, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Holmes',
          start: 417,
          end: 423,
          box: Rect.fromLTWH(0.1, 0.46, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'took',
          start: 424,
          end: 428,
          box: Rect.fromLTWH(0.19, 0.46, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 429,
          end: 432,
          box: Rect.fromLTWH(0.25, 0.46, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'violin',
          start: 433,
          end: 439,
          box: Rect.fromLTWH(0.31, 0.46, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'from',
          start: 440,
          end: 444,
          box: Rect.fromLTWH(0.39, 0.46, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'its',
          start: 445,
          end: 448,
          box: Rect.fromLTWH(0.45, 0.46, 0.04, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'corner',
          start: 449,
          end: 455,
          box: Rect.fromLTWH(0.5, 0.46, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'and',
          start: 456,
          end: 459,
          box: Rect.fromLTWH(0.59, 0.46, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'began',
          start: 460,
          end: 465,
          box: Rect.fromLTWH(0.65, 0.46, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'to',
          start: 466,
          end: 468,
          box: Rect.fromLTWH(0.73, 0.46, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'play',
          start: 469,
          end: 473,
          box: Rect.fromLTWH(0.77, 0.46, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'a',
          start: 474,
          end: 475,
          box: Rect.fromLTWH(0.83, 0.46, 0.02, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'low,',
          start: 476,
          end: 480,
          box: Rect.fromLTWH(0.1, 0.5, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'melancholy',
          start: 481,
          end: 491,
          box: Rect.fromLTWH(0.16, 0.5, 0.13, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'tune',
          start: 492,
          end: 496,
          box: Rect.fromLTWH(0.3, 0.5, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'as',
          start: 497,
          end: 499,
          box: Rect.fromLTWH(0.37, 0.5, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'he',
          start: 500,
          end: 502,
          box: Rect.fromLTWH(0.41, 0.5, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'pondered',
          start: 503,
          end: 511,
          box: Rect.fromLTWH(0.45, 0.5, 0.11, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 512,
          end: 515,
          box: Rect.fromLTWH(0.57, 0.5, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'case',
          start: 516,
          end: 520,
          box: Rect.fromLTWH(0.63, 0.5, 0.06, 0.03),
        ),
        // Footer Chrome
        const SearchTokenGeometry(
          text: 'Page',
          start: 521,
          end: 525,
          box: Rect.fromLTWH(0.4, 0.96, 0.06, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: '1',
          start: 526,
          end: 527,
          box: Rect.fromLTWH(0.47, 0.96, 0.02, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'of',
          start: 528,
          end: 530,
          box: Rect.fromLTWH(0.5, 0.96, 0.03, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: '3',
          start: 531,
          end: 532,
          box: Rect.fromLTWH(0.54, 0.96, 0.02, 0.02),
          isChrome: true,
        ),
      ];

      final p1Text =
          'Chapter 1: The Beginning It was a dark and stormy night when the messenger finally arrived at the gates of the ancient estate. He carried news that would change the destiny of the kingdom forever. "Open the gates!" cried the guard The heavy iron hinges groaned roaring fire crackled stone hearth dancing shadows examining an old parchment map. THE ADVENTURES OF SHERLOCK HOLMES Section 1: The Investigation Continues Holmes took the violin from its corner and began to play a low, melancholy tune as he pondered the case Page 1 of 3';

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p0'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(0),
          plainText: drift.Value(p1Text),
          rawText: drift.Value(p1Text),
          geometryJson: drift.Value(
            jsonEncode(p1Tokens.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Page 2: Sherlock Section 2
      final p2Tokens = [
        const SearchTokenGeometry(
          text: 'THE',
          start: 0,
          end: 3,
          box: Rect.fromLTWH(0.1, 0.02, 0.05, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'ADVENTURES',
          start: 4,
          end: 14,
          box: Rect.fromLTWH(0.16, 0.02, 0.15, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'OF',
          start: 15,
          end: 17,
          box: Rect.fromLTWH(0.32, 0.02, 0.04, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'SHERLOCK',
          start: 18,
          end: 26,
          box: Rect.fromLTWH(0.37, 0.02, 0.12, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'HOLMES',
          start: 27,
          end: 33,
          box: Rect.fromLTWH(0.5, 0.02, 0.1, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'Section',
          start: 34,
          end: 41,
          box: Rect.fromLTWH(0.1, 0.1, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: '2:',
          start: 42,
          end: 44,
          box: Rect.fromLTWH(0.2, 0.1, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'The',
          start: 45,
          end: 48,
          box: Rect.fromLTWH(0.24, 0.1, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Investigation',
          start: 49,
          end: 62,
          box: Rect.fromLTWH(0.3, 0.1, 0.16, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Continues',
          start: 63,
          end: 72,
          box: Rect.fromLTWH(0.47, 0.1, 0.12, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Holmes',
          start: 73,
          end: 79,
          box: Rect.fromLTWH(0.1, 0.15, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'took',
          start: 80,
          end: 84,
          box: Rect.fromLTWH(0.19, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 85,
          end: 88,
          box: Rect.fromLTWH(0.25, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'violin',
          start: 89,
          end: 95,
          box: Rect.fromLTWH(0.31, 0.15, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'from',
          start: 96,
          end: 100,
          box: Rect.fromLTWH(0.39, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'its',
          start: 101,
          end: 104,
          box: Rect.fromLTWH(0.45, 0.15, 0.04, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'corner',
          start: 105,
          end: 111,
          box: Rect.fromLTWH(0.5, 0.15, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'and',
          start: 112,
          end: 115,
          box: Rect.fromLTWH(0.59, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'began',
          start: 116,
          end: 121,
          box: Rect.fromLTWH(0.65, 0.15, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'to',
          start: 122,
          end: 124,
          box: Rect.fromLTWH(0.73, 0.15, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'play',
          start: 125,
          end: 129,
          box: Rect.fromLTWH(0.77, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'a',
          start: 130,
          end: 131,
          box: Rect.fromLTWH(0.83, 0.15, 0.02, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'low,',
          start: 132,
          end: 136,
          box: Rect.fromLTWH(0.1, 0.2, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'melancholy',
          start: 137,
          end: 147,
          box: Rect.fromLTWH(0.16, 0.2, 0.13, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'tune',
          start: 148,
          end: 152,
          box: Rect.fromLTWH(0.3, 0.2, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'as',
          start: 153,
          end: 155,
          box: Rect.fromLTWH(0.37, 0.2, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'he',
          start: 156,
          end: 158,
          box: Rect.fromLTWH(0.41, 0.2, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'pondered',
          start: 159,
          end: 167,
          box: Rect.fromLTWH(0.45, 0.2, 0.11, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 168,
          end: 171,
          box: Rect.fromLTWH(0.57, 0.2, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'case',
          start: 172,
          end: 176,
          box: Rect.fromLTWH(0.63, 0.2, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Page',
          start: 177,
          end: 181,
          box: Rect.fromLTWH(0.4, 0.96, 0.06, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: '2',
          start: 182,
          end: 183,
          box: Rect.fromLTWH(0.47, 0.96, 0.02, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'of',
          start: 184,
          end: 186,
          box: Rect.fromLTWH(0.5, 0.96, 0.03, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: '3',
          start: 187,
          end: 188,
          box: Rect.fromLTWH(0.54, 0.96, 0.02, 0.02),
          isChrome: true,
        ),
      ];

      final p2Text =
          'THE ADVENTURES OF SHERLOCK HOLMES Section 2: The Investigation Continues Holmes took the violin from its corner and began to play a low, melancholy tune as he pondered the case Page 2 of 3';

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p1'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(1),
          plainText: drift.Value(p2Text),
          rawText: drift.Value(p2Text),
          geometryJson: drift.Value(
            jsonEncode(p2Tokens.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Page 3: Sherlock Section 3
      final p3Tokens = [
        const SearchTokenGeometry(
          text: 'THE',
          start: 0,
          end: 3,
          box: Rect.fromLTWH(0.1, 0.02, 0.05, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'ADVENTURES',
          start: 4,
          end: 14,
          box: Rect.fromLTWH(0.16, 0.02, 0.15, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'OF',
          start: 15,
          end: 17,
          box: Rect.fromLTWH(0.32, 0.02, 0.04, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'SHERLOCK',
          start: 18,
          end: 26,
          box: Rect.fromLTWH(0.37, 0.02, 0.12, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'HOLMES',
          start: 27,
          end: 33,
          box: Rect.fromLTWH(0.5, 0.02, 0.1, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'Section',
          start: 34,
          end: 41,
          box: Rect.fromLTWH(0.1, 0.1, 0.09, 0.03),
        ),
        const SearchTokenGeometry(
          text: '3:',
          start: 42,
          end: 44,
          box: Rect.fromLTWH(0.2, 0.1, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'The',
          start: 45,
          end: 48,
          box: Rect.fromLTWH(0.24, 0.1, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Investigation',
          start: 49,
          end: 62,
          box: Rect.fromLTWH(0.3, 0.1, 0.16, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Continues',
          start: 63,
          end: 72,
          box: Rect.fromLTWH(0.47, 0.1, 0.12, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Holmes',
          start: 73,
          end: 79,
          box: Rect.fromLTWH(0.1, 0.15, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'took',
          start: 80,
          end: 84,
          box: Rect.fromLTWH(0.19, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 85,
          end: 88,
          box: Rect.fromLTWH(0.25, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'violin',
          start: 89,
          end: 95,
          box: Rect.fromLTWH(0.31, 0.15, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'from',
          start: 96,
          end: 100,
          box: Rect.fromLTWH(0.39, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'its',
          start: 101,
          end: 104,
          box: Rect.fromLTWH(0.45, 0.15, 0.04, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'corner',
          start: 105,
          end: 111,
          box: Rect.fromLTWH(0.5, 0.15, 0.08, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'and',
          start: 112,
          end: 115,
          box: Rect.fromLTWH(0.59, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'began',
          start: 116,
          end: 121,
          box: Rect.fromLTWH(0.65, 0.15, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'to',
          start: 122,
          end: 124,
          box: Rect.fromLTWH(0.73, 0.15, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'play',
          start: 125,
          end: 129,
          box: Rect.fromLTWH(0.77, 0.15, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'a',
          start: 130,
          end: 131,
          box: Rect.fromLTWH(0.83, 0.15, 0.02, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'low,',
          start: 132,
          end: 136,
          box: Rect.fromLTWH(0.1, 0.2, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'melancholy',
          start: 137,
          end: 147,
          box: Rect.fromLTWH(0.16, 0.2, 0.13, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'tune',
          start: 148,
          end: 152,
          box: Rect.fromLTWH(0.3, 0.2, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'as',
          start: 153,
          end: 155,
          box: Rect.fromLTWH(0.37, 0.2, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'he',
          start: 156,
          end: 158,
          box: Rect.fromLTWH(0.41, 0.2, 0.03, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'pondered',
          start: 159,
          end: 167,
          box: Rect.fromLTWH(0.45, 0.2, 0.11, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'the',
          start: 168,
          end: 171,
          box: Rect.fromLTWH(0.57, 0.2, 0.05, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'case',
          start: 172,
          end: 176,
          box: Rect.fromLTWH(0.63, 0.2, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'Page',
          start: 177,
          end: 181,
          box: Rect.fromLTWH(0.4, 0.96, 0.06, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: '3',
          start: 182,
          end: 183,
          box: Rect.fromLTWH(0.47, 0.96, 0.02, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: 'of',
          start: 184,
          end: 186,
          box: Rect.fromLTWH(0.5, 0.96, 0.03, 0.02),
          isChrome: true,
        ),
        const SearchTokenGeometry(
          text: '3',
          start: 187,
          end: 188,
          box: Rect.fromLTWH(0.54, 0.96, 0.02, 0.02),
          isChrome: true,
        ),
      ];

      final p3Text =
          'THE ADVENTURES OF SHERLOCK HOLMES Section 3: The Investigation Continues Holmes took the violin from its corner and began to play a low, melancholy tune as he pondered the case Page 3 of 3';

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p2'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(2),
          plainText: drift.Value(p3Text),
          rawText: drift.Value(p3Text),
          geometryJson: drift.Value(
            jsonEncode(p3Tokens.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Execute evaluation against ground truth
      int totalExpected = 0;
      int tp = 0;
      int fp = 0;
      int fn = 0;
      int tn = 0;

      for (final q in queries) {
        final queryStr = q['query'] as String;
        final expectedCount = q['expectedCount'] as int;
        final expectedPages = (q['expectedPages'] as List<dynamic>).cast<int>();
        final shouldBeFiltered = q['shouldBeFiltered'] as bool;

        totalExpected += expectedCount;

        // Perform search: production default filters chrome (includeChrome: false),
        // but if testing chrome header/footers, search with includeChrome: true.
        final results = await InBookSearchEngine.searchIndexedBook(
          bookId: bookId,
          dbService: dbService,
          query: queryStr,
          includeChrome: shouldBeFiltered,
        );

        // If this query targets chrome headers/footers, also verify chrome filter exclusion
        if (shouldBeFiltered) {
          final filteredResults = await InBookSearchEngine.searchIndexedBook(
            bookId: bookId,
            dbService: dbService,
            query: queryStr,
            includeChrome: false,
          );
          expect(
            filteredResults.isEmpty,
            isTrue,
            reason:
                'Chrome query "$queryStr" should be excluded when includeChrome is false',
          );
        }

        if (expectedCount == 0) {
          if (results.isEmpty) {
            tn++;
          } else {
            fp += results.length;
          }
        } else {
          final actualCount = results.length;
          if (actualCount != expectedCount) {
            print(
              '  -> Query "$queryStr": expected $expectedCount, actual $actualCount (${actualCount > expectedCount ? 'FP' : 'FN'})',
            );
          }
          if (actualCount == expectedCount) {
            tp += expectedCount;
          } else if (actualCount < expectedCount) {
            tp += actualCount;
            fn += (expectedCount - actualCount);
          } else {
            tp += expectedCount;
            fp += (actualCount - expectedCount);
          }

          // Verify matched page numbers match expected
          final actualPages = results.map((r) => r.sourcePdfPage).toSet();
          for (final ep in expectedPages) {
            expect(
              actualPages.contains(ep),
              isTrue,
              reason: 'Query "$queryStr" missing expected match on page $ep',
            );
          }
        }
      }

      final precision = (tp + fp) > 0 ? (tp / (tp + fp)) * 100.0 : 100.0;
      final recall = (tp + fn) > 0 ? (tp / (tp + fn)) * 100.0 : 100.0;
      final f1 = (precision + recall) > 0
          ? (2 * precision * recall) / (precision + recall)
          : 100.0;

      print(
        '\n===============================================================',
      );
      print('DIGITAL VECTOR PDF SEARCH GROUND TRUTH AUDIT (30 QUERIES)');
      print('===============================================================');
      print('Total Ground Truth Targets: $totalExpected');
      print('True Positives (TP):        $tp');
      print('False Positives (FP):       $fp');
      print('False Negatives (FN):       $fn');
      print('True Negatives (TN):        $tn');
      print('Precision:                  ${precision.toStringAsFixed(2)}%');
      print('Recall:                     ${recall.toStringAsFixed(2)}%');
      print('F1-Score:                   ${f1.toStringAsFixed(2)}%');
      print(
        '===============================================================\n',
      );

      expect(precision, greaterThanOrEqualTo(98.0));
      expect(recall, greaterThanOrEqualTo(98.0));
      expect(f1, greaterThanOrEqualTo(98.0));
    });

    test('2. Scanned OCR PDF Ground Truth Benchmark (30 Queries)', () async {
      final gtFile = File(
        'test/fixtures/search_ground_truth/scanned_ocr_ground_truth.json',
      );
      expect(gtFile.existsSync(), isTrue);

      final gtJson =
          jsonDecode(gtFile.readAsStringSync()) as Map<String, dynamic>;
      final queries = gtJson['queries'] as List<dynamic>;

      const bookId = 'book_scanned_ocr_gt';
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(bookId),
          title: const drift.Value('Laut Bercerita, Bicara, Suspect X'),
          author: const drift.Value('Various'),
          originalPdfPath: const drift.Value('/dummy/scanned.pdf'),
          totalPages: const drift.Value(35),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      // Page 11: Kesetiaan Mr X Ground Truth
      final p11Text =
          'Yasuko menatap putrinya Misato dengan cemas. Pelanggan toko Benten-tei mulai berdatangan memesan kotak bento. Yasuko tersenyum ramah melayani mereka.';
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p10'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(10), // 1-based page 11
          plainText: drift.Value(p11Text),
          rawText: drift.Value(p11Text),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(true),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Page 15: Laut Bercerita Ground Truth (includes dehyphenation: se- + buah -> sebuah)
      final p15Text =
          'Setelah lebih dari sejam kami berada di atas mobil dengan mata yang masih ditutup dan tangan terikat, akhirnya si Manusia Pohon menarikku keluar mobil dan bersama yang lain menggiringku ke sebuah tempat, udara terbuka. Aku ditendang agar berjalan dengan lekas. Jalan semakin menanjak dan aku mendengar debur ombak yang pecah. Aku bisa mencium aroma asin laut di antara angin yang mengacak rambut. Sekali lagi, suara ombak yang deras itu pecah tak seirama. Di manakah aku? Apakah kami masih di wilayah Jakarta? Karena aku sering berhenti untuk mengira-ngira lokasi, sebuah tangan besar mendorong punggungku agar aku berjalan lebih cepat. Setelah berjalan cukup jauh, kini salah satu dari mereka berteriak agar aku menaiki sebuah speedboat. Bau asin laut kembali menusuk cuping hidungku. Kudengar seseorang menyalakan motor speedboat itu. Seseorang yang lain sekali lagi menendang punggungku agar aku berlutut. Sial! Perlahan aku mencoba duduk dan tampaknya mereka tak keberatan. Begitu saja perahu motor itu melaju. Meski wajahku masih tertutup karung, aku masih bisa merasakan cipratan air laut. Angin laut terasa menyusup di antara pori-pori kain karung yang menyelimuti mukaku yang penuh darah dan luka. Pedih luka bibir dan tulang hidungku yang patah semakin menggigit karena asin air laut, tetapi angin yang menerpa itu terasa seperti sebuah pembebasan. Debar jantung semakin menggedor-gedor dada seolah ia siap mencelat keluar, tetapi aku mencoba menghadapi suara permukaan laut yang dibelah perahu motor itu. Tak terlalu lama, perahu motor terasa melambat.';

      // Page 15 Token Geometries with dehyphenated token boxes
      final p15Tokens = [
        const SearchTokenGeometry(
          text: 'se',
          start: 686,
          end: 688,
          box: Rect.fromLTWH(0.85, 0.4, 0.1, 0.04),
        ),
        const SearchTokenGeometry(
          text: 'buah',
          start: 688,
          end: 692,
          box: Rect.fromLTWH(0.1, 0.44, 0.12, 0.04),
        ),
      ];

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p14'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(14), // 1-based page 15
          plainText: drift.Value(p15Text),
          rawText: drift.Value(p15Text),
          geometryJson: drift.Value(
            jsonEncode(p15Tokens.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(true),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Page 33: Bicara Itu Ada Seninya Ground Truth
      final p33Text =
          'Aristoteles menjelaskan tiga pilar retorika dalam komunikasi efektif: ethos, pathos, logos. Komunikasi bukan sekadar menyampaikan kata, melainkan seni persuasi untuk membangun kepercayaan.';
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p32'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(32), // 1-based page 33
          plainText: drift.Value(p33Text),
          rawText: drift.Value(p33Text),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(true),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Evaluation
      int totalExpected = 0;
      int tp = 0;
      int fp = 0;
      int fn = 0;
      int tn = 0;

      for (final q in queries) {
        final queryStr = q['query'] as String;
        final expectedCount = q['expectedCount'] as int;
        final expectedPages = (q['expectedPages'] as List<dynamic>).cast<int>();

        totalExpected += expectedCount;

        final results = await InBookSearchEngine.searchIndexedBook(
          bookId: bookId,
          dbService: dbService,
          query: queryStr,
        );

        if (expectedCount == 0) {
          if (results.isEmpty) {
            tn++;
          } else {
            fp += results.length;
          }
        } else {
          final actualCount = results.length;
          if (actualCount != expectedCount) {
            print(
              '  -> Query "$queryStr": expected $expectedCount, actual $actualCount (${actualCount > expectedCount ? 'FP' : 'FN'})',
            );
          }
          if (actualCount == expectedCount) {
            tp += expectedCount;
          } else if (actualCount < expectedCount) {
            tp += actualCount;
            fn += (expectedCount - actualCount);
          } else {
            tp += expectedCount;
            fp += (actualCount - expectedCount);
          }

          final actualPages = results.map((r) => r.sourcePdfPage).toSet();
          for (final ep in expectedPages) {
            expect(
              actualPages.contains(ep),
              isTrue,
              reason: 'Query "$queryStr" missing expected match on page $ep',
            );
          }
        }
      }

      final precision = (tp + fp) > 0 ? (tp / (tp + fp)) * 100.0 : 100.0;
      final recall = (tp + fn) > 0 ? (tp / (tp + fn)) * 100.0 : 100.0;
      final f1 = (precision + recall) > 0
          ? (2 * precision * recall) / (precision + recall)
          : 100.0;

      print(
        '\n===============================================================',
      );
      print('SCANNED OCR PDF SEARCH GROUND TRUTH AUDIT (30 QUERIES)');
      print('===============================================================');
      print('Total Ground Truth Targets: $totalExpected');
      print('True Positives (TP):        $tp');
      print('False Positives (FP):       $fp');
      print('False Negatives (FN):       $fn');
      print('True Negatives (TN):        $tn');
      print('Precision:                  ${precision.toStringAsFixed(2)}%');
      print('Recall:                     ${recall.toStringAsFixed(2)}%');
      print('F1-Score:                   ${f1.toStringAsFixed(2)}%');
      print(
        '===============================================================\n',
      );

      expect(precision, greaterThanOrEqualTo(98.0));
      expect(recall, greaterThanOrEqualTo(98.0));
      expect(f1, greaterThanOrEqualTo(98.0));
    });

    test('3. Hybrid Mixed PDF Ground Truth Benchmark (15 Queries)', () async {
      final gtFile = File(
        'test/fixtures/search_ground_truth/hybrid_ground_truth.json',
      );
      expect(gtFile.existsSync(), isTrue);

      final gtJson =
          jsonDecode(gtFile.readAsStringSync()) as Map<String, dynamic>;
      final queries = gtJson['queries'] as List<dynamic>;

      const bookId = 'book_hybrid_gt';
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(bookId),
          title: const drift.Value(
            'Hybrid Mixed Document (09_hybrid_mixed.pdf)',
          ),
          author: const drift.Value('Test Engine'),
          originalPdfPath: const drift.Value(
            'test/fixtures/corpus/09_hybrid_mixed.pdf',
          ),
          totalPages: const drift.Value(3),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      // Page 1: Native Vector Text
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p0'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value(
            'Hybrid Document - Page 1 Native Text This page contains regular vector text.',
          ),
          rawText: const drift.Value(
            'Hybrid Document - Page 1 Native Text\nThis page contains regular vector text.',
          ),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Page 2: Pure Scanned Raster Page (No digital text)
      // Empty before OCR
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p1'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(1),
          plainText: const drift.Value(''),
          rawText: const drift.Value(''),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(true),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Page 3: Mixed (Vector Text + Embedded Chart)
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${bookId}_p2'),
          bookId: const drift.Value(bookId),
          pageIndex: const drift.Value(2),
          plainText: const drift.Value(
            'Page 3: Text and Embedded Chart Caption for the chart above.',
          ),
          rawText: const drift.Value(
            'Page 3: Text and Embedded Chart\nCaption for the chart above.',
          ),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Evaluation
      int totalExpected = 0;
      int tp = 0;
      int fp = 0;
      int fn = 0;
      int tn = 0;

      for (final q in queries) {
        final queryStr = q['query'] as String;
        final expectedCount = q['expectedCount'] as int;
        final expectedPages = (q['expectedPages'] as List<dynamic>).cast<int>();

        totalExpected += expectedCount;

        final results = await InBookSearchEngine.searchIndexedBook(
          bookId: bookId,
          dbService: dbService,
          query: queryStr,
        );

        if (expectedCount == 0) {
          if (results.isEmpty) {
            tn++;
          } else {
            fp += results.length;
          }
        } else {
          final actualCount = results.length;
          if (actualCount != expectedCount) {
            print(
              '  -> Query "$queryStr": expected $expectedCount, actual $actualCount (${actualCount > expectedCount ? 'FP' : 'FN'})',
            );
          }
          if (actualCount == expectedCount) {
            tp += expectedCount;
          } else if (actualCount < expectedCount) {
            tp += actualCount;
            fn += (expectedCount - actualCount);
          } else {
            tp += expectedCount;
            fp += (actualCount - expectedCount);
          }

          final actualPages = results.map((r) => r.sourcePdfPage).toSet();
          for (final ep in expectedPages) {
            expect(
              actualPages.contains(ep),
              isTrue,
              reason: 'Query "$queryStr" missing expected match on page $ep',
            );
          }
        }
      }

      final precision = (tp + fp) > 0 ? (tp / (tp + fp)) * 100.0 : 100.0;
      final recall = (tp + fn) > 0 ? (tp / (tp + fn)) * 100.0 : 100.0;
      final f1 = (precision + recall) > 0
          ? (2 * precision * recall) / (precision + recall)
          : 100.0;

      print(
        '\n===============================================================',
      );
      print('HYBRID MIXED PDF SEARCH GROUND TRUTH AUDIT (15 QUERIES)');
      print('===============================================================');
      print('Total Ground Truth Targets: $totalExpected');
      print('True Positives (TP):        $tp');
      print('False Positives (FP):       $fp');
      print('False Negatives (FN):       $fn');
      print('True Negatives (TN):        $tn');
      print('Precision:                  ${precision.toStringAsFixed(2)}%');
      print('Recall:                     ${recall.toStringAsFixed(2)}%');
      print('F1-Score:                   ${f1.toStringAsFixed(2)}%');
      print(
        '===============================================================\n',
      );

      expect(precision, greaterThanOrEqualTo(98.0));
      expect(recall, greaterThanOrEqualTo(98.0));
      expect(f1, greaterThanOrEqualTo(98.0));
    });
  });
}
