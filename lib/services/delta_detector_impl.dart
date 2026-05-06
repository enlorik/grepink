import '../models/evidence_item.dart';
import '../models/knowledge_delta.dart';
import 'delta_detector.dart';
import 'text_chunker.dart';
import 'text_similarity_provider.dart';

// ---------------------------------------------------------------------------
// Classification thresholds
// ---------------------------------------------------------------------------

/// Semantic similarity at or above this value → classified as [DeltaType.duplicate].
const double kDuplicateSimilarityThreshold = 0.88;

/// Semantic similarity at or above this value → classified as [DeltaType.relatedButNew].
/// Scores below this produce [DeltaType.newClaim].
const double kRelatedSimilarityThreshold = 0.72;

// ---------------------------------------------------------------------------

class DeltaDetectorImpl implements DeltaDetector {
  final TextSimilarityProvider _similarityProvider;
  final TextChunker _chunker;

  DeltaDetectorImpl({
    TextSimilarityProvider? similarityProvider,
    TextChunker? chunker,
  })  : _similarityProvider = similarityProvider ?? const JaccardTextSimilarityProvider(),
        _chunker = chunker ?? TextChunker();

  @override
  Future<List<KnowledgeDelta>> detect(
    List<EvidenceItem> localEvidence,
    List<EvidenceItem> incomingEvidence,
  ) async {
    // Pre-compute chunks for all local evidence so we compare incoming items
    // against individual paragraphs, not full (possibly long) note bodies.
    final localChunks = localEvidence.expand((item) => _chunker.chunk(item)).toList();

    final results = <KnowledgeDelta>[];
    for (final item in incomingEvidence) {
      results.add(await _classify(item, localEvidence, localChunks));
    }
    return results;
  }

  Future<KnowledgeDelta> _classify(
    EvidenceItem incoming,
    List<EvidenceItem> localItems,
    List<TextChunk> localChunks,
  ) async {
    // ---- 1. Fast exact-text match (case-insensitive, trimmed) ---------------
    if (isExactDuplicate(
        incoming.content, localItems.map((e) => e.content).toList())) {
      final bestLocal = _findBestLocalForExact(incoming.content, localItems);
      final localHasSource = bestLocal?.sourceUrl != null;
      final incomingHasSource = incoming.sourceUrl != null;

      if (incomingHasSource && !localHasSource && bestLocal != null) {
        return KnowledgeDelta(
          evidence: incoming,
          deltaType: DeltaType.betterSource,
          existingNoteId: bestLocal.sourceNoteId,
          reason: 'Exact text match found in existing note but the local note '
              'has no source URL; incoming evidence adds a source.',
          bestSimilarityScore: 1.0,
        );
      }

      return KnowledgeDelta(
        evidence: incoming,
        deltaType: DeltaType.duplicate,
        existingNoteId: bestLocal?.sourceNoteId,
        reason: 'Exact text match found in local notes.',
        bestSimilarityScore: 1.0,
      );
    }

    // ---- 2. No local content to compare against ----------------------------
    if (localChunks.isEmpty) {
      return KnowledgeDelta(
        evidence: incoming,
        deltaType: DeltaType.newClaim,
        reason: 'No local notes exist to compare against.',
      );
    }

    // ---- 3. Semantic similarity against local chunks -----------------------
    double bestScore = 0.0;
    TextChunk? bestChunk;

    for (final chunk in localChunks) {
      final score = await _similarityProvider.similarity(
          incoming.content, chunk.content);
      if (score > bestScore) {
        bestScore = score;
        bestChunk = chunk;
      }
    }

    // ---- 4. Classify based on thresholds -----------------------------------
    if (bestScore >= kDuplicateSimilarityThreshold) {
      // Check if incoming adds a source URL that the best-matching local note lacks.
      final incomingHasSource = incoming.sourceUrl != null;
      final localChunkHasSource = bestChunk?.sourceUrl != null;
      if (incomingHasSource && !localChunkHasSource) {
        return KnowledgeDelta(
          evidence: incoming,
          deltaType: DeltaType.betterSource,
          existingNoteId: bestChunk?.sourceNoteId,
          reason: 'Semantically duplicate '
              '(${(bestScore * 100).toStringAsFixed(0)}%) but incoming evidence '
              'adds a source URL the existing note lacks.',
          bestSimilarityScore: bestScore,
        );
      }

      return KnowledgeDelta(
        evidence: incoming,
        deltaType: DeltaType.duplicate,
        existingNoteId: bestChunk?.sourceNoteId,
        reason:
            'High semantic similarity (${(bestScore * 100).toStringAsFixed(0)}%) '
            'with existing note.',
        bestSimilarityScore: bestScore,
      );
    }

    if (bestScore >= kRelatedSimilarityThreshold) {
      return KnowledgeDelta(
        evidence: incoming,
        deltaType: DeltaType.relatedButNew,
        existingNoteId: bestChunk?.sourceNoteId,
        reason: 'Related to existing note '
            '(${(bestScore * 100).toStringAsFixed(0)}% similarity) '
            'but contains new wording or perspective.',
        bestSimilarityScore: bestScore,
      );
    }

    return KnowledgeDelta(
      evidence: incoming,
      deltaType: DeltaType.newClaim,
      reason: 'No sufficiently similar local note found; '
          'this appears to be new knowledge.',
      bestSimilarityScore: bestScore,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns true when [text] is an exact (case-insensitive, trimmed) match
  /// to any entry in [candidates].
  bool isExactDuplicate(String text, List<String> candidates) {
    final normalized = text.trim().toLowerCase();
    return candidates.any((c) => c.trim().toLowerCase() == normalized);
  }

  /// Jaccard similarity convenience method kept for backward compatibility.
  double jaccardSimilarity(String a, String b) {
    final setA = _tokenize(a);
    final setB = _tokenize(b);
    if (setA.isEmpty && setB.isEmpty) return 1.0;
    if (setA.isEmpty || setB.isEmpty) return 0.0;
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return intersection / union;
  }

  /// Returns the local item whose content exactly matches [text], or null.
  EvidenceItem? _findBestLocalForExact(
      String text, List<EvidenceItem> localItems) {
    final normalized = text.trim().toLowerCase();
    try {
      return localItems.firstWhere(
          (e) => e.content.trim().toLowerCase() == normalized);
    } catch (_) {
      return null;
    }
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

