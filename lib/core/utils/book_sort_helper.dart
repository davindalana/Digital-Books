import '../database/app_database.dart';
import '../database/database_service.dart';
import '../providers/database_providers.dart';

class BookSortHelper {
  static List<Book> sortBooks(
    List<Book> books,
    BookSortOption sortOption, {
    Map<String, double>? progressMap,
  }) {
    final list = List<Book>.from(books);
    switch (sortOption) {
      case BookSortOption.titleAsc:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case BookSortOption.titleDesc:
        list.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case BookSortOption.authorAsc:
        list.sort((a, b) {
          final authorComp = a.author.toLowerCase().compareTo(
            b.author.toLowerCase(),
          );
          if (authorComp != 0) return authorComp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
      case BookSortOption.dateAddedDesc:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case BookSortOption.dateAddedAsc:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case BookSortOption.progressDesc:
        list.sort((a, b) {
          final pA = progressMap?[a.id] ?? 0.0;
          final pB = progressMap?[b.id] ?? 0.0;
          final pComp = pB.compareTo(pA);
          if (pComp != 0) return pComp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
      case BookSortOption.progressAsc:
        list.sort((a, b) {
          final pA = progressMap?[a.id] ?? 0.0;
          final pB = progressMap?[b.id] ?? 0.0;
          final pComp = pA.compareTo(pB);
          if (pComp != 0) return pComp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
    }
    return list;
  }

  static List<BookWithProgress> sortBooksWithProgress(
    List<BookWithProgress> items,
    BookSortOption sortOption,
  ) {
    final list = List<BookWithProgress>.from(items);
    switch (sortOption) {
      case BookSortOption.titleAsc:
        list.sort(
          (a, b) =>
              a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase()),
        );
        break;
      case BookSortOption.titleDesc:
        list.sort(
          (a, b) =>
              b.book.title.toLowerCase().compareTo(a.book.title.toLowerCase()),
        );
        break;
      case BookSortOption.authorAsc:
        list.sort((a, b) {
          final comp = a.book.author.toLowerCase().compareTo(
            b.book.author.toLowerCase(),
          );
          if (comp != 0) return comp;
          return a.book.title.toLowerCase().compareTo(
            b.book.title.toLowerCase(),
          );
        });
        break;
      case BookSortOption.dateAddedDesc:
        list.sort((a, b) => b.book.createdAt.compareTo(a.book.createdAt));
        break;
      case BookSortOption.dateAddedAsc:
        list.sort((a, b) => a.book.createdAt.compareTo(b.book.createdAt));
        break;
      case BookSortOption.progressDesc:
        list.sort((a, b) {
          final pA = a.progress?.progressPercentage ?? 0.0;
          final pB = b.progress?.progressPercentage ?? 0.0;
          final comp = pB.compareTo(pA);
          if (comp != 0) return comp;
          return a.book.title.toLowerCase().compareTo(
            b.book.title.toLowerCase(),
          );
        });
        break;
      case BookSortOption.progressAsc:
        list.sort((a, b) {
          final pA = a.progress?.progressPercentage ?? 0.0;
          final pB = b.progress?.progressPercentage ?? 0.0;
          final comp = pA.compareTo(pB);
          if (comp != 0) return comp;
          return a.book.title.toLowerCase().compareTo(
            b.book.title.toLowerCase(),
          );
        });
        break;
    }
    return list;
  }
}
