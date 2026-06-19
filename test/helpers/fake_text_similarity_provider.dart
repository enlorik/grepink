import 'package:grepink/services/text_similarity_provider.dart';

/// Test-only similarity provider that always returns a fixed score.
class FakeTextSimilarityProvider implements TextSimilarityProvider {
  final double _score;

  const FakeTextSimilarityProvider(this._score);

  @override
  Future<double> similarity(String a, String b) async => _score;
}

/// Test-only provider that returns 1.0 for exact string matches, 0.0 otherwise.
///
/// Use this when a test needs to prove that chunking is working: the claim
/// text is compared against individual sentence chunks, so an exact match on
/// one chunk should yield a high score even when the full note body would score
/// low against the same claim.
class ExactMatchFakeTextSimilarityProvider implements TextSimilarityProvider {
  const ExactMatchFakeTextSimilarityProvider();

  @override
  Future<double> similarity(String a, String b) async =>
      a.trim() == b.trim() ? 1.0 : 0.0;
}
