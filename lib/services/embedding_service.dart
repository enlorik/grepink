import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/note.dart';

class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService instance = EmbeddingService._();

  static const String _model = 'text-embedding-3-small';
  static const int _dimensions = 1536;

  Future<List<double>> embed(String text, String apiKey) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/embeddings'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'input': text,
        'dimensions': _dimensions,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Embedding API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final embedding = (data['data'] as List).first['embedding'] as List;
    return embedding.map((e) => (e as num).toDouble()).toList();
  }

  Future<List<double>> embedNote(Note note, String apiKey) async {
    return embed(note.embeddingText, apiKey);
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = sqrt(normA) * sqrt(normB);
    if (denom == 0) return 0.0;
    return dot / denom;
  }

  String extractExcerpt(String content, String query, {int windowSize = 200}) {
    if (content.isEmpty) return '';
    if (content.length <= windowSize) return content;
    if (query.isEmpty) {
      return '${content.substring(0, windowSize)}...';
    }

    final queryWords = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    if (queryWords.isEmpty) {
      return '${content.substring(0, windowSize)}...';
    }

    final lowerContent = content.toLowerCase();
    int bestStart = 0;
    int bestScore = 0;

    final maxStart = content.length - windowSize;
    for (int i = 0; i <= maxStart; i += 20) {
      final window = lowerContent.substring(i, i + windowSize);
      int score = 0;
      for (final word in queryWords) {
        if (window.contains(word)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestStart = i;
      }
    }

    final end = min(bestStart + windowSize, content.length);
    final excerpt = content.substring(bestStart, end).trim();
    if (bestStart > 0 || end < content.length) {
      return '...$excerpt...';
    }
    return excerpt;
  }

  List<String> extractKeywordHighlights(String query, Note note) {
    final queryWords = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    final allText = '${note.title} ${note.content} ${note.keywords.join(' ')}'.toLowerCase();
    return queryWords.where((w) => allText.contains(w)).toList();
  }
}
