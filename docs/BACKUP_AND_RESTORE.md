# Backup & Disaster Recovery Guide • Digital Books v1.1.0-alpha.8 (build 9)

This guide explains the data architecture, backup formats, conflict resolution policies, and disaster recovery procedures in Digital Books.

---

## 1. Backup Formats Explained

Digital Books offers two distinct export formats tailored for different storage and migration needs:

### A. Library Metadata Export (`.json`)
- **What it contains**:
  - Book metadata (Title, Author, Description, Total Pages, SHA-256 File Checksums).
  - Exact reading progress per layout mode (Paginated vs Scrolling), reading percentage, and timestamps (`lastReadAt`).
  - All User Annotations: Bookmarks, Highlights with color codes, and Notes.
  - User Collections & Book-to-Collection mappings.
  - Reader Preferences (Theme, Typography, Font Size, Spread settings).
- **File size**: Typically between **50 KB and 2 MB** depending on library size.
- **What it does NOT contain**: The original binary PDF files.
- **Best for**: Routine daily backups, syncing reading annotations between Macs where PDFs are already stored in iCloud Drive / Dropbox, or archiving reading notes.

### B. Full Library Bundle (`.bundle` / Directory)
- **What it contains**:
  - `manifest.json`: Complete library metadata, progress, and annotations (identical to format A).
  - `originals/`: Physical copies of all active PDF documents currently imported into your library.
- **File size**: Proportional to your total PDF collection size (typically several hundred megabytes to gigabytes).
- **Best for**: Complete offline disaster recovery, moving to a brand-new Mac without needing to manually relink or locate original PDF files.

---

## 2. Restore Conflict Resolution Strategies

When restoring a backup into a library that already contains books, Digital Books offers two strategies to guarantee zero accidental data loss:

### 1. Skip Existing (`skipExisting`)
- Existing books and their current reading positions and annotations remain completely untouched.
- Only newly discovered books in the backup file are inserted into the database.
- Recommended when importing a secondary backup or shared reading list without modifying current reading sessions.

### 2. Merge & Update Existing (`mergeUpdateExisting`)
- **Monotonic Progress Protection (`lastReadAt`)**:
  - The restore engine compares the backup's `lastReadAt` timestamp against the local book's `lastReadAt` timestamp.
  - If the local reading session is newer than the backup record, **the local reading position is preserved**. Your recent reading progress is never overwritten by an older backup file.
  - If the backup reading timestamp is newer, the reading position is safely updated.
- **Non-Destructive Annotation Merging**:
  - Bookmarks are merged using duplicate prevention (no identical chapter/paragraph bookmarks created).
  - Highlights and Notes are deduplicated and merged. Any new highlights from the backup are added to your existing notes without deleting locally created annotations.
- **Collection Associations**: Existing collection memberships are preserved; any new collection tags from the backup are attached.

---

## 3. Atomic Database Transactions

Every restore operation in Digital Books is executed inside a single, strict **Drift / SQLite Transaction**:
```dart
await db.transaction(() async {
  // Validate schema version
  // Process collections
  // Process books, progress, bookmarks, highlights, notes
  // If any single error occurs -> AUTOMATIC ROLLBACK
});
```
- If a backup file is malformed, corrupted midway, or terminated abruptly, SQLite immediately rolls back all partial inserts.
- **Guarantee**: The database is never left in an inconsistent, partially imported, or corrupted state.

---

## 4. Recovering Moved or Missing PDF Files

If a source PDF file was moved, renamed, or restored onto a machine with a different folder hierarchy:
1. Digital Books flags the book with a **"Source PDF Missing"** indicator.
2. Clicking **Relink PDF** opens a native macOS file dialog.
3. Upon selecting a new PDF:
   - Digital Books calculates the **SHA-256 checksum** of the candidate file.
   - **Matching Checksum**: The path is instantly updated, and all existing highlights, bookmarks, and reading progress align with 100% precision.
   - **Mismatched Checksum**: If the content does not match (different edition or modified PDF), an informative alert is displayed warning the user that annotations may need anchor re-alignment.

