import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/excerpt_result.dart';

class AiService {
  AiService._();
  static final AiService instance = AiService._();

  static const String _model = 'gpt-4o-mini';
  static const String _systemPrompt =
      'You are Grepink AI, a personal knowledge assistant with a perfect memory. '
      'Your job is to help the user recall what THEY have already learned and written. '
      'When the user asks a question, look at the excerpts provided from their notes. '
      "Always quote from their notes. Never invent information they didn't write. "
      "If their notes contain the answer, start with 'You've solved this before:'. "
      "If notes are partial, say 'You touched on this in your notes:'. "
      "If no notes match, say 'I don't see this in your notes yet, but based on your knowledge:'";

  Future<String> getResponse({
    required String query,
    required List<ExcerptResult> excerpts,
    required String apiKey,
    int maxTokens = 120,
  }) async {
    final contextParts = excerpts.take(5).map((e) {
      return 'Note: "${e.note.title}"\nExcerpt: "${e.excerptText}"';
    }).join('\n\n');

    final userMessage = excerpts.isEmpty
        ? query
        : 'My notes context:\n$contextParts\n\nMy question: $query';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'max_tokens': maxTokens,
        'temperature': 0.3,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('AI API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = data['choices'][0]['message']['content'] as String;
    return content.trim();
  }
}
