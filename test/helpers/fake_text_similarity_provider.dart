import 'package:grepink/services/text_similarity_provider.dart';

/// Test-only similarity provider that always returns a fixed score.
class FakeTextSimilarityProvider implements TextSimilarityProvider {
  final double _score;

  const FakeTextSimilarityProvider(this._score);

  @override
  Future<double> similarity(String a, String b) async => _score;
}
