import 'embedding_service.dart';
import 'text_similarity_provider.dart';

/// [TextSimilarityProvider] that uses OpenAI embeddings + cosine similarity.
///
/// Falls back to [JaccardTextSimilarityProvider] if the API call fails or if
/// [apiKey] is empty.
class EmbeddingTextSimilarityProvider implements TextSimilarityProvider {
  final String _apiKey;
  final EmbeddingService _embeddingService;
  final TextSimilarityProvider _fallback;

  EmbeddingTextSimilarityProvider({
    required String apiKey,
    EmbeddingService? embeddingService,
    TextSimilarityProvider? fallback,
  })  : _apiKey = apiKey,
        _embeddingService = embeddingService ?? EmbeddingService.instance,
        _fallback = fallback ?? const JaccardTextSimilarityProvider();

  @override
  Future<double> similarity(String a, String b) async {
    if (_apiKey.isEmpty) {
      return _fallback.similarity(a, b);
    }
    try {
      final results = await Future.wait([
        _embeddingService.embed(a, _apiKey),
        _embeddingService.embed(b, _apiKey),
      ]);
      return _embeddingService.cosineSimilarity(results[0], results[1]);
    } catch (_) {
      return _fallback.similarity(a, b);
    }
  }
}
