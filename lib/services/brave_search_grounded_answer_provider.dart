import 'package:http/http.dart' as http;

import '../models/brave_settings.dart';
import '../models/grounded_answer.dart';
import 'brave_evidence_provider.dart';
import 'grounded_answer_provider.dart';

/// Adapts regular Brave Search results into Grepink's grounded-answer contract.
///
/// This is deliberately conservative: every extracted claim is backed by a
/// returned Brave result and its source URL. It does not pretend that regular
/// search snippets are the unavailable Brave AI Answers product.
class BraveSearchGroundedAnswerProvider implements GroundedAnswerProvider {
  final BraveSettings settings;
  final Future<String?> Function() apiKeyLoader;
  final http.Client? httpClient;
  final DateTime Function() now;

  BraveSearchGroundedAnswerProvider({
    required this.settings,
    required this.apiKeyLoader,
    this.httpClient,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  bool get isConfigured => settings.enabled && settings.apiKeyConfigured;

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty || !isConfigured) return null;

    final apiKey = (await apiKeyLoader())?.trim() ?? '';
    if (apiKey.isEmpty) return null;

    final evidence = await BraveEvidenceProvider(
      apiKey: apiKey,
      httpClient: httpClient,
      count: settings.resultCount,
      safeSearch: settings.safeSearch,
    ).fetch(trimmedQuestion);

    final usable = evidence
        .where(
          (item) =>
              item.title.trim().isNotEmpty &&
              item.content.trim().isNotEmpty &&
              (item.sourceUrl?.trim().isNotEmpty ?? false),
        )
        .toList(growable: false);

    if (usable.isEmpty) return null;

    final answerText = usable
        .map((item) => '${item.title.trim()}. ${item.content.trim()}')
        .join('\n\n');

    final citations = <GroundedAnswerCitation>[
      for (var i = 0; i < usable.length; i++)
        GroundedAnswerCitation(
          id: usable[i].id,
          title: usable[i].title.trim(),
          url: usable[i].sourceUrl!.trim(),
          snippet: usable[i].content.trim(),
          position: i + 1,
        ),
    ];

    return GroundedAnswer(
      question: trimmedQuestion,
      answerText: answerText,
      citations: citations,
      providerName: 'Brave Search',
      generatedAt: now().toUtc(),
      rawSourceLabel: 'brave_web_search',
    );
  }
}
