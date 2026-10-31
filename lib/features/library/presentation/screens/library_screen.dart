import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/typography/typography_settings.dart';
import '../../../../core/utils/book_sort_helper.dart';
import '../../../../core/utils/sample_book_generator.dart';
import '../../../processing/providers/import_provider.dart';
import '../../../reader/presentation/screens/reading_screen.dart';
import '../../../reader/presentation/widgets/reflowable/highlight_interaction_sheet.dart';
import '../../../reader/providers/reader_settings_provider.dart';
import '../widgets/book_card.dart';
import '../widgets/book_details_dialog.dart';
import '../widgets/book_list_tile.dart';
import '../widgets/import_pdf_dialog.dart';

enum LibraryNavigationSection {
  home('Reading Now', Icons.auto_stories),
  allBooks('All Books', Icons.library_books),
  currentlyReading('Currently Reading', Icons.bookmark_added),
  finished('Finished', Icons.check_circle_outline),
  collections('Collections', Icons.folder_outlined),
  bookmarks('Bookmarks', Icons.bookmark_border_rounded),
  highlights('Highlights & Notes', Icons.border_color_outlined),
  search('Search', Icons.search),
  settings('Settings', Icons.settings_outlined);

  final String label;
  final IconData icon;
  const LibraryNavigationSection(this.label, this.icon);
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  LibraryNavigationSection _selectedSection = LibraryNavigationSection.home;
  String? _selectedCollectionId;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
          bottomNavigationBar: isDesktop ? null : _buildMobileBottomBar(),
        );
      },
    );
  }

  // --- 1. macOS Desktop Split Layout ---
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // macOS Sidebar
        Container(
          width: 250,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF161618)
                : const Color(0xFFF2F2F7),
            border: Border(
              right: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withAlpha(15)
                    : Colors.black.withAlpha(15),
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // macOS App Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Books',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                // Import Button in Sidebar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(
                        'Import PDF',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () =>
                          ImportPdfHelper.pickAndImportPdf(context, ref),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Navigation Items List
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      _buildSidebarCategoryHeader('READING'),
                      _buildSidebarItem(LibraryNavigationSection.home),

                      const SizedBox(height: 12),
                      _buildSidebarCategoryHeader('LIBRARY'),
                      _buildSidebarItem(LibraryNavigationSection.allBooks),
                      _buildSidebarItem(
                          LibraryNavigationSection.currentlyReading),
                      _buildSidebarItem(LibraryNavigationSection.finished),

                      const SizedBox(height: 12),
                      _buildCollectionsSidebarCategory(),

                      const SizedBox(height: 12),
                      _buildSidebarCategoryHeader('ANNOTATIONS'),
                      _buildSidebarItem(LibraryNavigationSection.bookmarks),
                      _buildSidebarItem(LibraryNavigationSection.highlights),

                      const SizedBox(height: 16),
                      Divider(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withAlpha(15)
                            : Colors.black.withAlpha(15),
                      ),
                      _buildSidebarItem(LibraryNavigationSection.settings),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Main Content Area
        Expanded(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDesktopTopBar(),
                Expanded(child: _buildSectionContent()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarCategoryHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildCollectionsSidebarCategory() {
    final collectionsAsync = ref.watch(collectionsStreamProvider);
    final bookCountsAsync = ref.watch(collectionBookCountsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'COLLECTIONS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: _showCreateCollectionDialog,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
        // All Collections Item
        _buildSidebarItem(
          LibraryNavigationSection.collections,
          onTap: () {
            setState(() {
              _selectedSection = LibraryNavigationSection.collections;
              _selectedCollectionId = null;
            });
          },
          isSelected: _selectedSection == LibraryNavigationSection.collections &&
              _selectedCollectionId == null,
        ),
        // Dynamic collections list
        collectionsAsync.when(
          data: (collections) {
            final counts = bookCountsAsync.asData?.value ?? {};
            return Column(
              children: collections.map((col) {
                final isSelected =
                    _selectedSection == LibraryNavigationSection.collections &&
                        _selectedCollectionId == col.id;
                final count = counts[col.id] ?? 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _selectedSection =
                            LibraryNavigationSection.collections;
                        _selectedCollectionId = col.id;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark
                                ? Colors.white.withAlpha(30)
                                : const Color(0xFFE5E5EA))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_rounded,
                            size: 16,
                            color: isSelected
                                ? const Color(0xFF007AFF)
                                : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              col.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade800),
                              ),
                            ),
                          ),
                          if (count > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF007AFF)
                                    : (isDark
                                        ? Colors.white.withAlpha(20)
                                        : Colors.black.withAlpha(15)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, stack) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildSidebarItem(
    LibraryNavigationSection section, {
    VoidCallback? onTap,
    bool? isSelected,
  }) {
    final selected = isSelected ??
        (_selectedSection == section && _selectedCollectionId == null);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap ??
            () {
              setState(() {
                _selectedSection = section;
                _selectedCollectionId = null;
              });
            },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? Colors.white.withAlpha(30) : const Color(0xFFE5E5EA))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                section.icon,
                size: 17,
                color: selected
                    ? const Color(0xFF007AFF)
                    : Colors.grey.shade500,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTopBar() {
    final viewMode = ref.watch(libraryViewModeProvider);
    final sortOption = ref.watch(bookSortOptionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final collectionsAsync = ref.watch(collectionsStreamProvider);
    String headerTitle = _selectedSection.label;
    if (_selectedSection == LibraryNavigationSection.collections &&
        _selectedCollectionId != null) {
      final col = collectionsAsync.asData?.value
          .cast<Collection?>()
          .firstWhere((c) => c?.id == _selectedCollectionId, orElse: () => null);
      if (col != null) {
        headerTitle = col.name;
      }
    }

    final showListControls =
        _selectedSection == LibraryNavigationSection.home ||
            _selectedSection == LibraryNavigationSection.allBooks ||
            _selectedSection == LibraryNavigationSection.currentlyReading ||
            _selectedSection == LibraryNavigationSection.finished ||
            _selectedSection == LibraryNavigationSection.collections ||
            _selectedSection == LibraryNavigationSection.search;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        children: [
          // Breadcrumb or Section Title
          if (_selectedSection == LibraryNavigationSection.collections &&
              _selectedCollectionId != null) ...[
            InkWell(
              onTap: () {
                setState(() => _selectedCollectionId = null);
              },
              child: Text(
                'Collections',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.chevron_right, size: 20, color: Colors.grey),
            ),
            Flexible(
              child: Text(
                headerTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            Flexible(
              child: Text(
                headerTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const Spacer(),

          // Search Field
          if (_selectedSection != LibraryNavigationSection.search)
            SizedBox(
              width: 170,
              height: 34,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withAlpha(20)
                      : Colors.black.withAlpha(10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  ref.read(searchQueryProvider.notifier).state = val;
                  if (val.isNotEmpty &&
                      _selectedSection != LibraryNavigationSection.search) {
                    setState(() {
                      _selectedSection = LibraryNavigationSection.search;
                    });
                  }
                },
              ),
            ),

          if (showListControls) ...[
            const SizedBox(width: 12),

            // Sort Dropdown Button
            PopupMenuButton<BookSortOption>(
              tooltip: 'Sort by',
              elevation: 8,
              color: isDark ? const Color(0xFF222226) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isDark ? Colors.white.withAlpha(20) : Colors.black12,
                ),
              ),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(15)
                      : Colors.black.withAlpha(8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(sortOption.icon, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      sortOption.label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 16),
                  ],
                ),
              ),
              onSelected: (option) {
                ref.read(bookSortOptionProvider.notifier).state = option;
              },
              itemBuilder: (context) {
                return BookSortOption.values.map((option) {
                  final isCurrent = option == sortOption;
                  return PopupMenuItem<BookSortOption>(
                    value: option,
                    height: 36,
                    child: Row(
                      children: [
                        Icon(
                          option.icon,
                          size: 16,
                          color: isCurrent
                              ? const Color(0xFF007AFF)
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            option.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrent
                                  ? const Color(0xFF007AFF)
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                        ),
                        if (isCurrent)
                          const Icon(Icons.check,
                              size: 15, color: Color(0xFF007AFF)),
                      ],
                    ),
                  );
                }).toList();
              },
            ),

            const SizedBox(width: 10),

            // View Mode Toggle (Grid vs List)
            Container(
              height: 34,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(15)
                    : Colors.black.withAlpha(8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildViewModeButton(
                    mode: LibraryViewMode.grid,
                    icon: Icons.grid_view_rounded,
                    isActive: viewMode == LibraryViewMode.grid,
                  ),
                  _buildViewModeButton(
                    mode: LibraryViewMode.list,
                    icon: Icons.view_list_rounded,
                    isActive: viewMode == LibraryViewMode.list,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewModeButton({
    required LibraryViewMode mode,
    required IconData icon,
    required bool isActive,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: () {
        ref.read(libraryViewModeProvider.notifier).state = mode;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? Colors.white.withAlpha(35) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 50 : 15),
                    blurRadius: 4,
                  )
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 17,
          color: isActive
              ? const Color(0xFF007AFF)
              : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
        ),
      ),
    );
  }

  // --- 2. Mobile Layout ---
  Widget _buildMobileLayout() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedSection.label,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle,
                      color: Color(0xFF007AFF), size: 28),
                  onPressed: () =>
                      ImportPdfHelper.pickAndImportPdf(context, ref),
                ),
              ],
            ),
          ),
          Expanded(child: _buildSectionContent()),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar() {
    return NavigationBar(
      selectedIndex: _getMobileNavIndex(_selectedSection),
      onDestinationSelected: (index) {
        setState(() {
          switch (index) {
            case 0:
              _selectedSection = LibraryNavigationSection.home;
              _selectedCollectionId = null;
              break;
            case 1:
              _selectedSection = LibraryNavigationSection.allBooks;
              _selectedCollectionId = null;
              break;
            case 2:
              _selectedSection = LibraryNavigationSection.collections;
              _selectedCollectionId = null;
              break;
            case 3:
              _selectedSection = LibraryNavigationSection.bookmarks;
              _selectedCollectionId = null;
              break;
            case 4:
              _selectedSection = LibraryNavigationSection.settings;
              _selectedCollectionId = null;
              break;
          }
        });
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.auto_stories_outlined),
          selectedIcon: Icon(Icons.auto_stories),
          label: 'Reading',
        ),
        NavigationDestination(
          icon: Icon(Icons.library_books_outlined),
          selectedIcon: Icon(Icons.library_books),
          label: 'Library',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder),
          label: 'Collections',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_border_rounded),
          selectedIcon: Icon(Icons.bookmark),
          label: 'Bookmarks',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }

  int _getMobileNavIndex(LibraryNavigationSection section) {
    switch (section) {
      case LibraryNavigationSection.home:
      case LibraryNavigationSection.currentlyReading:
        return 0;
      case LibraryNavigationSection.allBooks:
      case LibraryNavigationSection.finished:
        return 1;
      case LibraryNavigationSection.collections:
        return 2;
      case LibraryNavigationSection.bookmarks:
      case LibraryNavigationSection.highlights:
        return 3;
      case LibraryNavigationSection.search:
      case LibraryNavigationSection.settings:
        return 4;
    }
  }

  // --- 3. Section Content Routing ---
  Widget _buildSectionContent() {
    switch (_selectedSection) {
      case LibraryNavigationSection.home:
        return _buildHomeSection();
      case LibraryNavigationSection.allBooks:
        return _buildAllBooksSection();
      case LibraryNavigationSection.currentlyReading:
        return _buildCurrentlyReadingSection();
      case LibraryNavigationSection.finished:
        return _buildFinishedBooksSection();
      case LibraryNavigationSection.collections:
        return _buildCollectionsSection();
      case LibraryNavigationSection.bookmarks:
        return _buildBookmarksSection();
      case LibraryNavigationSection.highlights:
        return _buildHighlightsSection();
      case LibraryNavigationSection.search:
        return _buildSearchSection();
      case LibraryNavigationSection.settings:
        return _buildSettingsSection();
    }
  }

  // --- Home: Reading Now Hero Spotlight + Shelf + Recently Added ---
  Widget _buildHomeSection() {
    final currentlyReadingAsync = ref.watch(currentlyReadingStreamProvider);
    final recentlyAddedAsync = ref.watch(recentlyAddedStreamProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      children: [
        // Continue Reading Hero Spotlight
        currentlyReadingAsync.when(
          data: (books) {
            if (books.isEmpty) return const SizedBox.shrink();
            final heroItem = books.first;
            final remainingBooks = books.sublist(1);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroReadingCard(heroItem, isStarted: true),
                if (remainingBooks.isNotEmpty) ...[
                  const Text(
                    'BUKU LAIN SEDANG DIBACA',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 250,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: remainingBooks.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 18),
                      itemBuilder: (context, index) {
                        final item = remainingBooks[index];
                        return SizedBox(
                          width: 140,
                          child: BookCard(
                            book: item.book,
                            progressPercentage: item.progress?.progressPercentage,
                            onDetails: () => _openBookDetails(item.book),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, stack) => const SizedBox.shrink(),
        ),

        // Recently Added Shelf
        const Text(
          'RECENTLY ADDED',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 16),
        recentlyAddedAsync.when(
          data: (books) {
            if (books.isEmpty) {
              return _buildEmptyState(
                title: 'Your Library is Empty',
                subtitle:
                    'Import personal PDF books from your device to start reading with the Apple Books experience.',
              );
            }
            return _buildBookListOrGrid(books);
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Center(
            child: Text('Error loading books: $e'),
          ),
        ),
      ],
    );
  }

  // --- All Books Section ---
  Widget _buildAllBooksSection() {
    final allBooksAsync = ref.watch(allBooksStreamProvider);

    return allBooksAsync.when(
      data: (books) {
        if (books.isEmpty) {
          return _buildEmptyState(
            title: 'No Books in Library',
            subtitle: 'Click "Import PDF" to add your books.',
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: _buildBookListOrGrid(books),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // --- Currently Reading Section ---
  Widget _buildCurrentlyReadingSection() {
    final readingAsync = ref.watch(currentlyReadingStreamProvider);

    return readingAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState(
            title: 'No Books Currently In Progress',
            subtitle:
                'Start reading any book from your library to track progress.',
          );
        }
        final progressMap = {
          for (final i in items) i.book.id: i.progress?.progressPercentage ?? 0.0
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: _buildBookListOrGrid(
            items.map((i) => i.book).toList(),
            progressMap: progressMap,
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // --- Finished Books Section ---
  Widget _buildFinishedBooksSection() {
    final finishedAsync = ref.watch(finishedBooksStreamProvider);

    return finishedAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState(
            title: 'No Finished Books Yet',
            subtitle: 'Books you finish will be archived here.',
          );
        }
        final progressMap = {
          for (final i in items) i.book.id: i.progress?.progressPercentage ?? 1.0
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: _buildBookListOrGrid(
            items.map((i) => i.book).toList(),
            progressMap: progressMap,
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // --- Collections Section (Overview or Single Collection) ---
  Widget _buildCollectionsSection() {
    if (_selectedCollectionId != null) {
      // Viewing a specific collection
      final booksInColAsync =
          ref.watch(booksInCollectionStreamProvider(_selectedCollectionId!));
      final collectionsAsync = ref.watch(collectionsStreamProvider);

      final col = collectionsAsync.asData?.value
          .cast<Collection?>()
          .firstWhere((c) => c?.id == _selectedCollectionId, orElse: () => null);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Collection Action Bar
            Row(
              children: [
                if (col != null)
                  Text(
                    col.description ?? 'Curated personal reading collection',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                const Spacer(),
                if (col != null) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Rename'),
                    onPressed: () => _showRenameCollectionDialog(col),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete Collection'),
                    onPressed: () => _confirmDeleteCollection(col),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: booksInColAsync.when(
                data: (books) {
                  if (books.isEmpty) {
                    return _buildEmptyState(
                      title: 'No Books in this Collection',
                      subtitle:
                          'Open any book options (•••) and select "Manage Collections" to add books here.',
                    );
                  }
                  return _buildBookListOrGrid(books);
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      );
    }

    // Viewing all collections overview
    final collectionsAsync = ref.watch(collectionsStreamProvider);
    final bookCountsAsync = ref.watch(collectionBookCountsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return collectionsAsync.when(
      data: (collections) {
        if (collections.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.folder_special_rounded,
                      size: 48,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Collections Yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create custom collections like "Favorites", "Psychology", or "Work" to organize your library.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create First Collection'),
                    onPressed: _showCreateCollectionDialog,
                  ),
                ],
              ),
            ),
          );
        }

        final counts = bookCountsAsync.asData?.value ?? {};

        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            mainAxisExtent: 130,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: collections.length + 1,
          itemBuilder: (context, index) {
            if (index == collections.length) {
              // Add Collection Card
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _showCreateCollectionDialog,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withAlpha(25)
                          : Colors.black.withAlpha(20),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 28, color: const Color(0xFF007AFF)),
                        const SizedBox(height: 8),
                        const Text(
                          'New Collection',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF007AFF)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final col = collections[index];
            final count = counts[col.id] ?? 0;

            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                setState(() {
                  _selectedCollectionId = col.id;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E22)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withAlpha(20)
                        : Colors.black.withAlpha(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 40 : 15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.folder_rounded,
                            color: Color(0xFF007AFF),
                            size: 22,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withAlpha(15)
                                : Colors.black.withAlpha(10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count ${count == 1 ? 'book' : 'books'}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      col.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // --- Bookmarks Section ---
  Widget _buildBookmarksSection() {
    final bookmarksAsync = ref.watch(allBookmarksStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFormat = DateFormat.yMMMd();

    return bookmarksAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState(
            title: 'No Bookmarks Yet',
            subtitle:
                'Tap the bookmark icon in the reader toolbar while reading to save important pages here.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            final bookmark = item.bookmark;
            final book = item.book;
            final coverFile =
                book.coverPath != null ? File(book.coverPath!) : null;

            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(18)
                      : Colors.black.withAlpha(15),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReadingScreen(
                          book: book,
                          initialMode: book.isScanned
                              ? ReadingMode.originalPdf
                              : ReadingMode.reflowable,
                          initialPage: bookmark.position,
                          initialAnchorNodeId: bookmark.anchorNodeId,
                          initialCharOffset: bookmark.characterOffset,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // Cover Thumbnail
                        Container(
                          width: 36,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: (coverFile != null && coverFile.existsSync())
                                ? Image.file(coverFile, fit: BoxFit.cover)
                                : Container(
                                    color: const Color(0xFF2C2C2E),
                                    child: const Icon(Icons.book,
                                        size: 18, color: Colors.white70),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.bookmark,
                                      size: 16, color: const Color(0xFF007AFF)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      bookmark.label.isNotEmpty
                                          ? bookmark.label
                                          : 'Page ${bookmark.position}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    dateFormat.format(bookmark.createdAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.grey.shade500
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${book.title} • Page ${bookmark.position}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: Colors.grey.shade400,
                          tooltip: 'Delete Bookmark',
                          onPressed: () async {
                            await ref
                                .read(databaseServiceProvider)
                                .deleteBookmark(bookmark.id);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // --- Highlights & Notes Section ---
  Widget _buildHighlightsSection() {
    final highlightsAsync = ref.watch(allHighlightsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFormat = DateFormat.yMMMd();

    return highlightsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState(
            title: 'No Highlights or Notes Yet',
            subtitle:
                'Select text while reading to highlight important passages and write personal annotations.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = items[index];
            final highlight = item.highlight;
            final book = item.book;
            final coverFile =
                book.coverPath != null ? File(book.coverPath!) : null;

            Color highlightColor = const Color(0xFFFFD600);
            if (highlight.color.contains('green')) {
              highlightColor = const Color(0xFF34C759);
            } else if (highlight.color.contains('blue')) {
              highlightColor = const Color(0xFF007AFF);
            } else if (highlight.color.contains('pink') ||
                highlight.color.contains('red')) {
              highlightColor = const Color(0xFFFF2D55);
            } else if (highlight.color.contains('purple')) {
              highlightColor = const Color(0xFFAF52DE);
            }

            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(18)
                      : Colors.black.withAlpha(15),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReadingScreen(
                          book: book,
                          initialMode: book.isScanned
                              ? ReadingMode.originalPdf
                              : ReadingMode.reflowable,
                          initialPage: highlight.startPosition,
                          initialAnchorNodeId: highlight.anchorNodeId,
                          initialCharOffset: highlight.startOffset,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: Book info + delete
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: (coverFile != null &&
                                        coverFile.existsSync())
                                    ? Image.file(coverFile, fit: BoxFit.cover)
                                    : Container(
                                        color: const Color(0xFF2C2C2E),
                                        child: const Icon(Icons.book,
                                            size: 14, color: Colors.white70),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    book.title,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Page ${highlight.startPosition} • ${dateFormat.format(highlight.createdAt)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_note_rounded, size: 20),
                              color: Colors.grey.shade400,
                              tooltip: 'Edit Note / Color',
                              onPressed: () {
                                HighlightInteractionSheet.show(
                                  context: context,
                                  existingHighlight: highlight,
                                  selectedText: highlight.selectedText,
                                  initialColor: highlight.color,
                                  initialNote: highlight.note,
                                  theme: isDark ? ReadingThemeType.black : ReadingThemeType.white,
                                  onSave: (color, note) async {
                                    final dbService = ref.read(databaseServiceProvider);
                                    if (color != highlight.color) {
                                      await dbService.updateHighlightColor(highlight.id, color);
                                    }
                                    if (note != highlight.note) {
                                      await dbService.updateHighlightNote(highlight.id, note);
                                    }
                                  },
                                  onDelete: () async {
                                    await ref.read(databaseServiceProvider).deleteHighlight(highlight.id);
                                  },
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: Colors.grey.shade400,
                              tooltip: 'Delete Highlight',
                              onPressed: () async {
                                await ref
                                    .read(databaseServiceProvider)
                                    .deleteHighlight(highlight.id);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Quote Block with color left border
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          decoration: BoxDecoration(
                            color: highlightColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                            border: Border(
                              left: BorderSide(
                                color: highlightColor,
                                width: 3.5,
                              ),
                            ),
                          ),
                          child: Text(
                            '"${highlight.selectedText}"',
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              height: 1.4,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),

                        // Note if present
                        if (highlight.note != null &&
                            highlight.note!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.notes,
                                  size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  highlight.note!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade800,
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
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // --- Search Section ---
  Widget _buildSearchSection() {
    final searchAsync = ref.watch(searchBooksStreamProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search by title or author...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                      },
                    )
                  : null,
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withAlpha(20)
                  : Colors.black.withAlpha(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              ref.read(searchQueryProvider.notifier).state = val;
            },
          ),
          const SizedBox(height: 20),
          Expanded(
            child: searchAsync.when(
              data: (books) {
                if (books.isEmpty) {
                  return Center(
                    child: Text(
                      'No books matching "${_searchController.text}"',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  );
                }
                return _buildBookListOrGrid(books);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  // --- Settings Section ---
  Widget _buildSettingsSection() {
    final activeTheme = ref.watch(readingThemeStateProvider);
    final typoSettings = ref.watch(typographySettingsStateProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        const Text(
          'READING PREFERENCES',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E22)
              : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                title: const Text('Default Reading Theme'),
                subtitle: Text(activeTheme.label),
                trailing: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeTheme.backgroundColor,
                    border: Border.all(color: Colors.grey),
                  ),
                ),
                onTap: () {
                  final nextIndex =
                      (activeTheme.index + 1) % ReadingThemeType.values.length;
                  ref.read(readingThemeStateProvider.notifier).state =
                      ReadingThemeType.values[nextIndex];
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Default Font Family'),
                subtitle: Text(typoSettings.fontFamily.label),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  final nextIdx = (typoSettings.fontFamily.index + 1) %
                      ReadingFontFamily.values.length;
                  ref.read(typographySettingsStateProvider.notifier).state =
                      typoSettings.copyWith(
                    fontFamily: ReadingFontFamily.values[nextIdx],
                  );
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Two-Page Spread on Mac/Desktop'),
                subtitle:
                    const Text('Display dual-page book spread on wide screens'),
                value: typoSettings.twoPageSpread,
                onChanged: (val) {
                  ref.read(typographySettingsStateProvider.notifier).state =
                      typoSettings.copyWith(twoPageSpread: val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        const Text(
          'ABOUT',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E22)
              : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              const ListTile(
                title: Text('Personal Digital Library'),
                subtitle: Text('Version 0.2.0 • Apple Books Experience'),
              ),
              const Divider(height: 1),
              const ListTile(
                title: Text('Architecture'),
                subtitle: Text(
                    'Offline-first • SQLite Drift • Pure-Dart Conversion Pipeline'),
              ),
              const Divider(height: 1),
              ListTile(
                leading:
                    const Icon(Icons.auto_stories, color: Color(0xFF007AFF)),
                title: const Text('Load Sample Book (Demo)'),
                subtitle: const Text(
                    'Import "The Adventures of Sherlock Holmes" for instant testing'),
                trailing: const Icon(Icons.download, size: 20),
                onTap: _loadSampleBook,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Dynamic Grid / List View Builder ---
  Widget _buildBookListOrGrid(
    List<Book> books, {
    Map<String, double>? progressMap,
  }) {
    final viewMode = ref.watch(libraryViewModeProvider);
    final sortOption = ref.watch(bookSortOptionProvider);

    final sorted = BookSortHelper.sortBooks(
      books,
      sortOption,
      progressMap: progressMap,
    );

    if (viewMode == LibraryViewMode.list) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final book = sorted[index];
          return BookListTile(
            book: book,
            progressPercentage: progressMap?[book.id],
            onDetails: () => _openBookDetails(book),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        int crossAxisCount = 2;
        if (width >= 1200) {
          crossAxisCount = 6;
        } else if (width >= 900) {
          crossAxisCount = 5;
        } else if (width >= 650) {
          crossAxisCount = 4;
        } else if (width >= 450) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sorted.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.58,
            crossAxisSpacing: 18,
            mainAxisSpacing: 22,
          ),
          itemBuilder: (context, index) {
            final book = sorted[index];
            return BookCard(
              book: book,
              progressPercentage: progressMap?[book.id],
              onDetails: () => _openBookDetails(book),
            );
          },
        );
      },
    );
  }

  // --- Collection Dialogs ---
  Future<void> _showCreateCollectionDialog() async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? const Color(0xFF1E1E22) : const Color(0xFFF9F9FB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(20),
          ),
        ),
        title: const Text('New Collection',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Collection Name (e.g. Science, Philosophy)',
            isDense: true,
          ),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) Navigator.of(ctx).pop(val.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final db = ref.read(databaseServiceProvider);
      final id = const Uuid().v4();
      await db.createCollection(
        CollectionsCompanion(
          id: drift.Value(id),
          name: drift.Value(name),
          createdAt: drift.Value(DateTime.now()),
        ),
      );
      setState(() {
        _selectedSection = LibraryNavigationSection.collections;
        _selectedCollectionId = id;
      });
    }
  }

  Future<void> _showRenameCollectionDialog(Collection col) async {
    final controller = TextEditingController(text: col.name);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? const Color(0xFF1E1E22) : const Color(0xFFF9F9FB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(20),
          ),
        ),
        title: const Text('Rename Collection',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(isDense: true),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) Navigator.of(ctx).pop(val.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      final db = ref.read(databaseServiceProvider);
      await db.updateCollection(col.id, name: newName);
    }
  }

  Future<void> _confirmDeleteCollection(Collection col) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? const Color(0xFF1E1E22) : const Color(0xFFF9F9FB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Collection?'),
        content: Text(
            'Are you sure you want to delete the collection "${col.name}"?\nBooks in this collection will remain in your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseServiceProvider);
      await db.deleteCollection(col.id);
      setState(() {
        _selectedCollectionId = null;
      });
    }
  }

  Future<void> _loadSampleBook() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final pipeline = ref.read(pdfProcessingPipelineProvider);
      final book =
          await SampleBookGenerator.generateAndImportSampleBook(pipeline);

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReadingScreen(
              book: book,
              initialMode: book.isScanned
                  ? ReadingMode.originalPdf
                  : ReadingMode.reflowable,
            ),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Failed to load sample book: $e\n$stack');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load sample book: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildEmptyState({required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_stories,
                size: 56,
                color: Color(0xFF007AFF),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Import PDF'),
                  onPressed: () =>
                      ImportPdfHelper.pickAndImportPdf(context, ref),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.auto_stories, size: 18),
                  label: const Text('Load Sample Book'),
                  onPressed: _loadSampleBook,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroReadingCard(BookWithProgress heroItem,
      {bool isStarted = true}) {
    final book = heroItem.book;
    final progress = heroItem.progress;
    final pct = progress?.progressPercentage ?? 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coverFile = book.coverPath != null ? File(book.coverPath!) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF232328), const Color(0xFF17171A)]
              : [const Color(0xFFFFFFFF), const Color(0xFFF6F4EF)],
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withAlpha(25)
              : Colors.black.withAlpha(15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 20),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openReader(book),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 3D Book Cover with Shadow
                Container(
                  width: 105,
                  height: 155,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(isDark ? 160 : 60),
                        blurRadius: 16,
                        offset: const Offset(4, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: (coverFile != null && coverFile.existsSync())
                        ? Image.file(coverFile, fit: BoxFit.cover)
                        : Container(
                            color: const Color(0xFF2A2A2E),
                            child: const Center(
                              child: Icon(Icons.book,
                                  size: 40, color: Color(0xFFD4AF37)),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 22),

                // Book Details & CTA
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Badge
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_stories,
                            size: 14,
                            color: Color(0xFFD4AF37),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isStarted ? 'SEDANG DIBACA' : 'REKOMENDASI BACA',
                            style: const TextStyle(
                              color: Color(0xFFD4AF37),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Title
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'serif',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Author
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Progress Bar
                      if (isStarted && pct > 0.0) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct.clamp(0.0, 1.0),
                            backgroundColor: isDark
                                ? Colors.white.withAlpha(20)
                                : Colors.black.withAlpha(15),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFD4AF37),
                            ),
                            minHeight: 5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${(pct * 100).toInt()}% Selesai • Halaman ${progress?.currentPosition ?? 1} dari ${book.totalPages}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ] else ...[
                        const SizedBox(height: 6),
                      ],

                      // CTA Button
                      FilledButton.icon(
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                          color: Colors.black,
                        ),
                        label: Text(
                          isStarted ? 'Lanjutkan Membaca' : 'Mulai Membaca',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => _openReader(book),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openReader(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReadingScreen(
          book: book,
          initialMode: book.isScanned
              ? ReadingMode.originalPdf
              : ReadingMode.reflowable,
        ),
      ),
    );
  }

  void _openBookDetails(Book book) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(120),
      builder: (_) => BookDetailsDialog(book: book),
    );
  }
}
