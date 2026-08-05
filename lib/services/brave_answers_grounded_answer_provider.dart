import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/grounded_answer.dart';
import '../models/grounded_answer_provider_outcome.dart';
import 'grounded_answer_provider.dart';

class BraveAnswersGroundedAnswerProvider implements GroundedAnswerProvider {
  final String _apiKey;
  final http.Client _client;

  BraveAnswersGroundedAnswerProvider({
    required String apiKey,
    http.Client? client,
  })  : _apiKey = apiKey,
        _client = client ?? http.Client();

  static final _citationTag =
      RegExp(r'<citation>(.*?)</citation>', dotAll: true);
  static final _anyTag = RegExp(r'<[^>]+>.*?</[^>]+>', dotAll: true);

  @override
  Future<GroundedAnswerProviderOutcome> fetchGroundedAnswer(
      String question) async {
    try {
      final request = http.Request(
        'POST',
        Uri.parse('https://api.search.brave.com/res/v1/chat/completions'),
      );
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'x-subscription-token': _apiKey,
      });
      request.body = jsonEncode({
        'model': 'brave',
        'stream': true,
        'enable_citations': true,
        'messages': [
          {'role': 'user', 'content': question}
        ],
      });

      final response = await _client.send(request);

      switch (response.statusCode) {
        case 402:
          return const GroundedAnswerPlanUnavailable();
        case 403:
          return const GroundedAnswerUnauthorized();
        case 429:
          return const GroundedAnswerRateLimited();
        default:
          if (response.statusCode >= 500) {
            return const GroundedAnswerNetworkFailure();
          }
      }

      if (response.statusCode != 200) {
        return const GroundedAnswerNetworkFailure();
      }

      final buffer = StringBuffer();
      var remainder = '';

      await for (final chunk
          in response.stream.transform(utf8.decoder)) {
        remainder += chunk;
        final frames = remainder.split('\n\n');
        remainder = frames.removeLast();

        for (final frame in frames) {
          for (final line in frame.split('\n')) {
            if (!line.startsWith('data: ')) continue;
            final data = line.substring(6);
            if (data.trim() == '[DONE]') break;
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final choices = json['choices'] as List<dynamic>?;
              if (choices == null || choices.isEmpty) continue;
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null) buffer.write(content);
            } catch (_) {
              // skip malformed delta chunk
            }
          }
        }
      }

      // Process any trailing frame
      for (final line in remainder.split('\n')) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6);
        if (data.trim() == '[DONE]') break;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null) buffer.write(content);
        } catch (_) {
          // skip malformed delta chunk
        }
      }

      final assembled = buffer.toString();

      final citations = <GroundedAnswerCitation>[];
      for (final match in _citationTag.allMatches(assembled)) {
        try {
          final json =
              jsonDecode(match.group(1)!) as Map<String, dynamic>;
          citations.add(GroundedAnswerCitation(
            id: (json['number'] ?? json['id'] ?? citations.length + 1)
                .toString(),
            title: (json['url'] as String? ?? ''),
            url: json['url'] as String? ?? '',
            snippet: json['snippet'] as String?,
            startIndex: json['start_index'] as int?,
            endIndex: json['end_index'] as int?,
          ));
        } catch (_) {
          // skip malformed citation
        }
      }

      var answerText = assembled
          .replaceAll(_citationTag, '')
          .replaceAll(RegExp(r'<usage>.*?</usage>', dotAll: true), '')
          .replaceAll(_anyTag, '')
          .trim();

      if (answerText.isEmpty) return const GroundedAnswerEmpty();

      return GroundedAnswerSuccess(GroundedAnswer(
        question: question,
        answerText: answerText,
        citations: citations,
        providerName: 'Brave Answers',
        generatedAt: DateTime.now().toUtc(),
      ));
    } on SocketException {
      return const GroundedAnswerNetworkFailure();
    } on IOException {
      return const GroundedAnswerNetworkFailure();
    } on TimeoutException {
      return const GroundedAnswerNetworkFailure();
    } catch (_) {
      return const GroundedAnswerNetworkFailure();
    }
  }
}
