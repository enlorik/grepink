import '../models/evidence_item.dart';
import '../models/knowledge_delta.dart';
import 'delta_detector.dart';

/// Threshold above which two pieces of text are considered duplicate.
const double _kDuplicateThreshold = 0.9;

/// Threshold above which two pieces of text are considered related but new.
const double _kRelatedThreshold = 0.3;

class DeltaDetectorImpl implements DeltaDetector {
  @override
  Future<List<KnowledgeDelta>> detect(
    List<EvidenceItem> localEvidence,
    List<EvidenceItem> incomingEvidence,
  ) async {
    return incomingEvidence
        .map((item) => _classify(item, localEvidence))
        .toList();
  }

  KnowledgeDelta _classify(
    EvidenceItem incoming,
    List<EvidenceItem> local,
  ) {
    if (local.isEmpty) {
      return KnowledgeDelta(
        evidence: incoming,
        deltaType: DeltaType.newClaim,
        reason: 'No local notes exist to compare against.',
      );
    }

    double bestScore = 0.0;
    String? bestNoteId;

    for (final localItem in local) {
      final score = _jaccardSimilarity(incoming.content, localItem.content);
      if (score > bestScore) {
        bestScore = score;
        bestNoteId = localItem.sourceNoteId;
      }
    }

    if (isExactDuplicate(incoming.content, local.map((e) => e.content).toList())) {
      return KnowledgeDelta(
        evidence: incoming,
        deltaType: DeltaType.duplicate,
        existingNoteId: bestNoteId,
        reason: 'Exact text match found in local notes.',
      );
    }

    if (bestScore >= _kDuplicateThreshold) {
      return KnowledgeDelta(
        evidence: incoming,
        deltaType: DeltaType.duplicate,
        existingNoteId: bestNoteId,
        reason: 'High similarity (${(bestScore * 100).toStringAsFixed(0)}%) with existing note.',
      );
    }

    if (bestScore >= _kRelatedThreshold) {
      return KnowledgeDelta(
        evidence: incoming,
        deltaType: DeltaType.relatedButNew,
        existingNoteId: bestNoteId,
        reason:
            'Related to existing note (${(bestScore * 100).toStringAsFixed(0)}% overlap) '
            'but contains new wording or perspective.',
      );
    }

    return KnowledgeDelta(
      evidence: incoming,
      deltaType: DeltaType.newClaim,
      reason: 'No sufficiently similar local note found; this appears to be new knowledge.',
    );
  }

  /// Returns true when [text] is an exact (case-insensitive, trimmed) match
  /// to any entry in [candidates].
  bool isExactDuplicate(String text, List<String> candidates) {
    final normalized = text.trim().toLowerCase();
    return candidates.any((c) => c.trim().toLowerCase() == normalized);
  }

  /// Jaccard similarity between two texts: |intersection| / |union| of word sets.
  ///
  /// Used as a placeholder until real embedding similarity is available.
  double jaccardSimilarity(String a, String b) => _jaccardSimilarity(a, b);

  double _jaccardSimilarity(String a, String b) {
    final setA = _tokenize(a);
    final setB = _tokenize(b);
    if (setA.isEmpty && setB.isEmpty) return 1.0;
    if (setA.isEmpty || setB.isEmpty) return 0.0;
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return intersection / union;
  }

  Set<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toSet();
  }
}
