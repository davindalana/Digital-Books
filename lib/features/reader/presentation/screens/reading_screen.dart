import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/utils/file_storage_service.dart';
import '../../models/book_document.dart';
import '../../services/book_text_normalizer.dart';
import '../../domain/engines/in_book_search_engine.dart';
import '../../domain/engines/reflowable_engine.dart';
import '../../domain/engines/reflowable_highlight_span_builder.dart';
import '../../domain/models/book_annotation.dart';
import '../../domain/models/reader_content.dart';
import '../../domain/models/reading_navigation_history.dart';
import '../../domain/services/anchor_resolution_service.dart';
import '../../providers/reader_settings_provider.dart';
import '../widgets/annotations_sheet.dart';
import '../widgets/appearance_sheet.dart';
import '../widgets/book_search_dialog.dart';
import '../widgets/original_pdf_reader.dart';
import '../widgets/reflowable/highlight_interaction_sheet.dart';
import '../widgets/reflowable/reflowable_reader_container.dart';
import '../widgets/search_traversal_bar.dart';
import '../widgets/toc_dialog.dart';
import '../../../processing/models/ocr_queue_state.dart';
import '../../../processing/providers/background_ocr_provider.dart';

class ReadingScreen extends ConsumerStatefulWidget {
  final Book book;
  final ReadingMode? initialMode;
  final int? initialPage;
  final String? initialAnchorNodeId;
  final int initialCharOffset;

  const ReadingScreen({
    super.key,
    required this.book,
    this.initialMode,
    this.initialPage,
    this.initialAnchorNodeId,
    this.initialCharOffset = 0,
  });

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen>
    with WidgetsBindingObserver {
  bool _showControls = true;
  BookDocument? _document;
  ReaderDocument? _readerDocument;
  bool _isLoadingDoc = true;

  late String _currentPdfPath;
  late ReadingMode _readingMode;
  int _currentPage = 1;
  int _totalPages = 1;
  int _currentChapter = 0;
  int _pdfPage = 1;
  int _reflowableChapter = 0;
  int _reflowablePosition = 0;
  String? _activeAnchorNodeId;
  int _activeCharOffset = 0;
  double _progressPercentage = 0.0;
  double? _sliderDragValue;
  String _currentChapterTitle = '';
  int _estimatedMinutesLeftInChapter = 0;
  StreamSubscription<OcrQueueProgress>? _ocrProgressSub;

  late final ReadingNavigationHistory _navigationHistory;
  List<ActiveSearchMatch> _activeSearchMatches = [];
  Map<int, List<Rect>> _activePdfSearchHighlights = {};
  List<InBookSearchResult> _searchResults = [];
  int _currentSearchMatchIndex = 0;
  String _activeSearchQuery = '';
  bool _showSearchTraversal = false;
  bool _dismissedQualityBanner = false;
  Timer? _periodicProgressTimer;
  Timer? _autoHideTimer;

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && _showControls) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _cancelAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  void _onUserPointerInteraction() {
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _startAutoHideTimer();
  }

  final GlobalKey<ReflowableReaderContainerState> _reflowableKey =
      GlobalKey<ReflowableReaderContainerState>();
  final GlobalKey<OriginalPdfReaderState> _pdfKey =
      GlobalKey<OriginalPdfReaderState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navigationHistory = ReadingNavigationHistory(bookId: widget.book.id);
    _currentPdfPath = widget.book.originalPdfPath;
    final currentProviderMode = ref.read(
      activeReadingModeProvider(widget.book.id),
    );
    _readingMode =
        widget.initialMode ??
        (widget.book.isScanned ? ReadingMode.originalPdf : currentProviderMode);

    if (widget.initialAnchorNodeId != null) {
      _activeAnchorNodeId = widget.initialAnchorNodeId;
      _activeCharOffset = widget.initialCharOffset;
    }

