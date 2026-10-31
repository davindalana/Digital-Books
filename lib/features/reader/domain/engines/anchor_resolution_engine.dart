import 'dart:math' as math;
import '../models/reader_content.dart';

enum AnchorResolutionStatus {
  exact,
  contextMatch,
  offsetShifted,
  nodeRelocated,
  unresolved,
}

class AnchorResolutionResult {
  final bool isResolved;
  final String? resolvedNodeId;
  final int resolvedStartOffset;
  final int resolvedEndOffset;
  final double confidence;
  final AnchorResolutionStatus status;

  const AnchorResolutionResult({
    required this.isResolved,
    this.resolvedNodeId,
    this.resolvedStartOffset = 0,
    this.resolvedEndOffset = 0,
    required this.confidence,
    required this.status,
  });

  static const AnchorResolutionResult unresolvedResult = AnchorResolutionResult(
    isResolved: false,
    confidence: 0.0,
    status: AnchorResolutionStatus.unresolved,
  );
}

class AnchorResolutionEngine {
  /// Resolves an annotation's target position against document content nodes.
  static AnchorResolutionResult resolveAnchor({
    required ReaderDocument document,
    required String? chapterId,
    required String? anchorNodeId,
    required String selectedText,
    required int startOffset,
    required int endOffset,
    String? prefixContext,
    String? suffixContext,
  }) {
    if (selectedText.trim().isEmpty) {
      return AnchorResolutionResult.unresolvedResult;
    }

    final trimmedTarget = selectedText.trim();

    // 1. Locate chapter
    ReaderChapter? targetChapter;
    if (chapterId != null && chapterId.isNotEmpty) {
      for (final ch in document.chapters) {
        if (ch.id == chapterId) {
          targetChapter = ch;
          break;
        }
      }
    }
    targetChapter ??= document.chapters.isNotEmpty ? document.chapters.first : null;

    if (targetChapter == null) {
      return AnchorResolutionResult.unresolvedResult;
    }

    // 2. Locate target node
    ContentNode? targetNode;
    if (anchorNodeId != null && anchorNodeId.isNotEmpty) {
      for (final node in targetChapter.nodes) {
        if (node.id == anchorNodeId) {
          targetNode = node;
          break;
        }
      }
    }

    // 3. If target node found, check exact offset
    if (targetNode != null) {
      final text = targetNode.text;
      final safeStart = startOffset.clamp(0, text.length);
      final safeEnd = endOffset.clamp(safeStart, text.length);

      if (safeEnd > safeStart) {
        final candidate = text.substring(safeStart, safeEnd).trim();
        if (candidate == trimmedTarget) {
          return AnchorResolutionResult(
            isResolved: true,
            resolvedNodeId: targetNode.id,
            resolvedStartOffset: safeStart,
            resolvedEndOffset: safeEnd,
            confidence: 1.0,
            status: AnchorResolutionStatus.exact,
          );
        }
      }

      // 4. Context recovery in target node: prefix + target + suffix
      if (prefixContext != null && suffixContext != null) {
        final combined = '$prefixContext$selectedText$suffixContext';
        final combinedIdx = text.indexOf(combined);
        if (combinedIdx != -1) {
          final resolvedStart = combinedIdx + prefixContext.length;
          final resolvedEnd = resolvedStart + selectedText.length;
          return AnchorResolutionResult(
            isResolved: true,
            resolvedNodeId: targetNode.id,
            resolvedStartOffset: resolvedStart,
            resolvedEndOffset: resolvedEnd,
            confidence: 0.95,
            status: AnchorResolutionStatus.contextMatch,
          );
        }
      }

      // 5. Offset-shifted search in target node: find nearest occurrence of selectedText
      final occurrences = _findAllOccurrences(text, trimmedTarget);
      if (occurrences.isNotEmpty) {
        // Choose occurrence closest to original startOffset
        int bestStart = occurrences.first;
        int minDistance = (bestStart - startOffset).abs();
        for (final occ in occurrences) {
          final dist = (occ - startOffset).abs();
          if (dist < minDistance) {
            minDistance = dist;
            bestStart = occ;
          }
        }
        return AnchorResolutionResult(
          isResolved: true,
          resolvedNodeId: targetNode.id,
          resolvedStartOffset: bestStart,
          resolvedEndOffset: bestStart + trimmedTarget.length,
          confidence: 0.85,
          status: AnchorResolutionStatus.offsetShifted,
        );
      }
    }

    // 6. Chapter-wide search across nodes (node relocated or renamed)
    for (final node in targetChapter.nodes) {
      if (node.id == anchorNodeId) continue; // Already checked
      final text = node.text;
      final occurrences = _findAllOccurrences(text, trimmedTarget);
      if (occurrences.isNotEmpty) {
        // Check if prefix or suffix matches
        bool contextMatched = false;
        int chosenStart = occurrences.first;

        if (prefixContext != null && prefixContext.isNotEmpty) {
          for (final occ in occurrences) {
            final testPrefixStart = math.max(0, occ - prefixContext.length);
            final testPrefix = text.substring(testPrefixStart, occ);
            if (prefixContext.endsWith(testPrefix) || testPrefix.endsWith(prefixContext)) {
              chosenStart = occ;
              contextMatched = true;
              break;
            }
          }
        }

        return AnchorResolutionResult(
          isResolved: true,
          resolvedNodeId: node.id,
          resolvedStartOffset: chosenStart,
          resolvedEndOffset: chosenStart + trimmedTarget.length,
          confidence: contextMatched ? 0.75 : 0.60,
          status: AnchorResolutionStatus.nodeRelocated,
        );
      }
    }

    // 7. Unresolved
    return AnchorResolutionResult.unresolvedResult;
  }

  static List<int> _findAllOccurrences(String source, String query) {
    if (query.isEmpty) return const [];
    final indices = <int>[];
    int start = 0;
    while (start < source.length) {
      final idx = source.indexOf(query, start);
      if (idx == -1) break;
      indices.add(idx);
      start = idx + query.length;
    }
    return indices;
  }
}
