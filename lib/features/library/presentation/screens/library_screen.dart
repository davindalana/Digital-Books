import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/theme/reading_theme.dart';
import '../../../../core/typography/typography_settings.dart';
import '../../../reader/providers/reader_settings_provider.dart';
import '../widgets/book_card.dart';
import '../widgets/book_details_dialog.dart';
import '../widgets/import_pdf_dialog.dart';
import '../../../../core/utils/sample_book_generator.dart';
import '../../../processing/providers/import_provider.dart';
import '../../../reader/presentation/screens/reading_screen.dart';

enum LibraryNavigationSection {
  home('Reading Now', Icons.auto_stories),
  allBooks('All Books', Icons.library_books),
  currentlyReading('Currently Reading', Icons.bookmark_added),
  finished('Finished', Icons.check_circle_outline),
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
          width: 240,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => ImportPdfHelper.pickAndImportPdf(context, ref),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      _buildSidebarItem(LibraryNavigationSection.home),
                      _buildSidebarItem(LibraryNavigationSection.allBooks),
                      _buildSidebarItem(LibraryNavigationSection.currentlyReading),
                      _buildSidebarItem(LibraryNavigationSection.finished),
                      _buildSidebarItem(LibraryNavigationSection.search),
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

  Widget _buildSidebarItem(LibraryNavigationSection section) {
    final isSelected = _selectedSection == section;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _selectedSection = section;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? Colors.white.withAlpha(30) : const Color(0xFFE5E5EA))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                section.icon,
                size: 18,
                color: isSelected ? const Color(0xFF007AFF) : Colors.grey.shade500,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        children: [
          Flexible(
            child: Text(
              _selectedSection.label,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          if (_selectedSection != LibraryNavigationSection.search)
            SizedBox(
              width: 180,
              height: 36,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search Library',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withAlpha(20)
                      : Colors.black.withAlpha(10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
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
        ],
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
                Text(
                  _selectedSection.label,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Color(0xFF007AFF), size: 28),
                  onPressed: () => ImportPdfHelper.pickAndImportPdf(context, ref),
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
              break;
            case 1:
              _selectedSection = LibraryNavigationSection.allBooks;
              break;
            case 2:
              _selectedSection = LibraryNavigationSection.search;
              break;
            case 3:
              _selectedSection = LibraryNavigationSection.settings;
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
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: 'Search',
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
      case LibraryNavigationSection.search:
        return 2;
      case LibraryNavigationSection.settings:
        return 3;
    }
  }

  // --- 3. Section Content Routing ---
  Widget _buildSectionContent() {
    switch (_selectedSection) {
      case LibraryNavigationSection.home:
        return _buildHomeSection();
      case LibraryNavigationSection.allBooks:
        return _buildAllBooksGrid();
      case LibraryNavigationSection.currentlyReading:
        return _buildCurrentlyReadingGrid();
      case LibraryNavigationSection.finished:
        return _buildFinishedBooksGrid();
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
                      separatorBuilder: (context, index) => const SizedBox(width: 18),
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
            return _buildResponsiveGrid(books);
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

  // --- All Books Grid ---
  Widget _buildAllBooksGrid() {
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
          child: _buildResponsiveGrid(books),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // --- Currently Reading Grid ---
  Widget _buildCurrentlyReadingGrid() {
    final readingAsync = ref.watch(currentlyReadingStreamProvider);

    return readingAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState(
            title: 'No Books Currently In Progress',
            subtitle: 'Start reading any book from your library to track progress.',
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: _buildResponsiveGrid(items.map((i) => i.book).toList()),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // --- Finished Books Grid ---
  Widget _buildFinishedBooksGrid() {
    final finishedAsync = ref.watch(finishedBooksStreamProvider);

    return finishedAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState(
            title: 'No Finished Books Yet',
            subtitle: 'Books you finish will be archived here.',
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: _buildResponsiveGrid(items.map((i) => i.book).toList()),
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
                return _buildResponsiveGrid(books);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  // Cycle theme
                  final nextIndex = (activeTheme.index + 1) % ReadingThemeType.values.length;
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
                subtitle: const Text('Display dual-page book spread on wide screens'),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              const ListTile(
                title: Text('Personal Digital Library'),
                subtitle: Text('Version 1.0.0 • Apple Books Experience'),
              ),
              const Divider(height: 1),
              const ListTile(
                title: Text('Architecture'),
                subtitle: Text('Offline-first • SQLite Drift • Pure-Dart Conversion Pipeline'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.auto_stories, color: Color(0xFF007AFF)),
                title: const Text('Load Sample Book (Demo)'),
                subtitle: const Text('Import "The Adventures of Sherlock Holmes" for instant testing'),
                trailing: const Icon(Icons.download, size: 20),
                onTap: _loadSampleBook,
              ),
            ],
          ),
        ),
      ],
    );
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
      final book = await SampleBookGenerator.generateAndImportSampleBook(pipeline);

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

  // --- Responsive Grid Helper ---
  Widget _buildResponsiveGrid(List<Book> books) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute responsive column count
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
          itemCount: books.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.58, // 2:3 book cover + title/author text
            crossAxisSpacing: 18,
            mainAxisSpacing: 22,
          ),
          itemBuilder: (context, index) {
            final book = books[index];
            return BookCard(
              book: book,
              onDetails: () => _openBookDetails(book),
            );
          },
        );
      },
    );
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Import PDF'),
                  onPressed: () => ImportPdfHelper.pickAndImportPdf(context, ref),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  Widget _buildHeroReadingCard(BookWithProgress heroItem, {bool isStarted = true}) {
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
                              child: Icon(Icons.book, size: 40, color: Color(0xFFD4AF37)),
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
