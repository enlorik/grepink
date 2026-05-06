import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/evidence_item.dart';
import 'web_evidence_provider.dart';

/// Safe-search levels supported by the Brave Search API.
enum BraveSafeSearch { off, moderate, strict }

/// [WebEvidenceProvider] backed by the Brave Search API.
///
/// Usage:
/// ```dart
/// final provider = BraveEvidenceProvider(apiKey: 'YOUR_KEY');
/// final results = await provider.fetch('What is photosynthesis?');
/// ```
///
/// For unit tests, pass a custom [httpClient] so no real network call is made.
class BraveEvidenceProvider implements WebEvidenceProvider {
  static const _baseUrl = 'https://api.search.brave.com/res/v1/web/search';

  final String _apiKey;
  final http.Client _httpClient;

  /// Maximum number of results to return (1–20, default 5).
  final int count;

  /// Optional country/market code (e.g. `'US'`, `'GB'`).
  final String? country;

  /// Safe-search level (default: [BraveSafeSearch.moderate]).
  final BraveSafeSearch safeSearch;

  BraveEvidenceProvider({
    required String apiKey,
    http.Client? httpClient,
    this.count = 5,
    this.country,
    this.safeSearch = BraveSafeSearch.moderate,
  })  : _apiKey = apiKey,
        _httpClient = httpClient ?? http.Client();

  @override
  Future<List<EvidenceItem>> fetch(String question) async {
    if (question.trim().isEmpty) return [];
    if (_apiKey.trim().isEmpty) return [];

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'q': question,
        'count': count.clamp(1, 20).toString(),
        'safesearch': safeSearch.name,
        if (country != null) 'country': country!,
      },
    );

    http.Response response;
    try {
      response = await _httpClient.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'X-Subscription-Token': _apiKey,
        },
      );
    } catch (_) {
      return [];
    }

    if (response.statusCode != 200) return [];

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return [];
    }

    final webBlock = body['web'] as Map<String, dynamic>?;
    final rawResults = webBlock?['results'] as List<dynamic>? ?? [];

    final items = <EvidenceItem>[];
    var rank = 0;
    for (final raw in rawResults) {
      final r = raw as Map<String, dynamic>;
      final url = (r['url'] as String? ?? '').trim();
      final title = (r['title'] as String? ?? '').trim();
      final description = (r['description'] as String? ?? '').trim();

      if (url.isEmpty || title.isEmpty || description.isEmpty) continue;

      items.add(EvidenceItem(
        id: 'brave_${rank}_${url.hashCode.abs()}',
        type: EvidenceType.webSearch,
        title: title,
        content: description,
        sourceUrl: url,
        relevanceScore: (1.0 - rank * 0.1).clamp(0.1, 1.0),
      ));
      rank++;
    }
    return items;
  }
}

/// Thrown when the Brave Search API returns a non-200 status code.
class BraveApiException implements Exception {
  final int statusCode;
  final String body;

  const BraveApiException({required this.statusCode, required this.body});

  @override
  String toString() =>
      'BraveApiException: HTTP $statusCode\n$body';
}