    _loadBookDocumentAndProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(activeReadingModeProvider(widget.book.id).notifier).state =
            _readingMode;
      }
    });

    // Periodic auto-save timer ensures progress is continuously durable
    // even during sudden crashes or power loss without page-turn events.
    _periodicProgressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _saveProgress(
          chapter: _reflowableChapter,
          position: _readingMode == ReadingMode.originalPdf
              ? _pdfPage
              : _reflowablePosition,
          percentage: _progressPercentage,
        );
      }
    });
    _startAutoHideTimer();

    _ocrProgressSub = ref.read(backgroundOcrQueueProvider).progressStream.listen((
      p,
    ) {
      if (p.bookId == widget.book.id && p.status == OcrQueueStatus.completed) {
        _loadProcessedDoc();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pengenalan teks (OCR) selesai. Mode Buku (Reflowable) kini tersedia!',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _ocrProgressSub?.cancel();
    _cancelAutoHideTimer();
    _periodicProgressTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress(
      chapter: _reflowableChapter,
      position: _readingMode == ReadingMode.originalPdf
          ? _pdfPage
          : _reflowablePosition,
      percentage: _progressPercentage,
    );
    _activeSearchMatches.clear();
    _showSearchTraversal = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveProgress(
        chapter: _reflowableChapter,
        position: _readingMode == ReadingMode.originalPdf
            ? _pdfPage
            : _reflowablePosition,
        percentage: _progressPercentage,
      );
    }
  }

  void _setReadingMode(ReadingMode mode) {
    if (_readingMode == mode) return;

    if (mode == ReadingMode.originalPdf) {
      // Switching from Reflowable to Original PDF:
      // Map active reflowable anchor node to its source PDF page
      int targetPdfPage = _pdfPage;
      if (_showSearchTraversal &&
          _searchResults.isNotEmpty &&
          _currentSearchMatchIndex < _searchResults.length) {
        final match = _searchResults[_currentSearchMatchIndex];
        targetPdfPage = match.sourcePdfPage;
        if (match.boundingBoxes.isNotEmpty) {
          _activePdfSearchHighlights = {
            match.sourcePdfPage: match.boundingBoxes,
          };
        }
      } else if (_readerDocument != null) {
        final currentAnchorId =
            _activeAnchorNodeId ??
            _reflowableKey.currentState?.activeAnchorNodeId;
        if (currentAnchorId != null) {
          for (final ch in _readerDocument!.chapters) {
            for (final node in ch.nodes) {
              if (node.id == currentAnchorId && node.sourcePdfPage > 0) {
                targetPdfPage = node.sourcePdfPage;
                break;
              }
            }
          }
        }
      }

      setState(() {
        _readingMode = mode;
        _pdfPage = targetPdfPage;
        _totalPages = widget.book.totalPages > 0 ? widget.book.totalPages : 1;
        _currentPage = _pdfPage;
      });
    } else {
      // Switching from Original PDF to Reflowable:
      // Map current PDF page to first matching node in Reflowable reader
      String? targetAnchorId;
      int targetChapter = _reflowableChapter;
      int targetCharOffset = 0;

      if (_showSearchTraversal &&
          _searchResults.isNotEmpty &&
          _currentSearchMatchIndex < _searchResults.length) {
        final match = _searchResults[_currentSearchMatchIndex];
        targetAnchorId = match.nodeId;
        targetChapter = match.chapterIndex;
        targetCharOffset = match.startOffset;
      } else if (_readerDocument != null &&
          _readerDocument!.chapters.isNotEmpty) {
        for (int chIdx = 0; chIdx < _readerDocument!.chapters.length; chIdx++) {
          final ch = _readerDocument!.chapters[chIdx];
          for (final node in ch.nodes) {
            if (node.sourcePdfPage >= _pdfPage) {
              targetAnchorId = node.id;
              targetChapter = chIdx;
              break;
            }
          }
          if (targetAnchorId != null) break;
        }

        if (targetAnchorId == null) {
          // Fallback to last node if past end
          final lastChapter = _readerDocument!.chapters.last;
          if (lastChapter.nodes.isNotEmpty) {
            targetAnchorId = lastChapter.nodes.last.id;
            targetChapter = _readerDocument!.chapters.length - 1;
          }
        }
      }

      setState(() {
        _readingMode = mode;
        if (targetAnchorId != null) {
          _activeAnchorNodeId = targetAnchorId;
          _reflowableChapter = targetChapter;
          _currentChapter = targetChapter;
        }
        final reflowableTotal = _reflowableKey.currentState?.totalPages;
        if (reflowableTotal != null && reflowableTotal > 0) {
          _totalPages = reflowableTotal;
        }
        _currentChapter = _reflowableChapter;
        _currentPage = _reflowablePosition;
      });

      if (targetAnchorId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _reflowableKey.currentState?.jumpToAnchor(
              targetAnchorId!,
              targetCharOffset,
            );
          }
        });
      }
    }

    ref.read(activeReadingModeProvider(widget.book.id).notifier).state = mode;
    _saveProgress(
      chapter: _reflowableChapter,
      position: mode == ReadingMode.originalPdf
          ? _pdfPage
          : _reflowablePosition,
      percentage: _progressPercentage,
    );
  }

  Future<void> _loadBookDocumentAndProgress() async {
    // 1. Load progress
    try {
      final dbService = ref.read(databaseServiceProvider);
      final progress = await dbService.getProgress(widget.book.id);
      if (mounted) {
        setState(() {
          if (progress != null) {
            _currentChapter = progress.currentChapter;
            _reflowableChapter = progress.currentChapter;
            _progressPercentage = progress.progressPercentage;
            if (widget.initialMode == null &&
                progress.lastReadingMode != null) {
              if (progress.lastReadingMode == 'reflowable_scrolling' ||
                  progress.lastReadingMode == 'reflowable_paginated') {
                // Book Mode is always paginated — ignore any saved scrolling preference.
                _readingMode = ReadingMode.reflowable;
              } else {
                final restoredMode = ReadingMode.values
                    .where((m) => m.name == progress.lastReadingMode)
                    .firstOrNull;
                if (restoredMode != null) {
                  _readingMode = restoredMode;
                }
              }
              ref
                      .read(activeReadingModeProvider(widget.book.id).notifier)
                      .state =
                  _readingMode;
            }
            if (_readingMode == ReadingMode.originalPdf) {
              _pdfPage = progress.currentPosition > 0
                  ? progress.currentPosition
                  : 1;
              _currentPage = _pdfPage;
            } else {
              _reflowablePosition = progress.currentPosition > 0
                  ? progress.currentPosition
                  : 0;
              _currentPage = _reflowablePosition;
            }
          }
          if (widget.initialPage != null && widget.initialPage! > 0) {
            _currentPage = widget.initialPage!;
            if (_readingMode == ReadingMode.originalPdf) {
              _pdfPage = widget.initialPage!;
            } else {
              _reflowablePosition = widget.initialPage!;
            }
          }
        });
      }
    } catch (_) {}

    // 2. Load processed book document if available
    if (widget.book.processedBookPath != null) {
      try {
        final jsonStr = await FileStorageService.readProcessedBook(
          widget.book.processedBookPath!,
        );
        if (jsonStr != null) {
          final loadedDoc = BookDocument.fromJsonString(jsonStr);
          _document = loadedDoc.metadata.containsKey('reconstructionQuality')
              ? loadedDoc
              : BookTextNormalizer.normalizeDocument(loadedDoc);
          _readerDocument = ReflowableEngine.normalizeDocument(_document!);
          if (_currentChapter < _document!.chapters.length) {
            _currentChapterTitle = _document!.chapters[_currentChapter].title;
          }
        }
      } catch (_) {}
    }
    await _loadProcessedDoc();

    if (mounted) {
      setState(() {
        _isLoadingDoc = false;
        _totalPages = widget.book.totalPages > 0 ? widget.book.totalPages : 1;
      });
    }
  }

  Future<void> _loadProcessedDoc([String? explicitPath]) async {
    String? path = explicitPath ?? widget.book.processedBookPath;
    if (path == null) {
      final dbBook = await ref
          .read(databaseServiceProvider)
          .getBookById(widget.book.id);
      path = dbBook?.processedBookPath;
    }
    if (path != null) {
      try {
        final jsonStr = await FileStorageService.readProcessedBook(path);
        if (jsonStr != null && mounted) {
          final loadedDoc = BookDocument.fromJsonString(jsonStr);
          setState(() {
            _document = loadedDoc.metadata.containsKey('reconstructionQuality')
                ? loadedDoc
                : BookTextNormalizer.normalizeDocument(loadedDoc);
            _readerDocument = ReflowableEngine.normalizeDocument(_document!);
            if (_currentChapter < _document!.chapters.length) {
              _currentChapterTitle = _document!.chapters[_currentChapter].title;
            }
          });
        }
      } catch (_) {}
    }
  }

  void _handleHighlightCreated(
    String text,
    String color,
    int pageNumber,
  ) async {
    final highlight = HighlightsCompanion(
      id: drift.Value(const Uuid().v4()),
      bookId: drift.Value(widget.book.id),
      chapterId: drift.Value(_currentChapter.toString()),
      selectedText: drift.Value(text),
      startPosition: drift.Value(pageNumber),
      endPosition: drift.Value(pageNumber),
      color: drift.Value(color),
      createdAt: drift.Value(DateTime.now()),
    );
    await ref.read(databaseServiceProvider).addHighlight(highlight);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.bookmark_added_rounded,
                color: color == 'gold'
                    ? const Color(0xFFD4AF37)
                    : Colors.amberAccent,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Teks berhasil disorot & disimpan ke Catatan'),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _updateChapterInfo(int chapterIndex) {
    if (_document == null || _document!.chapters.isEmpty) return;
    final clampedIdx = chapterIndex.clamp(0, _document!.chapters.length - 1);
    final ch = _document!.chapters[clampedIdx];
    final totalWords = ch.blocks
        .where((b) => b.type == BlockType.paragraph)
        .map((b) => b.text.split(RegExp(r'\s+')).length)
        .fold(0, (a, b) => a + b);
    final estMins = (totalWords / 200).ceil();

    if (_currentChapterTitle != ch.title ||
        _estimatedMinutesLeftInChapter != estMins) {
      setState(() {
        _currentChapter = clampedIdx;
        _currentChapterTitle = ch.title;
        _estimatedMinutesLeftInChapter = estMins > 0 ? estMins : 1;
      });
    }
  }

  void _openAnnotationsSheet() async {
    final dbService = ref.read(databaseServiceProvider);
    final rawAnnotations = await dbService.getAnnotationsForBook(
      widget.book.id,
    );

    // Resolve anchors using AnchorResolutionService against current document
    final resolvedAnnotations = rawAnnotations.map((ann) {
      if (_readerDocument != null) {
        return AnchorResolutionService.resolveInReflowableDocument(
          annotation: ann,
          document: _readerDocument!,
        );
      }
      return ann;
    }).toList();

    if (!mounted) return;

    AnnotationsSheet.show(
      context: context,
      bookTitle: widget.book.title,
      annotations: resolvedAnnotations,
      theme: ref.read(readingThemeStateProvider),
      onNavigateToAnnotation: _navigateToAnnotation,
      onEditAnnotation: (ann) {
        HighlightInteractionSheet.show(
          context: context,
          selectedText: ann.selectedText,
          initialColor: ann.color,
          initialNote: ann.note,
          theme: ref.read(readingThemeStateProvider),
          onSave: (color, note) async {
            final updated = ann.copyWith(
              color: color,
              note: note,
              updatedAt: DateTime.now(),
            );
            await dbService.saveAnnotation(updated);
          },
          onDelete: () async {
            await dbService.deleteAnnotation(ann.id, ann.type);
          },
        );
      },
      onDeleteAnnotation: (ann) async {
        await dbService.deleteAnnotation(ann.id, ann.type);
      },
    );
  }

  void _navigateToAnnotation(BookAnnotation ann) {
    if (_readingMode == ReadingMode.originalPdf) {
      if (ann.pageIndex != null) {
        _pdfKey.currentState?.jumpToPage(ann.pageIndex!);
      }
    } else {
      // Reflowable mode
      if (ann.anchorNodeId != null) {
        _reflowableKey.currentState?.jumpToAnchor(
          ann.anchorNodeId!,
          ann.startOffset,
        );
      } else if (ann.pageIndex != null && _readerDocument != null) {
        final node = _readerDocument!.chapters
            .expand((c) => c.nodes)
            .where((n) => n.sourcePdfPage == ann.pageIndex)
            .firstOrNull;
        if (node != null) {
          _reflowableKey.currentState?.jumpToAnchor(node.id, 0);
        }
      }
    }
  }

  void _openBookSearchDialog() {
    if (_document == null && _readerDocument == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(120),
      builder: (_) => BookSearchDialog(
        bookId: widget.book.id,
        pdfPath: _currentPdfPath,
        dbService: ref.read(databaseServiceProvider),
        readerDocument: _readerDocument,
        document: _document,
        theme: ref.read(readingThemeStateProvider),
        onNavigateToResult: (result) {
          _handleSearchResultSelected(result);
        },
      ),
    );
  }

  void _handleSearchResultSelected(InBookSearchResult result) {
    _navigationHistory.recordLocation(
      NavigationHistoryEntry(
        bookId: widget.book.id,
        chapterIndex: _reflowableChapter,
        anchorNodeId: _activeAnchorNodeId,
        characterOffset: _activeCharOffset,
        pageNumber: _currentPage,
        label: 'Sebelum pencarian',
      ),
    );

    _activeSearchQuery = result.matchedText;
    _currentSearchMatchIndex = 0;
    _activeSearchMatches = [
      ActiveSearchMatch(
        nodeId: result.nodeId,
        startOffset: result.startOffset,
        endOffset: result.endOffset,
        isActive: true,
      ),
    ];
    if (result.boundingBoxes.isNotEmpty) {
      _activePdfSearchHighlights = {result.sourcePdfPage: result.boundingBoxes};
    }
    _showSearchTraversal = true;

    // Cache or fetch all matches for traversal
    final doc =
        _readerDocument ??
        (_document != null
            ? ReflowableEngine.normalizeDocument(_document!)
            : null);
    if (doc != null) {
      InBookSearchEngine.search(document: doc, query: result.matchedText).then((
        allFound,
      ) {
        if (mounted) {
          setState(() {
            _searchResults = allFound;
            final foundIdx = allFound.indexWhere((r) => r.id == result.id);
            if (foundIdx != -1) _currentSearchMatchIndex = foundIdx;
          });
        }
      });
    }

    if (_readingMode == ReadingMode.reflowable) {
      _reflowableKey.currentState?.jumpToAnchor(
        result.nodeId,
        result.startOffset,
      );
    } else {
      _pdfKey.currentState?.jumpToPage(result.sourcePdfPage);
    }
    setState(() {});
  }

  void _goToSearchMatch(int index) {
    if (_searchResults.isEmpty) return;
    final clamped =
        (index % _searchResults.length + _searchResults.length) %
        _searchResults.length;
    final result = _searchResults[clamped];

    setState(() {
      _currentSearchMatchIndex = clamped;
      _activeSearchMatches = [
        ActiveSearchMatch(
          nodeId: result.nodeId,
          startOffset: result.startOffset,
          endOffset: result.endOffset,
          isActive: true,
        ),
      ];
      if (result.boundingBoxes.isNotEmpty) {
        _activePdfSearchHighlights = {
          result.sourcePdfPage: result.boundingBoxes,
        };
      }
    });

    if (_readingMode == ReadingMode.reflowable) {
      _reflowableKey.currentState?.jumpToAnchor(
        result.nodeId,
        result.startOffset,
      );
    } else {
      _pdfKey.currentState?.jumpToPage(result.sourcePdfPage);
    }
  }

  void _goToNextSearchMatch() {
    _goToSearchMatch(_currentSearchMatchIndex + 1);
  }

  void _goToPreviousSearchMatch() {
    _goToSearchMatch(_currentSearchMatchIndex - 1);
  }

  void _handleHistoryBack() {
    final prev = _navigationHistory.goBack();
    if (prev == null) return;

    if (_readingMode == ReadingMode.reflowable) {
      if (prev.anchorNodeId != null) {
        _reflowableKey.currentState?.jumpToAnchor(
          prev.anchorNodeId!,
          prev.characterOffset,
        );
      } else {
        _reflowableKey.currentState?.jumpToChapter(prev.chapterIndex);
      }
    } else {
      _pdfKey.currentState?.jumpToPage(prev.pageNumber);
    }
    setState(() {});
  }

  void _previousPage(ReadingMode mode) {
    if (mode == ReadingMode.originalPdf) {
      _pdfKey.currentState?.previousPage();
    } else {
      _reflowableKey.currentState?.previousPage();
    }
  }

  void _nextPage(ReadingMode mode) {
    if (mode == ReadingMode.originalPdf) {
      _pdfKey.currentState?.nextPage();
    } else {
      _reflowableKey.currentState?.nextPage();
    }
  }

  void _jumpToPosition(int page, ReadingMode mode) {
    if (mode == ReadingMode.originalPdf) {
      _pdfKey.currentState?.jumpToPage(page);
    } else {
      _reflowableKey.currentState?.jumpToPage(page);
    }
    _saveProgress(
      chapter: _currentChapter,
      position: page,
      percentage: _totalPages > 0 ? (page / _totalPages) : 0.0,
    );
  }

  void _saveProgress({
    required int chapter,
    required int position,
    required double percentage,
  }) {
    if (_currentChapter == chapter &&
        _currentPage == position &&
        (_progressPercentage - percentage).abs() < 0.001) {
      return;
    }

    setState(() {
      _currentChapter = chapter;
      _currentPage = position;
      _progressPercentage = percentage;
    });

    try {
      final dbService = ref.read(databaseServiceProvider);
      String modeStr = _readingMode.name;
      if (_readingMode == ReadingMode.reflowable) {
        modeStr = 'reflowable_paginated';
      }

      dbService.upsertProgress(
        ReadingProgressesCompanion(
          id: drift.Value(const Uuid().v4()),
          bookId: drift.Value(widget.book.id),
          currentChapter: drift.Value(chapter),
          currentPosition: drift.Value(position),
          progressPercentage: drift.Value(percentage.clamp(0.0, 1.0)),
          lastReadingMode: drift.Value(modeStr),
          lastReadAt: drift.Value(DateTime.now()),
        ),
      );
    } catch (_) {}
  }

  Future<void> _handleRelinkPdf() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result.isEmpty || result.first.path == null) return;

      final newFile = File(result.first.path!);
      if (!await newFile.exists()) return;

      final newHash = await FileStorageService.computeFileSha256(newFile);

      // Validate checksum against original book hash if available
      if (widget.book.fileHash != null &&
          widget.book.fileHash!.isNotEmpty &&
          widget.book.fileHash != newHash &&
          mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withAlpha(25)),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orangeAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'File Checksum Mismatch',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              'The selected PDF does not match the original file checksum (SHA-256). It appears to be a different document.\n\nRelinking to an incompatible file may cause existing bookmarks, highlights, and reading positions to be inaccurate.\n\nDo you want to proceed anyway?',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Relink Anyway'),
              ),
            ],
          ),
        );

        if (proceed != true) return;
      }

      final storedPdf = await FileStorageService.copyPdfToStorage(
        newFile,
        widget.book.id,
      );
      await ref
          .read(databaseServiceProvider)
          .updateBookPdfPath(
            widget.book.id,
            storedPdf.path,
            newFileHash: newHash,
          );

      if (mounted) {
        setState(() {
          _currentPdfPath = storedPdf.path;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Berkas PDF berhasil ditautkan kembali.'),
            backgroundColor: Color(0xFF2C2C2E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menautkan PDF: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleRemoveBook() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withAlpha(25)),
        ),
        title: const Text('Hapus Buku', style: TextStyle(color: Colors.white)),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${widget.book.title}" dari perpustakaan?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(databaseServiceProvider).safeDeleteBook(widget.book.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startAutoHideTimer();
    } else {
      _cancelAutoHideTimer();
    }
  }

  void _openAppearanceSheet() {
    _cancelAutoHideTimer();
    final width = MediaQuery.of(context).size.width;
    if (width >= 600) {
      showDialog(
        context: context,
        barrierColor: Colors.black.withAlpha(90),
        builder: (_) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
            child: Material(
              color: Colors.transparent,
              child: AppearanceSheet(bookId: widget.book.id, isDialog: true),
            ),
          ),
        ),
      ).then((_) {
        if (mounted) _startAutoHideTimer();
      });
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => AppearanceSheet(bookId: widget.book.id),
      ).then((_) {
        if (mounted) _startAutoHideTimer();
      });
    }
  }

  void _openTocDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(120),
      builder: (_) => TocDialog(
        bookId: widget.book.id,
        bookDocument: _document,
        readerDocument: _readerDocument,
        currentChapterIndex: _reflowableChapter,
        currentAnchorNodeId: _activeAnchorNodeId,
        onNavigateToTocItem: (chIndex, pageNum, anchorNodeId) {
          _navigationHistory.recordLocation(
            NavigationHistoryEntry(
              bookId: widget.book.id,
              chapterIndex: _reflowableChapter,
              anchorNodeId: _activeAnchorNodeId,
              characterOffset: _activeCharOffset,
              pageNumber: _currentPage,
              label: 'Sebelum navigasi daftar isi',
            ),
          );
          if (_readingMode == ReadingMode.originalPdf) {
            _pdfKey.currentState?.jumpToPage(pageNum);
          } else {
            if (anchorNodeId != null) {
              _reflowableKey.currentState?.jumpToAnchor(anchorNodeId, 0);
            } else {
              _reflowableKey.currentState?.jumpToChapter(chIndex);
            }
          }
          _saveProgress(
            chapter: chIndex,
            position: pageNum,
            percentage: _totalPages > 0 ? (pageNum / _totalPages) : 0.0,
          );
          setState(() {});
        },
        onNavigateToChapter: (chIndex, pageNum) {
          _navigationHistory.recordLocation(
            NavigationHistoryEntry(
              bookId: widget.book.id,
              chapterIndex: _reflowableChapter,
              anchorNodeId: _activeAnchorNodeId,
              characterOffset: _activeCharOffset,
              pageNumber: _currentPage,
              label: 'Sebelum navigasi bab',
            ),
          );
          if (_readingMode == ReadingMode.originalPdf) {
            _pdfKey.currentState?.jumpToPage(pageNum);
          } else {
            _reflowableKey.currentState?.jumpToChapter(chIndex);
          }
          _saveProgress(
            chapter: chIndex,
            position: pageNum,
            percentage: _totalPages > 0 ? (pageNum / _totalPages) : 0.0,
          );
          setState(() {});
        },
        onNavigateToPosition: (pos) {
          _navigationHistory.recordLocation(
            NavigationHistoryEntry(
              bookId: widget.book.id,
              chapterIndex: _reflowableChapter,
              anchorNodeId: _activeAnchorNodeId,
              characterOffset: _activeCharOffset,
              pageNumber: _currentPage,
              label: 'Sebelum navigasi posisi',
            ),
          );
          _jumpToPosition(pos, _readingMode);
          setState(() {});
        },
        onNavigateToAnchor: (anchorNodeId, charOffset) {
          _navigationHistory.recordLocation(
            NavigationHistoryEntry(
              bookId: widget.book.id,
              chapterIndex: _reflowableChapter,
              anchorNodeId: _activeAnchorNodeId,
              characterOffset: _activeCharOffset,
              pageNumber: _currentPage,
              label: 'Sebelum navigasi jangkar',
            ),
          );
          _reflowableKey.currentState?.jumpToAnchor(anchorNodeId, charOffset);
          setState(() {});
        },
      ),
    );
  }

  Future<void> _toggleBookmark() async {
    final dbService = ref.read(databaseServiceProvider);
    final bookmarks = await dbService.watchBookmarks(widget.book.id).first;
    final isReflowable = _readingMode == ReadingMode.reflowable;

    final existing = bookmarks.where((b) {
      if (isReflowable &&
          _activeAnchorNodeId != null &&
          b.anchorNodeId != null) {
        return b.anchorNodeId == _activeAnchorNodeId;
      }
      return b.position == _currentPage;
    }).toList();

    if (existing.isNotEmpty) {
      for (final b in existing) {
        await dbService.deleteBookmark(b.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Penanda buku dihapus'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else {
      final label = isReflowable && _currentChapterTitle.isNotEmpty
          ? '$_currentChapterTitle • Hal. $_currentPage'
          : 'Halaman $_currentPage';

      await dbService.addBookmark(
        BookmarksCompanion(
          id: drift.Value(const Uuid().v4()),
          bookId: drift.Value(widget.book.id),
          chapterId: drift.Value(
            _readerDocument != null && _readerDocument!.chapters.isNotEmpty
                ? _readerDocument!
                      .chapters[_currentChapter.clamp(
                        0,
                        _readerDocument!.chapters.length - 1,
                      )]
                      .id
                : null,
          ),
          position: drift.Value(_currentPage),
          label: drift.Value(label),
          anchorNodeId: drift.Value(_activeAnchorNodeId),
          characterOffset: drift.Value(_activeCharOffset),
          progressPercentage: drift.Value(_progressPercentage),
          createdAt: drift.Value(DateTime.now()),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ditandai: $label'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = ref.watch(readingThemeStateProvider);
    final typoSettings = ref.watch(typographySettingsStateProvider);
    final bookmarksAsync = ref.watch(
      bookBookmarksStreamProvider(widget.book.id),
    );
    final isBookmarked =
        bookmarksAsync.value?.any((b) {
          if (_readingMode == ReadingMode.reflowable &&
              _activeAnchorNodeId != null &&
              b.anchorNodeId != null) {
            return b.anchorNodeId == _activeAnchorNodeId;
          }
          return b.position == _currentPage;
        }) ??
        false;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Traversal shortcuts when in search mode
          if (_showSearchTraversal) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(() {
                _showSearchTraversal = false;
                _activeSearchMatches = [];
                _activePdfSearchHighlights = {};
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (HardwareKeyboard.instance.isShiftPressed) {
                _goToPreviousSearchMatch();
              } else {
                _goToNextSearchMatch();
              }
              return KeyEventResult.handled;
            }
          }

          final isMetaOrCtrl =
              HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;

          if (isMetaOrCtrl) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              if (_navigationHistory.canGoBack) {
                _handleHistoryBack();
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.equal ||
                event.logicalKey == LogicalKeyboardKey.add) {
              if (_readingMode == ReadingMode.originalPdf) {
                _pdfKey.currentState?.zoomIn();
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.minus) {
              if (_readingMode == ReadingMode.originalPdf) {
                _pdfKey.currentState?.zoomOut();
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.digit0) {
              if (_readingMode == ReadingMode.originalPdf) {
                _pdfKey.currentState?.resetZoom();
                return KeyEventResult.handled;
              }
            }
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.pageUp) {
            _previousPage(_readingMode);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.pageDown ||
              event.logicalKey == LogicalKeyboardKey.space) {
            _nextPage(_readingMode);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            final route = ModalRoute.of(context);
            if (route?.isCurrent == true) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: activeTheme.backgroundColor,
        body: MouseRegion(
          onHover: (_) => _onUserPointerInteraction(),
          child: SizedBox.expand(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Reading Body Engine
                Positioned.fill(
                  child: _isLoadingDoc
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: activeTheme.textColor,
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Menyiapkan buku...',
                                style: TextStyle(
                                  color: activeTheme.textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : (_readingMode == ReadingMode.reflowable &&
                            _document != null)
                      ? ReflowableReaderContainer(
                          key: _reflowableKey,
                          bookId: widget.book.id,
                          document: _readerDocument ??=
                              ReflowableEngine.normalizeDocument(_document!),
                          theme: activeTheme,
                          typography: typoSettings,
                          initialChapterIndex: _currentChapter,
                          initialPosition: _currentPage,
                          initialAnchorNodeId: _activeAnchorNodeId,
                          initialCharOffset: _activeCharOffset,
                          searchMatches: _activeSearchMatches,
                          onTapContent: _toggleControls,
                          onHighlightCreated: _handleHighlightCreated,
                          onTotalPagesCalculated: (total) {
                            if (_readingMode == ReadingMode.reflowable &&
                                mounted) {
                              setState(() {
                                _totalPages = total > 0 ? total : 1;
                              });
                            }
                          },
                          onProgressChanged:
                              (ch, page, pct, anchorId, charOffset) {
                                _reflowableChapter = ch;
                                _reflowablePosition = page;
                                _activeAnchorNodeId = anchorId;
                                _activeCharOffset = charOffset;
                                _updateChapterInfo(ch);
                                _saveProgress(
                                  chapter: ch,
                                  position: page,
                                  percentage: pct,
                                );
                              },
                        )
                      : OriginalPdfReader(
                          key: _pdfKey,
                          pdfPath: _currentPdfPath,
                          initialPage: _currentPage,
                          theme: activeTheme,
                          viewMode: ref.watch(pdfViewModeProvider),
                          enhancementConfig: ref.watch(
                            scanEnhancementConfigProvider(widget.book.id),
                          ),
                          searchHighlights: _activePdfSearchHighlights,
                          showControls: _showControls,
                          onTapContent: _toggleControls,
                          onSwitchToReflowable: _document != null
                              ? () => _setReadingMode(ReadingMode.reflowable)
                              : null,
                          onBack: () => Navigator.of(context).pop(),
                          onRelinkPdf: _handleRelinkPdf,
                          onRemoveBook: _handleRemoveBook,
                          onToggleViewMode: () {
                            final current = ref.read(pdfViewModeProvider);
                            ref
                                .read(pdfViewModeProvider.notifier)
                                .state = current == PdfViewMode.paginated
                                ? PdfViewMode.continuous
                                : PdfViewMode.paginated;
                          },
                          onPageChanged: (page, total) {
                            _pdfPage = page;
                            setState(() {
                              _currentPage = page;
                              _totalPages = total;
                              _progressPercentage = total > 0
                                  ? (page / total)
                                  : 0.0;
                            });
                            _saveProgress(
                              chapter: _reflowableChapter,
                              position: page,
                              percentage: total > 0 ? (page / total) : 0.0,
                            );
                          },
                        ),
                ),

                // Ambient Night Reading Dimmer Layer
                Consumer(
                  builder: (context, ref, _) {
                    final dimmer = ref.watch(readerBrightnessDimmerProvider);
                    if (dimmer <= 0.01) return const SizedBox.shrink();
                    return Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: Colors.black.withAlpha((dimmer * 255).toInt()),
                        ),
                      ),
                    );
                  },
                ),

                // 2. Minimalist Floating Apple Books Top Toolbar
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  top: _showControls ? 0 : -100,
                  left: 0,
                  right: 0,
                  child: _buildFloatingTopBar(
                    activeTheme,
                    _readingMode,
                    isBookmarked,
                  ),
                ),

                // 2.5 Floating In-Book Search Traversal Bar
                if (_showSearchTraversal)
                  Positioned(
                    top: _showControls ? 74 : 18,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SearchTraversalBar(
                        query: _activeSearchQuery,
                        currentIndex: _currentSearchMatchIndex,
                        totalCount: _searchResults.isNotEmpty
                            ? _searchResults.length
                            : 1,
                        theme: activeTheme,
                        onPrevious: _goToPreviousSearchMatch,
                        onNext: _goToNextSearchMatch,
                        onClose: () {
                          setState(() {
                            _showSearchTraversal = false;
                            _activeSearchMatches = [];
                            _activePdfSearchHighlights = {};
                          });
                        },
                      ),
                    ),
                  ),

                // 2.6 Automatic Reader Recommendation Banner (shown when Reflowable is active for low-fidelity/scanned books)
                if (_readingMode == ReadingMode.reflowable &&
                    !_dismissedQualityBanner &&
                    !_showSearchTraversal) ...[
                  Builder(
                    builder: (context) {
                      final quality =
                          _document?.metadata['reconstructionQuality']
                              as Map<String, dynamic>?;
                      // `book.isScanned` only describes the source PDF. Once a
                      // verified OCR derivative exists, Book Mode quality is
                      // described by reconstructionQuality; showing the
                      // "PDF Asli recommended" banner for every scanned book
                      // hides the fact that the reflowable document is good.
                      final isPoor =
                          quality?['status'] == 'poor' ||
                          (quality == null && widget.book.isScanned);
                      final isPartial = quality?['status'] == 'partial';

                      if (!isPoor && !isPartial) return const SizedBox.shrink();

                      return Positioned(
                        top: _showControls ? 76 : 18,
                        left: 20,
                        right: 20,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(12),
                              color: isPoor
                                  ? (activeTheme.isDark
                                        ? const Color(0xFF381A1A)
                                        : const Color(0xFFFEE2E2))
                                  : (activeTheme.isDark
                                        ? const Color(0xFF302B18)
                                        : const Color(0xFFFEF3C7)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isPoor
                                          ? Icons.warning_amber_rounded
                                          : Icons.info_outline,
                                      size: 18,
                                      color: isPoor
                                          ? (activeTheme.isDark
                                                ? const Color(0xFFFCA5A5)
                                                : const Color(0xFFDC2626))
                                          : (activeTheme.isDark
                                                ? const Color(0xFFFDE68A)
                                                : const Color(0xFFD97706)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        isPoor
                                            ? 'Dokumen ini hasil pindaian (scan) tanpa lapisan teks lengkap. Mode PDF Asli direkomendasikan untuk kenyamanan membaca.'
                                            : 'Tata letak dokumen ini memiliki kompleksitas visual. Mode PDF Asli tersedia untuk tata letak lengkap.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: isPoor
                                              ? (activeTheme.isDark
                                                    ? Colors.white
                                                    : const Color(0xFF7F1D1D))
                                              : (activeTheme.isDark
                                                    ? Colors.white
                                                    : const Color(0xFF78350F)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isPoor)
                                      TextButton(
                                        key: const ValueKey(
                                          'quality_banner_switch_button',
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () {
                                          _setReadingMode(
                                            ReadingMode.originalPdf,
                                          );
                                        },
                                        child: Text(
                                          'Buka PDF Asli',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isPoor
                                                ? (activeTheme.isDark
                                                      ? const Color(0xFFF87171)
                                                      : const Color(0xFFB91C1C))
                                                : (activeTheme.isDark
                                                      ? const Color(0xFFFBBF24)
                                                      : const Color(
                                                          0xFFB45309,
                                                        )),
                                          ),
                                        ),
                                      ),
                                    IconButton(
                                      key: const ValueKey(
                                        'quality_banner_close_button',
                                      ),
                                      icon: Icon(
                                        Icons.close,
                                        size: 16,
                                        color: activeTheme.secondaryTextColor,
                                      ),
                                      tooltip: 'Tutup',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        setState(() {
                                          _dismissedQualityBanner = true;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],

                // 3. Minimalist Floating Bottom Bar with Slider & Steppers
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  bottom: _showControls ? 0 : -100,
                  left: 0,
                  right: 0,
                  child: _buildFloatingBottomBar(activeTheme, _readingMode),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingTopBar(
    ReadingThemeType activeTheme,
    ReadingMode readingMode,
    bool isBookmarked,
  ) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktopOrTablet = screenWidth >= 680;
    final isCompact = screenWidth < 520;
    final isUltraCompact = screenWidth < 380;
    final pdfViewMode = ref.watch(pdfViewModeProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 16,
          vertical: 8,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: activeTheme.isDark
                    ? const Color(0xFF1E1E22).withAlpha(200)
                    : const Color(0xFFFFFFFF).withAlpha(210),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: activeTheme.isDark
                      ? Colors.white.withAlpha(25)
                      : Colors.black.withAlpha(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(activeTheme.isDark ? 80 : 25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Back button
                  IconButton(
                    key: const ValueKey('reader_top_back_button'),
                    tooltip: 'Back',
                    icon: Icon(
                      Icons.chevron_left,
                      color: activeTheme.textColor,
                      size: 26,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),

                  // History Back button (undo jump)
                  if (_navigationHistory.canGoBack)
                    IconButton(
                      key: const ValueKey('reader_history_back_button'),
                      tooltip: 'Kembali ke lokasi membaca sebelumnya (⌘←)',
                      icon: const Icon(
                        Icons.history_rounded,
                        color: Color(0xFF007AFF),
                        size: 20,
                      ),
                      onPressed: _handleHistoryBack,
                    ),

                  // Book Title & Chapter subtitle
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.book.title,
                          style: TextStyle(
                            color: activeTheme.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!isCompact)
                          Text(
                            _currentChapterTitle.isNotEmpty
                                ? '$_currentChapterTitle • ${widget.book.author}'
                                : widget.book.author,
                            style: TextStyle(
                              color: activeTheme.secondaryTextColor,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // Background OCR progress / trigger pill
                  Consumer(
                    builder: (context, ref, _) {
                      final ocrProgressAsync = ref.watch(
                        ocrQueueProgressStreamProvider,
                      );
                      final ocrProgress = ocrProgressAsync.valueOrNull;
                      final isThisBookOcrRunning =
                          ocrProgress != null &&
                          ocrProgress.bookId == widget.book.id &&
                          ocrProgress.isRunning;

                      if (isThisBookOcrRunning) {
                        return Container(
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withAlpha(25),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF007AFF).withAlpha(60),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Color(0xFF007AFF),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'OCR ${ocrProgress.completedPages}/${ocrProgress.totalPages} (${(ocrProgress.progressPercentage * 100).toInt()}%)',
                                style: const TextStyle(
                                  color: Color(0xFF007AFF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // If document is null or contains only raw fallback image pages (scanned PDF), allow triggering OCR directly from reader bar
                      final needsOcr =
                          _document == null ||
                          (widget.book.isScanned &&
                              _document!.chapters.isNotEmpty &&
                              _document!.chapters.every(
                                (c) => c.blocks.every(
                                  (b) => b.type == BlockType.image,
                                ),
                              ));
                      if (needsOcr && !isCompact) {
                        return Tooltip(
                          message:
                              'Mulai Pengenalan Teks Latar Belakang (OCR) agar dapat membaca dalam mode Teks / Reflowable',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              ref
                                  .read(backgroundOcrQueueProvider)
                                  .start(
                                    bookId: widget.book.id,
                                    pdfPath: widget.book.originalPdfPath,
                                    autoReconstruct: true,
                                  );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Pengenalan teks (OCR) dimulai di latar belakang. Mode Buku akan aktif setelah selesai.',
                                  ),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            },
                            child: Container(
                              height: 28,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: activeTheme.isDark
                                    ? Colors.white.withAlpha(15)
                                    : Colors.black.withAlpha(8),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: activeTheme.isDark
                                      ? Colors.white24
                                      : Colors.black12,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.document_scanner_outlined,
                                    size: 14,
                                    color: activeTheme.textColor,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Mulai OCR',
                                    style: TextStyle(
                                      color: activeTheme.textColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),

                  // Mode Switcher: Reflowable vs PDF (only if processed document is present and not compact)
                  if (_document != null && !isCompact) ...[
                    Container(
                      height: 30,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: activeTheme.isDark
                            ? Colors.white.withAlpha(20)
                            : Colors.black.withAlpha(12),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        children: [
                          _ModePillButton(
                            label: 'Book',
                            isSelected: readingMode == ReadingMode.reflowable,
                            activeTheme: activeTheme,
                            onTap: () =>
                                _setReadingMode(ReadingMode.reflowable),
                          ),
                          _ModePillButton(
                            label: 'PDF',
                            isSelected: readingMode == ReadingMode.originalPdf,
                            activeTheme: activeTheme,
                            onTap: () =>
                                _setReadingMode(ReadingMode.originalPdf),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],

                  // Book Mode is always paginated — scrolling/paginated toggle removed.

                  // 1-Page vs 2-Page Slide Toggle in Reflowable Mode
                  if (readingMode == ReadingMode.reflowable &&
                      isDesktopOrTablet)
                    Consumer(
                      builder: (context, ref, _) {
                        final layoutMode = ref.watch(
                          reflowableLayoutModeProvider(widget.book.id),
                        );
                        if (layoutMode != ReflowableLayoutMode.paginated) {
                          return const SizedBox.shrink();
                        }
                        final typo = ref.watch(typographySettingsStateProvider);
                        return IconButton(
                          tooltip: typo.twoPageSpread
                              ? 'Tampilan 2 Halaman'
                              : 'Tampilan 1 Halaman',
                          icon: Icon(
                            typo.twoPageSpread
                                ? Icons.auto_stories_rounded
                                : Icons.article_rounded,
                            color: activeTheme.textColor,
                            size: 20,
                          ),
                          onPressed: () {
                            final current = ref.read(
                              typographySettingsStateProvider,
                            );
                            ref
                                .read(typographySettingsStateProvider.notifier)
                                .state = current.copyWith(
                              twoPageSpread: !current.twoPageSpread,
                            );
                          },
                        );
                      },
                    ),

                  // PDF Zoom controls & View Mode Toggle
                  if (readingMode == ReadingMode.originalPdf) ...[
                    if (isDesktopOrTablet) ...[
                      if (pdfViewMode == PdfViewMode.paginated)
                        IconButton(
                          tooltip:
                              _pdfKey.currentState?.isTwoPageSpreadActive ==
                                  true
                              ? 'Tampilan 1 Halaman'
                              : 'Tampilan 2 Halaman (Buku Terbuka)',
                          icon: Icon(
                            _pdfKey.currentState?.isTwoPageSpreadActive == true
                                ? Icons.auto_stories_rounded
                                : Icons.article_rounded,
                            color: activeTheme.textColor,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _pdfKey.currentState?.toggleTwoPageSpread();
                            });
                          },
                        )
                      else
                        IconButton(
                          tooltip:
                              'Tampilan 2 halaman hanya tersedia dalam mode Halaman (Paginasi)',
                          icon: Icon(
                            Icons.article_rounded,
                            color: activeTheme.textColor.withAlpha(80),
                            size: 20,
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Tampilan 2 halaman hanya tersedia dalam mode Halaman (Paginasi). Silakan beralih dari Gulir Vertikal.',
                                ),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      IconButton(
                        tooltip: 'Zoom Out (Cmd -)',
                        icon: Icon(
                          Icons.zoom_out,
                          color: activeTheme.textColor,
                          size: 20,
                        ),
                        onPressed: () => _pdfKey.currentState?.zoomOut(),
                      ),
                      IconButton(
                        tooltip: 'Zoom In (Cmd +)',
                        icon: Icon(
                          Icons.zoom_in,
                          color: activeTheme.textColor,
                          size: 20,
                        ),
                        onPressed: () => _pdfKey.currentState?.zoomIn(),
                      ),
                    ],
                    if (!isUltraCompact)
                      IconButton(
                        tooltip: pdfViewMode == PdfViewMode.continuous
                            ? 'Mode Halaman'
                            : 'Mode Gulir Vertikal',
                        icon: Icon(
                          pdfViewMode == PdfViewMode.continuous
                              ? Icons.view_headline_rounded
                              : Icons.view_carousel_outlined,
                          color: activeTheme.textColor,
                          size: 20,
                        ),
                        onPressed: () {
                          final next = pdfViewMode == PdfViewMode.paginated
                              ? PdfViewMode.continuous
                              : PdfViewMode.paginated;
                          ref.read(pdfViewModeProvider.notifier).state = next;
                        },
                      ),
                  ],

                  // Table of Contents
                  if (!isUltraCompact)
                    IconButton(
                      key: const ValueKey('reader_toc_button'),
                      tooltip: 'Daftar Isi',
                      icon: Icon(
                        Icons.list_alt,
                        color: activeTheme.textColor,
                        size: 20,
                      ),
                      onPressed: _openTocDialog,
                    ),

                  // In-Book Search button
                  if ((_document != null || _readerDocument != null) &&
                      isDesktopOrTablet)
                    IconButton(
                      key: const ValueKey('reader_search_button'),
                      tooltip: 'Cari dalam buku',
                      icon: Icon(
                        Icons.search,
                        color: _showSearchTraversal
                            ? const Color(0xFFFF9500)
                            : activeTheme.textColor,
                        size: 20,
                      ),
                      onPressed: _openBookSearchDialog,
                    ),

                  // Quick Scan Enhancement Toggle for Original PDF Reader
                  if (readingMode == ReadingMode.originalPdf)
                    Consumer(
                      builder: (context, ref, _) {
                        final config = ref.watch(
                          scanEnhancementConfigProvider(widget.book.id),
                        );
                        return IconButton(
                          key: const ValueKey('reader_enhancement_toggle'),
                          tooltip: config.isEnabled
                              ? 'Enhance Aktif (Klik untuk Mode Asli)'
                              : 'Tingkatkan Kualitas Scan (Enhance)',
                          icon: Icon(
                            config.isEnabled
                                ? Icons.auto_fix_high
                                : Icons.auto_fix_normal_outlined,
                            color: config.isEnabled
                                ? const Color(0xFFD4AF37)
                                : activeTheme.textColor,
                            size: 20,
                          ),
                          onPressed: () {
                            ref
                                .read(
                                  scanEnhancementConfigProvider(
                                    widget.book.id,
                                  ).notifier,
                                )
                                .state = config.copyWith(
                              isEnabled: !config.isEnabled,
                            );
                          },
                        );
                      },
                    ),

                  // Appearance Settings (aA)
                  IconButton(
                    key: const ValueKey('reader_appearance_button'),
                    tooltip: 'Tampilan & Tema',
                    icon: Text(
                      'aA',
                      style: TextStyle(
                        color: activeTheme.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _openAppearanceSheet,
                  ),

                  // Annotations Library (Highlights, Notes, Bookmarks)
                  IconButton(
                    key: const ValueKey('reader_annotations_button'),
                    tooltip: 'Daftar Anotasi & Catatan',
                    icon: Icon(
                      Icons.collections_bookmark_rounded,
                      color: activeTheme.textColor,
                      size: 20,
                    ),
                    onPressed: _openAnnotationsSheet,
                  ),

                  // Bookmark button
                  IconButton(
                    key: const ValueKey('reader_bookmark_button'),
                    tooltip: isBookmarked ? 'Hapus Markah' : 'Tambah Markah',
                    icon: Icon(
                      isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: isBookmarked
                          ? const Color(0xFF007AFF)
                          : activeTheme.textColor,
                      size: 20,
                    ),
                    onPressed: _toggleBookmark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomBar(
    ReadingThemeType activeTheme,
    ReadingMode readingMode,
  ) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 500;
    final currentProgress = (_sliderDragValue ?? _progressPercentage).clamp(
      0.0,
      1.0,
    );
    final displayPage = _sliderDragValue != null
        ? (_sliderDragValue! * _totalPages).round().clamp(
            1,
            _totalPages > 0 ? _totalPages : 1,
          )
        : _currentPage;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 24,
          vertical: 10,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: activeTheme.isDark
                    ? const Color(0xFF1E1E22).withAlpha(200)
                    : const Color(0xFFFFFFFF).withAlpha(210),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: activeTheme.isDark
                      ? Colors.white.withAlpha(25)
                      : Colors.black.withAlpha(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(activeTheme.isDark ? 80 : 25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Builder(
                          builder: (context) {
                            String pageLabel;
                            final secPage =
                                _readingMode == ReadingMode.originalPdf
                                ? _pdfKey.currentState?.currentSecondaryPage
                                : null;

                            if (secPage != null && secPage != displayPage) {
                              final start = math.min(displayPage, secPage);
                              final end = math.max(displayPage, secPage);
                              pageLabel = 'Pages $start–$end of $_totalPages';
                            } else {
                              pageLabel = 'Page $displayPage of $_totalPages';
                            }

                            if (_readingMode == ReadingMode.reflowable &&
                                _estimatedMinutesLeftInChapter > 0 &&
                                !isCompact) {
                              pageLabel +=
                                  ' • ~$_estimatedMinutesLeftInChapter mnt tersisa';
                            }

                            return Text(
                              pageLabel,
                              style: TextStyle(
                                color: activeTheme.secondaryTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(currentProgress * 100).toInt()}%',
                        style: TextStyle(
                          color: activeTheme.textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Previous Page Stepper
                      IconButton(
                        tooltip: 'Previous Page',
                        icon: Icon(
                          Icons.chevron_left,
                          color: _currentPage > 1
                              ? activeTheme.textColor
                              : activeTheme.secondaryTextColor.withAlpha(80),
                          size: 22,
                        ),
                        onPressed: _currentPage > 1
                            ? () => _previousPage(readingMode)
                            : null,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: const Color(0xFF007AFF),
                            inactiveTrackColor: activeTheme.isDark
                                ? Colors.white.withAlpha(30)
                                : Colors.black.withAlpha(20),
                            thumbColor: Colors.white,
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                          ),
                          child: Slider(
                            value: currentProgress,
                            onChangeStart: (val) {
                              setState(() {
                                _sliderDragValue = val;
                              });
                            },
                            onChanged: (val) {
                              setState(() {
                                _sliderDragValue = val;
                              });
                            },
                            onChangeEnd: (val) {
                              setState(() {
                                _sliderDragValue = null;
                              });
                              final targetPage = (val * _totalPages)
                                  .round()
                                  .clamp(1, _totalPages > 0 ? _totalPages : 1);
                              _jumpToPosition(targetPage, readingMode);
                            },
                          ),
                        ),
                      ),
                      // Next Page Stepper
                      IconButton(
                        tooltip: 'Next Page',
                        icon: Icon(
                          Icons.chevron_right,
                          color: _currentPage < _totalPages
                              ? activeTheme.textColor
                              : activeTheme.secondaryTextColor.withAlpha(80),
                          size: 22,
                        ),
                        onPressed: _currentPage < _totalPages
                            ? () => _nextPage(readingMode)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModePillButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ReadingThemeType activeTheme;
  final VoidCallback onTap;

  const _ModePillButton({
    required this.label,
    required this.isSelected,
    required this.activeTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (activeTheme.isDark ? Colors.white.withAlpha(45) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected && !activeTheme.isDark
              ? [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 3)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? activeTheme.textColor
                : activeTheme.secondaryTextColor,
          ),
        ),
      ),
    );
  }
}
