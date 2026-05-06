import 'embedding_service.dart';
import 'text_similarity_provider.dart';

/// [TextSimilarityProvider] that uses OpenAI embeddings + cosine similarity.
///
/// Falls back to [JaccardTextSimilarityProvider] if the API call fails or if
/// [apiKey] is empty.
///
/// Embeddings are cached in memory (keyed by exact input text) to avoid
/// redundant API calls when the same text is compared multiple times.
class EmbeddingTextSimilarityProvider implements TextSimilarityProvider {
  final String _apiKey;
  final EmbeddingService _embeddingService;
  final TextSimilarityProvider _fallback;
  final Map<String, Future<List<double>>> _cache = {};

  EmbeddingTextSimilarityProvider({
    required String apiKey,
    EmbeddingService? embeddingService,
    TextSimilarityProvider? fallback,
  })  : _apiKey = apiKey,
        _embeddingService = embeddingService ?? EmbeddingService.instance,
        _fallback = fallback ?? const JaccardTextSimilarityProvider();

  Future<List<double>> _embed(String text) =>
      _cache.putIfAbsent(text, () => _embeddingService.embed(text, _apiKey));

  @override
  Future<double> similarity(String a, String b) async {
    if (_apiKey.isEmpty) {
      return _fallback.similarity(a, b);
    }
    try {
      final results = await Future.wait([_embed(a), _embed(b)]);
      return _embeddingService.cosineSimilarity(results[0], results[1]);
    } catch (_) {
      return _fallback.similarity(a, b);
    }
  }
}
