/// Abstraction for computing semantic/textual similarity between two strings.
///
/// Swap implementations to upgrade from word-overlap to real embeddings
/// without touching [DeltaDetectorImpl].
abstract class TextSimilarityProvider {
  Future<double> similarity(String a, String b);
}

/// Jaccard word-set similarity: |intersection| / |union| of word sets.
///
/// Used as a fast, dependency-free fallback when no API key is available.
class JaccardTextSimilarityProvider implements TextSimilarityProvider {
  const JaccardTextSimilarityProvider();

  @override
  Future<double> similarity(String a, String b) async {
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

// FakeTextSimilarityProvider has been moved to test/helpers/fake_text_similarity_provider.dart.
// It is test/demo-only and should not be used in production code.
