class NavigationHistoryEntry {
  final String bookId;
  final int chapterIndex;
  final String? chapterId;
  final String? anchorNodeId;
  final int characterOffset;
  final int pageNumber;
  final String? label;
  final DateTime timestamp;

  NavigationHistoryEntry({
    required this.bookId,
    required this.chapterIndex,
    this.chapterId,
    this.anchorNodeId,
    this.characterOffset = 0,
    this.pageNumber = 1,
    this.label,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'NavigationHistoryEntry(book: $bookId, ch: $chapterIndex, anchor: $anchorNodeId, offset: $characterOffset, page: $pageNumber)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NavigationHistoryEntry &&
        other.bookId == bookId &&
        other.chapterIndex == chapterIndex &&
        other.anchorNodeId == anchorNodeId &&
        other.pageNumber == pageNumber;
  }

  @override
  int get hashCode =>
      Object.hash(bookId, chapterIndex, anchorNodeId, pageNumber);
}

class ReadingNavigationHistory {
  final String bookId;
  final int maxEntries;
  final List<NavigationHistoryEntry> _entries = [];
  int _currentIndex = -1;

  ReadingNavigationHistory({required this.bookId, this.maxEntries = 50});

  bool get canGoBack => _currentIndex > 0;
  bool get canGoForward =>
      _currentIndex >= 0 && _currentIndex < _entries.length - 1;
  NavigationHistoryEntry? get current =>
      (_currentIndex >= 0 && _currentIndex < _entries.length)
      ? _entries[_currentIndex]
      : null;

  int get length => _entries.length;
  int get currentIndex => _currentIndex;

  /// Pushes a new location to history. Discards any forward history.
  /// Prevents adding consecutive duplicate locations.
  void recordLocation(NavigationHistoryEntry entry) {
    if (entry.bookId != bookId) return;

    if (_currentIndex >= 0 && _currentIndex < _entries.length) {
      final cur = _entries[_currentIndex];
      // Skip if consecutive duplicate
      if (cur == entry) {
        return;
      }
      // Truncate any forward entries when a new navigation occurs
      if (_currentIndex < _entries.length - 1) {
        _entries.removeRange(_currentIndex + 1, _entries.length);
      }
    }

    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    _currentIndex = _entries.length - 1;
  }

  /// Navigates back in history. Returns target entry or null.
  NavigationHistoryEntry? goBack() {
    if (!canGoBack) return null;
    _currentIndex--;
    return _entries[_currentIndex];
  }

  /// Navigates forward in history. Returns target entry or null.
  NavigationHistoryEntry? goForward() {
    if (!canGoForward) return null;
    _currentIndex++;
    return _entries[_currentIndex];
  }

  void clear() {
    _entries.clear();
    _currentIndex = -1;
  }
}
