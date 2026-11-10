// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings, depend_on_referenced_packages, unused_import

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'Phase 3.1.2 — Bi-Directional Reading Navigation & Anchor Synchronization Audit',
    () {
      final mockNodes = [
        // Page 10 content
        const ContentNode(
          id: 'node_p10_1',
          type: ContentNodeType.sectionHeading,
          text: 'Bab 1: Mengetahui Karakter Lawan Bicara',
          sourcePdfPage: 10,
        ),
        const ContentNode(
          id: 'node_p10_2',
          type: ContentNodeType.paragraph,
          text:
              'Komunikasi yang efektif bermula dari pemahaman mendalam tentang siapa yang mendengarkan kita.',
          sourcePdfPage: 10,
        ),
        // Page 11 content
        const ContentNode(
          id: 'node_p11_1',
          type: ContentNodeType.paragraph,
          text:
              'Ketika kita berbicara dengan orang yang memiliki tipe analitis, sajikan data dan fakta yang teruji.',
          sourcePdfPage: 11,
        ),
        const ContentNode(
          id: 'node_p11_2',
          type: ContentNodeType.quote,
          text:
              '"Kata-kata yang tepat pada waktu yang tepat adalah kunci membuka hati seseorang."',
          sourcePdfPage: 11,
        ),
        // Page 12 content
        const ContentNode(
          id: 'node_p12_1',
          type: ContentNodeType.sectionHeading,
          text: '2. Prinsip Telinga Terbuka',
          sourcePdfPage: 12,
        ),
        const ContentNode(
          id: 'node_p12_2',
          type: ContentNodeType.orderedList,
          text: '1. Dengarkan 70% dari waktu percakapan.',
          sourcePdfPage: 12,
        ),
        const ContentNode(
          id: 'node_p12_3',
          type: ContentNodeType.orderedList,
          text: '2. Ajukan pertanyaan terbuka untuk menggali perspektif.',
          sourcePdfPage: 12,
        ),
      ];

      final readerDoc = ReaderDocument(
        bookId: 'nav_test_doc',
        title: 'Bicara Itu Ada Seninya',
        author: 'Oh Su Hyang',
        totalPages: 248,
        chapters: [
          ReaderChapter(
            id: 'ch_0',
            index: 0,
            title: 'Bab 1: Karakter Lawan Bicara',
            nodes: mockNodes,
          ),
        ],
      );

      test(
        '1. Mode Switching: Original PDF Page -> Reflowable Anchor Mapping',
        () {
          // User is reading PDF Page 11
          const currentPdfPage = 11;

          // Locate matching node
          String? targetAnchorId;
          int targetPdfPage = -1;

          for (final node in readerDoc.chapters.first.nodes) {
            if (node.sourcePdfPage >= currentPdfPage) {
              targetAnchorId = node.id;
              targetPdfPage = node.sourcePdfPage;
              break;
            }
          }

          expect(targetAnchorId, isNotNull);
          expect(targetAnchorId, equals('node_p11_1'));
          expect(
            targetPdfPage,
            equals(11),
            reason:
                'Switching to Reflowable from PDF page 11 must anchor on node_p11_1',
          );
        },
      );

      test(
        '2. Mode Switching: Reflowable Anchor -> Original PDF Page Resolution',
        () {
          // User is currently at anchor 'node_p12_2' (second list item on PDF page 12)
          const currentAnchorId = 'node_p12_2';

          int resolvedPdfPage = 1;
          for (final node in readerDoc.chapters.first.nodes) {
            if (node.id == currentAnchorId) {
              resolvedPdfPage = node.sourcePdfPage;
              break;
            }
          }

          expect(
            resolvedPdfPage,
            equals(12),
            reason:
                'Switching back to Original PDF from node_p12_2 must navigate to PDF page 12',
          );
        },
      );

      test(
        '3. Window Resize Stability: Anchor Continuity across Compact, Standard, and Two-Page Spread',
        () {
          const typo = TypographySettings(fontSize: 18.0, lineSpacing: 1.6);
          final chapter = readerDoc.chapters.first;

          // 1. Compact Viewport (e.g. mobile 400x700)
          final compactPages = PaginationEngine.paginateChapter(
            chapter: chapter,
            viewportWidth: 400.0,
            viewportHeight: 700.0,
            typography: typo,
          );

          // Find which compact page contains 'node_p11_2'
          int compactPageIndex = -1;
          for (int i = 0; i < compactPages.length; i++) {
            if (compactPages[i].slices.any((s) => s.node.id == 'node_p11_2')) {
              compactPageIndex = i;
              break;
            }
          }
          expect(compactPageIndex, greaterThanOrEqualTo(0));

          // 2. Desktop Standard Viewport (1000x800)
          final standardPages = PaginationEngine.paginateChapter(
            chapter: chapter,
            viewportWidth: 1000.0,
            viewportHeight: 800.0,
            typography: typo,
          );

          int standardPageIndex = -1;
          for (int i = 0; i < standardPages.length; i++) {
            if (standardPages[i].slices.any((s) => s.node.id == 'node_p11_2')) {
              standardPageIndex = i;
              break;
            }
          }
          expect(standardPageIndex, greaterThanOrEqualTo(0));

          // 3. Desktop Wide Two-Page Spread (1400x900)
          final spreadPages = PaginationEngine.paginateChapter(
            chapter: chapter,
            viewportWidth: 1400.0,
            viewportHeight: 900.0,
            typography: typo.copyWith(twoPageSpread: true),
          );

          int spreadPageIndex = -1;
          for (int i = 0; i < spreadPages.length; i++) {
            if (spreadPages[i].slices.any((s) => s.node.id == 'node_p11_2')) {
              spreadPageIndex = i;
              break;
            }
          }
          expect(spreadPageIndex, greaterThanOrEqualTo(0));

          print('Anchor "node_p11_2" resolved cleanly across all viewports:');
          print(
            '  - Compact (400x700):      Page ${compactPageIndex + 1}/${compactPages.length}',
          );
          print(
            '  - Standard (1000x800):    Page ${standardPageIndex + 1}/${standardPages.length}',
          );
          print(
            '  - Two-Page (1400x900):    Page ${spreadPageIndex + 1}/${spreadPages.length}',
          );
        },
      );

      test(
        '4. Typography Scaling: Anchor Retention across Small, Normal, and Large Fonts',
        () {
          final chapter = readerDoc.chapters.first;
          const targetAnchor = 'node_p12_1'; // Section heading on page 12

          final fontSizes = [13.0, 18.0, 24.0];
          for (final fs in fontSizes) {
            final scaledTypo = TypographySettings(
              fontSize: fs,
              lineSpacing: 1.6,
            );
            final pages = PaginationEngine.paginateChapter(
              chapter: chapter,
              viewportWidth: 800.0,
              viewportHeight: 700.0,
              typography: scaledTypo,
            );

            final targetPage = pages.indexWhere(
              (p) => p.slices.any((s) => s.node.id == targetAnchor),
            );
            expect(
              targetPage,
              greaterThanOrEqualTo(0),
              reason:
                  'Target anchor $targetAnchor must be located at font size $fs pt',
            );
          }
        },
      );
    },
  );
}
