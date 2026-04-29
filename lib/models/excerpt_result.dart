import 'note.dart';

class ExcerptResult {
  final Note note;
  final String excerptText;
  final double similarityScore;
  final List<String> keywordHighlights;
  final List<String> highlightedWords;

  const ExcerptResult({
    required this.note,
    required this.excerptText,
    required this.similarityScore,
    required this.keywordHighlights,
    required this.highlightedWords,
  });

  ExcerptResult copyWith({
    Note? note,
    String? excerptText,
    double? similarityScore,
    List<String>? keywordHighlights,
    List<String>? highlightedWords,
  }) {
    return ExcerptResult(
      note: note ?? this.note,
      excerptText: excerptText ?? this.excerptText,
      similarityScore: similarityScore ?? this.similarityScore,
      keywordHighlights: keywordHighlights ?? this.keywordHighlights,
      highlightedWords: highlightedWords ?? this.highlightedWords,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'note': note.toJson(),
      'excerptText': excerptText,
      'similarityScore': similarityScore,
      'keywordHighlights': keywordHighlights,
      'highlightedWords': highlightedWords,
    };
  }

  factory ExcerptResult.fromJson(Map<String, dynamic> json) {
    return ExcerptResult(
      note: Note.fromJson(json['note'] as Map<String, dynamic>),
      excerptText: json['excerptText'] as String,
      similarityScore: (json['similarityScore'] as num).toDouble(),
      keywordHighlights: List<String>.from(json['keywordHighlights'] as List),
      highlightedWords: List<String>.from(json['highlightedWords'] as List),
    );
  }

  String get badgeLabel {
    if (similarityScore >= 0.95) return 'EXACT MATCH';
    if (similarityScore >= 0.85) return 'YOU SOLVED THIS BEFORE';
    if (similarityScore >= 0.72) return 'SIMILAR PROBLEM';
    return '';
  }

  bool get showInMemorySection => similarityScore >= 0.72;
  bool get showBadge => similarityScore >= 0.72;
}
