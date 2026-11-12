import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'highlight_interaction_sheet.dart';
import 'paginated_reflowable_reader.dart';
// scrolling_reflowable_reader.dart intentionally not imported:
// Book Mode is always horizontal paginated.

class ReflowableReaderContainer extends ConsumerStatefulWidget {
  final String bookId;
  final ReaderDocument document;
  final ReadingThemeType theme;
  final TypographySettings typography;
  final int initialChapterIndex;
  final int initialPosition;
  final String? initialAnchorNodeId;
  final int initialCharOffset;
  final VoidCallback onTapContent;
  final Function(
    int chapterIndex,
    int position,
    double percentage,
    String? anchorNodeId,
    int charOffset,
  )
  onProgressChanged;
  final void Function(int totalPages)? onTotalPagesCalculated;
  final Function(String text, String color, int pageNumber)? onHighlightCreated;
  final List<Highlight>? customHighlights;
  final List<ActiveSearchMatch> searchMatches;

  const ReflowableReaderContainer({
    super.key,
    required this.bookId,
    required this.document,
    required this.theme,
    required this.typography,
    this.initialChapterIndex = 0,
    this.initialPosition = 0,
    this.initialAnchorNodeId,
    this.initialCharOffset = 0,
    required this.onTapContent,
    required this.onProgressChanged,
    this.onTotalPagesCalculated,
    this.onHighlightCreated,
    this.customHighlights,
    this.searchMatches = const [],
  });

  @override
  ConsumerState<ReflowableReaderContainer> createState() =>
      ReflowableReaderContainerState();
}

class ReflowableReaderContainerState
    extends ConsumerState<ReflowableReaderContainer> {
  final GlobalKey<PaginatedReflowableReaderState> _paginatedKey =
      GlobalKey<PaginatedReflowableReaderState>();
  // _scrollingKey removed: Book Mode is always paginated.

  String? _activeAnchorNodeId;
  int _activeCharOffset = 0;
  int _currentChapter = 0;
  int _currentPage = 1;
  int _totalPages = 1;

  int get totalPages => _paginatedKey.currentState?.totalPages ?? _totalPages;
  int get currentPage => _currentPage;
  String? get activeAnchorNodeId => _activeAnchorNodeId;

  @override
  void initState() {
    super.initState();
    _activeAnchorNodeId = widget.initialAnchorNodeId;
    _activeCharOffset = widget.initialCharOffset;
    _currentChapter = widget.initialChapterIndex;
    _currentPage = widget.initialPosition > 0 ? widget.initialPosition : 1;

    if (widget.initialAnchorNodeId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        jumpToAnchor(widget.initialAnchorNodeId!, widget.initialCharOffset);
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReflowableReaderContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAnchorNodeId != null &&
        widget.initialAnchorNodeId != oldWidget.initialAnchorNodeId) {
      _activeAnchorNodeId = widget.initialAnchorNodeId;
      _activeCharOffset = widget.initialCharOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        jumpToAnchor(widget.initialAnchorNodeId!, widget.initialCharOffset);
      });
    }
  }

  void nextPage() {
    _paginatedKey.currentState?.nextPage();
  }

  void previousPage() {
    _paginatedKey.currentState?.previousPage();
  }

  void jumpToPage(int pageNumber) {
    _paginatedKey.currentState?.jumpToPage(pageNumber);
  }

  void jumpToAnchor(String nodeId, [int charOffset = 0]) {
    _activeAnchorNodeId = nodeId;
    _activeCharOffset = charOffset;
    _paginatedKey.currentState?.jumpToAnchor(nodeId, charOffset);
  }

  void jumpToChapter(int chapterIndex) {
    _paginatedKey.currentState?.jumpToChapter(chapterIndex);
  }

  Future<void> _handleHighlightCreated({
    required String text,
    required String color,
    String? note,
    required String anchorNodeId,
    required int startOffset,
    required int endOffset,
    String? prefixContext,
    String? suffixContext,
    required int pageNumber,
  }) async {
    final dbService = ref.read(databaseServiceProvider);
    final id = const Uuid().v4();
    final chapter = widget.document.chapters.isNotEmpty
        ? widget.document.chapters[_currentChapter.clamp(
            0,
            widget.document.chapters.length - 1,
          )]
        : null;

    await dbService.addHighlight(
      HighlightsCompanion(
        id: drift.Value(id),
        bookId: drift.Value(widget.bookId),
        chapterId: drift.Value(chapter?.id),
        selectedText: drift.Value(text),
        startPosition: drift.Value(pageNumber),
        endPosition: drift.Value(pageNumber),
        color: drift.Value(color),
        note: drift.Value(note),
        anchorNodeId: drift.Value(anchorNodeId),
        startOffset: drift.Value(startOffset),
        endOffset: drift.Value(endOffset),
        prefixContext: drift.Value(prefixContext),
        suffixContext: drift.Value(suffixContext),
        anchorVersion: const drift.Value(1),
        createdAt: drift.Value(DateTime.now()),
      ),
    );

    widget.onHighlightCreated?.call(text, color, pageNumber);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            note != null ? 'Highlight and note saved' : 'Text highlighted',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _handleHighlightTap(Highlight hl) {
    HighlightInteractionSheet.show(
      context: context,
      existingHighlight: hl,
      selectedText: hl.selectedText,
      theme: widget.theme,
      onSave: (color, note) async {
        final dbService = ref.read(databaseServiceProvider);
        if (color != hl.color) {
          await dbService.updateHighlightColor(hl.id, color);
        }
        if (note != hl.note) {
          await dbService.updateHighlightNote(hl.id, note);
        }
      },
      onDelete: () async {
        final dbService = ref.read(databaseServiceProvider);
        await dbService.deleteHighlight(hl.id);
      },
    );
  }

  void _handleProgressChanged(
    int chapterIndex,
    int position,
    double percentage,
    String? anchorNodeId,
    int charOffset,
  ) {
    _currentChapter = chapterIndex;
    _currentPage = position;
    if (anchorNodeId != null) {
      _activeAnchorNodeId = anchorNodeId;
      _activeCharOffset = charOffset;
    }

    widget.onProgressChanged(
      chapterIndex,
      position,
      percentage,
      anchorNodeId,
      charOffset,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Book Mode is always paginated — no layout mode switch needed.
    final highlightsStream = ref.watch(
      bookHighlightsStreamProvider(widget.bookId),
    );
    final effectiveHighlights =
        widget.customHighlights ?? highlightsStream.value ?? const [];

    final Widget content = PaginatedReflowableReader(
      key: _paginatedKey,
      document: widget.document,
      theme: widget.theme,
      typography: widget.typography,
      initialPageIndex: _currentPage > 0 ? _currentPage - 1 : 0,
      initialAnchorNodeId: _activeAnchorNodeId,
      initialCharOffset: _activeCharOffset,
      highlights: effectiveHighlights,
      searchMatches: widget.searchMatches,
      onTapContent: widget.onTapContent,
      onProgressChanged: (ch, page, pct, anchor, offset) {
        _handleProgressChanged(ch, page, pct, anchor, offset);
      },
      onTotalPagesCalculated: (total) {
        _totalPages = total;
        widget.onTotalPagesCalculated?.call(total);
      },
      onHighlightCreated: _handleHighlightCreated,
      onHighlightTap: _handleHighlightTap,
    );

    return Container(color: widget.theme.backgroundColor, child: content);
  }
}
