import 'dart:convert';
import 'dart:typed_data';

class Note {
  final String id;
  final String title;
  final String content;
  final List<String> tags;
  final List<String> keywords;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<double>? embedding;
  final bool embeddingPending;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.tags,
    required this.keywords,
    required this.isPinned,
    required this.createdAt,
    required this.updatedAt,
    this.embedding,
    required this.embeddingPending,
  });

  Note copyWith({
    String? id,
    String? title,
    String? content,
    List<String>? tags,
    List<String>? keywords,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<double>? embedding,
    bool? embeddingPending,
    bool clearEmbedding = false,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      keywords: keywords ?? this.keywords,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      embedding: clearEmbedding ? null : (embedding ?? this.embedding),
      embeddingPending: embeddingPending ?? this.embeddingPending,
    );
  }

  Map<String, dynamic> toMap() {
    Uint8List? embeddingBytes;
    if (embedding != null) {
      final float32 = Float32List.fromList(embedding!);
      embeddingBytes = float32.buffer.asUint8List();
    }
    return {
      'id': id,
      'title': title,
      'content': content,
      'tags': jsonEncode(tags),
      'keywords': jsonEncode(keywords),
      'is_pinned': isPinned ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'embedding': embeddingBytes,
      'embedding_pending': embeddingPending ? 1 : 0,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    List<double>? embedding;
    if (map['embedding'] != null) {
      try {
        final bytes = map['embedding'] as List<int>;
        final uint8 = Uint8List.fromList(bytes);
        embedding = Float32List.view(uint8.buffer).toList();
      } catch (_) {
        embedding = null;
      }
    }

    List<String> parseTags(dynamic value) {
      if (value == null) return [];
      if (value is List) return List<String>.from(value);
      try {
        final decoded = jsonDecode(value as String);
        if (decoded is List) return List<String>.from(decoded);
      } catch (_) {}
      return [];
    }

    return Note(
      id: map['id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      tags: parseTags(map['tags']),
      keywords: parseTags(map['keywords']),
      isPinned: (map['is_pinned'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      embedding: embedding,
      embeddingPending: (map['embedding_pending'] as int) == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'tags': tags,
      'keywords': keywords,
      'isPinned': isPinned,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'embeddingPending': embeddingPending,
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      tags: List<String>.from(json['tags'] as List),
      keywords: List<String>.from(json['keywords'] as List),
      isPinned: json['isPinned'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      embeddingPending: json['embeddingPending'] as bool? ?? false,
    );
  }

  String get embeddingText {
    final kwJoined = keywords.join(', ');
    final excerpt = content.length > 500 ? content.substring(0, 500) : content;
    return '$title. $kwJoined. $excerpt';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Note && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
