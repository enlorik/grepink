import 'dart:convert';
import 'package:http/http.dart' as http;

class RailwaySyncResponse {
  final List<AcknowledgedMutation> acknowledged;
  final List<ConflictResult> conflicts;
  final List<SnapshotRow> snapshot;

  const RailwaySyncResponse({
    required this.acknowledged,
    required this.conflicts,
    required this.snapshot,
  });

  factory RailwaySyncResponse.fromJson(Map<String, dynamic> json) {
    return RailwaySyncResponse(
      acknowledged: (json['acknowledged'] as List)
          .map((e) => AcknowledgedMutation.fromJson(e as Map<String, dynamic>))
          .toList(),
      conflicts: (json['conflicts'] as List)
          .map((e) => ConflictResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      snapshot: (json['snapshot'] as List)
          .map((e) => SnapshotRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AcknowledgedMutation {
  final String mutationId;
  final String noteId;
  final int revision;

  const AcknowledgedMutation({
    required this.mutationId,
    required this.noteId,
    required this.revision,
  });

  factory AcknowledgedMutation.fromJson(Map<String, dynamic> json) =>
      AcknowledgedMutation(
        mutationId: json['mutationId'] as String,
        noteId: json['noteId'] as String,
        revision: json['revision'] as int,
      );
}

class ConflictResult {
  final String mutationId;
  final String noteId;
  final String operation;
  final int serverRevision;
  final Map<String, dynamic>? serverState;

  const ConflictResult({
    required this.mutationId,
    required this.noteId,
    required this.operation,
    required this.serverRevision,
    this.serverState,
  });

  factory ConflictResult.fromJson(Map<String, dynamic> json) => ConflictResult(
        mutationId: json['mutationId'] as String,
        noteId: json['noteId'] as String,
        operation: json['operation'] as String,
        serverRevision: json['serverRevision'] as int,
        serverState: json['serverState'] as Map<String, dynamic>?,
      );
}

class SnapshotRow {
  final String id;
  final int revision;
  final bool deleted;
  final String? title;
  final String? content;
  final List<String> tags;
  final List<String> keywords;
  final bool isPinned;
  final String? createdAt;
  final String? updatedAt;

  const SnapshotRow({
    required this.id,
    required this.revision,
    required this.deleted,
    this.title,
    this.content,
    required this.tags,
    required this.keywords,
    required this.isPinned,
    this.createdAt,
    this.updatedAt,
  });

  factory SnapshotRow.fromJson(Map<String, dynamic> json) {
    List<String> parseList(dynamic v) {
      if (v == null) return [];
      if (v is List) return List<String>.from(v);
      if (v is String) {
        try {
          final decoded = jsonDecode(v);
          if (decoded is List) return List<String>.from(decoded);
        } catch (_) {}
      }
      return [];
    }

    return SnapshotRow(
      id: json['id'] as String,
      revision: json['revision'] as int,
      deleted: json['deleted'] as bool? ?? false,
      title: json['title'] as String?,
      content: json['content'] as String?,
      tags: parseList(json['tags']),
      keywords: parseList(json['keywords']),
      isPinned: json['isPinned'] as bool? ?? false,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }
}

abstract class RailwayHttpClient {
  Future<bool> checkHealth(String baseUrl);
  Future<RailwaySyncResponse> sync(
    String baseUrl,
    String token,
    List<Map<String, dynamic>> mutations,
  );
}

class LiveRailwayHttpClient implements RailwayHttpClient {
  final http.Client _client;

  LiveRailwayHttpClient({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<bool> checkHealth(String baseUrl) async {
    final uri = Uri.parse('$baseUrl/health');
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    return response.statusCode == 200;
  }

  @override
  Future<RailwaySyncResponse> sync(
    String baseUrl,
    String token,
    List<Map<String, dynamic>> mutations,
  ) async {
    final uri = Uri.parse('$baseUrl/v1/sync');
    final body = jsonEncode({'mutations': mutations});

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      throw const RailwayAuthException();
    }
    if (response.statusCode == 413) {
      throw const RailwayRequestTooLargeException();
    }
    if (response.statusCode != 200) {
      throw RailwayServerException(response.statusCode);
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }
    return RailwaySyncResponse.fromJson(json);
  }
}

class RailwayAuthException implements Exception {
  const RailwayAuthException();
  @override
  String toString() => 'RailwayAuthException';
}

class RailwayRequestTooLargeException implements Exception {
  const RailwayRequestTooLargeException();
  @override
  String toString() => 'RailwayRequestTooLargeException';
}

class RailwayServerException implements Exception {
  final int statusCode;
  const RailwayServerException(this.statusCode);
  @override
  String toString() => 'RailwayServerException($statusCode)';
}
