class GroundedAnswerCitation {
  final String id;
  final String title;
  final String url;
  final String? snippet;
  final int? position;

  const GroundedAnswerCitation({
    required this.id,
    required this.title,
    required this.url,
    this.snippet,
    this.position,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroundedAnswerCitation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          url == other.url;

  @override
  int get hashCode => Object.hash(id, url);
}

class GroundedAnswer {
  final String question;
  final String answerText;
  final List<GroundedAnswerCitation> citations;
  final String providerName;
  final DateTime generatedAt;
  final String? rawSourceLabel;

  const GroundedAnswer({
    required this.question,
    required this.answerText,
    required this.citations,
    required this.providerName,
    required this.generatedAt,
    this.rawSourceLabel,
  });

  bool get isEmpty => answerText.trim().isEmpty;

  bool get hasCitations => citations.isNotEmpty;
}
