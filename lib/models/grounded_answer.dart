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

  GroundedAnswer({
    required this.question,
    required this.answerText,
    required List<GroundedAnswerCitation> citations,
    required this.providerName,
    required this.generatedAt,
    this.rawSourceLabel,
  }) : citations = List.unmodifiable(citations);

  bool get isEmpty => answerText.trim().isEmpty;

  bool get hasCitations => citations.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroundedAnswer &&
          runtimeType == other.runtimeType &&
          question == other.question &&
          answerText == other.answerText &&
          providerName == other.providerName &&
          generatedAt == other.generatedAt &&
          rawSourceLabel == other.rawSourceLabel &&
          _citationsEqual(citations, other.citations);

  static bool _citationsEqual(
    List<GroundedAnswerCitation> a,
    List<GroundedAnswerCitation> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        question,
        answerText,
        providerName,
        generatedAt,
        rawSourceLabel,
        Object.hashAll(citations),
      );
}
