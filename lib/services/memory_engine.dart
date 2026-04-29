import 'dart:async';
import 'dart:math';
import '../models/note.dart';
import '../models/excerpt_result.dart';
import '../models/search_state.dart';
import 'database_service.dart';
import 'embedding_service.dart';
import 'ai_service.dart';

class MemoryEngine {
  MemoryEngine._();
  static final MemoryEngine instance = MemoryEngine._();

  static const int _maxResults = 10;

  Future<SearchState> search(
    String query,
    String? apiKey,
    double threshold, {
    void Function(String aiResponse)? onAiResponse,
    bool aiEnabled = true,
    int maxTokens = 120,
  }) async {
    if (query.trim().isEmpty) {
      return const SearchState();
    }

    // LAYER 1 + 2: Run in parallel
    final ftsResultsFuture = _runFts(query);
    final semanticResultsFuture = (apiKey != null && apiKey.isNotEmpty)
        ? _runSemantic(query, apiKey)
        : Future.value(<_SemanticResult>[]);

    final results = await Future.wait([ftsResultsFuture, semanticResultsFuture]);
    final ftsResults = results[0] as List<_FtsResult>;
    final semanticResults = results[1] as List<_SemanticResult>;

    // LAYER 3: Combined ranking + excerpt extraction
    final combined = _combineAndRank(ftsResults, semanticResults, threshold);
    final excerpts = _extractExcerpts(combined, query);

    final memoryResults = excerpts.where((e) => e.showInMemorySection).toList();
    final noteResults = excerpts
        .where((e) => !e.showInMemorySection && e.similarityScore >= 0.60)
        .map((e) => e.note)
        .toList();

    final state = SearchState(
      query: query,
      memoryResults: memoryResults,
      noteResults: noteResults,
      isSearching: false,
      isAiLoading: aiEnabled && apiKey != null && apiKey.isNotEmpty,
    );

    // LAYER 4: AI response fires async
    if (aiEnabled && apiKey != null && apiKey.isNotEmpty) {
      AiService.instance
          .getResponse(
        query: query,
        excerpts: excerpts.take(5).toList(),
        apiKey: apiKey,
        maxTokens: maxTokens,
      )
          .then((aiResponse) {
        onAiResponse?.call(aiResponse);
      }).catchError((_) {
        onAiResponse?.call('Unable to load AI response.');
      });
    }

    return state;
  }

  Future<List<_FtsResult>> _runFts(String query) async {
    try {
      final rows = await DatabaseService.instance.searchFts(query);
      return rows.map((row) {
        final note = Note.fromMap(row);
        final rank = (row['fts_rank'] as num?)?.toDouble() ?? 0.0;
        // BM25 returns negative values; normalize to [0,1]
        final normalizedRank = rank < 0 ? min(1.0, (-rank) / 10.0) : 0.0;
        return _FtsResult(note: note, rank: normalizedRank);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<_SemanticResult>> _runSemantic(String query, String apiKey) async {
    try {
      final queryEmbedding = await EmbeddingService.instance.embed(query, apiKey);
      final allNotes = await DatabaseService.instance.getAllNotesWithEmbeddings();
      final results = <_SemanticResult>[];
      for (final note in allNotes) {
        if (note.embedding != null) {
          final score = EmbeddingService.instance.cosineSimilarity(queryEmbedding, note.embedding!);
          results.add(_SemanticResult(note: note, score: score));
        }
      }
      results.sort((a, b) => b.score.compareTo(a.score));
      return results;
    } catch (_) {
      return [];
    }
  }

  List<ExcerptResult> _combineAndRank(
    List<_FtsResult> ftsResults,
    List<_SemanticResult> semanticResults,
    double threshold,
  ) {
    final Map<String, double> semanticScores = {
      for (final r in semanticResults) r.note.id: r.score,
    };
    final Map<String, double> ftsScores = {
      for (final r in ftsResults) r.note.id: r.rank,
    };

    // Collect all unique note IDs
    final allIds = {...semanticScores.keys, ...ftsScores.keys};
    final Map<String, Note> noteMap = {};
    for (final r in semanticResults) noteMap[r.note.id] = r.note;
    for (final r in ftsResults) noteMap[r.note.id] = r.note;

    final scored = <_RankedResult>[];
    for (final id in allIds) {
      final semanticScore = semanticScores[id] ?? 0.0;
      final ftsScore = ftsScores[id] ?? 0.0;
      final combined = 0.6 * semanticScore + 0.4 * ftsScore;
      // Include if combined score meets threshold OR if semantic score alone meets it.
      // Spec: threshold applies to semantic similarity. High semantic match
      // should always surface even if FTS score is 0 (no shared keywords).
      // This is the core "zero shared keywords" use case of the Memory Engine.
      if (combined >= threshold || semanticScore >= threshold) {
        scored.add(_RankedResult(
          note: noteMap[id]!,
          semanticScore: semanticScore,
          ftsScore: ftsScore,
          combinedScore: max(combined, semanticScore),
        ));
      }
    }

    scored.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));
    return scored.take(_maxResults).map((r) => ExcerptResult(
      note: r.note,
      excerptText: '',
      similarityScore: r.combinedScore,
      keywordHighlights: const [],
      highlightedWords: const [],
    )).toList();
  }

  List<ExcerptResult> _extractExcerpts(List<ExcerptResult> results, String query) {
    return results.map((r) {
      final excerpt = EmbeddingService.instance.extractExcerpt(r.note.content, query);
      final highlights = EmbeddingService.instance.extractKeywordHighlights(query, r.note);
      return r.copyWith(
        excerptText: excerpt,
        keywordHighlights: highlights,
        highlightedWords: highlights,
      );
    }).toList();
  }
}

class _FtsResult {
  final Note note;
  final double rank;
  const _FtsResult({required this.note, required this.rank});
}

class _SemanticResult {
  final Note note;
  final double score;
  const _SemanticResult({required this.note, required this.score});
}

class _RankedResult {
  final Note note;
  final double semanticScore;
  final double ftsScore;
  final double combinedScore;
  const _RankedResult({
    required this.note,
    required this.semanticScore,
    required this.ftsScore,
    required this.combinedScore,
  });
}
