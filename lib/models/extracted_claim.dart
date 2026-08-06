class ExtractedClaim {
  final String id;
  final String text;
  final List<String> citationUrls;
  final List<String> citationTitles;
  final String sourceAnswerProvider;
  final String sourceQuestion;
  final double? confidence;
  final int order;
  final bool citationUncertain;

  const ExtractedClaim({
    required this.id,
    required this.text,
    required this.citationUrls,
    required this.citationTitles,
    required this.sourceAnswerProvider,
    required this.sourceQuestion,
    this.confidence,
    required this.order,
    this.citationUncertain = false,
  });

  ExtractedClaim copyWith({
    String? id,
    String? text,
    List<String>? citationUrls,
    List<String>? citationTitles,
    String? sourceAnswerProvider,
    String? sourceQuestion,
    double? confidence,
    int? order,
    bool? citationUncertain,
  }) {
    return ExtractedClaim(
      id: id ?? this.id,
      text: text ?? this.text,
      citationUrls: citationUrls ?? this.citationUrls,
      citationTitles: citationTitles ?? this.citationTitles,
      sourceAnswerProvider: sourceAnswerProvider ?? this.sourceAnswerProvider,
      sourceQuestion: sourceQuestion ?? this.sourceQuestion,
      confidence: confidence ?? this.confidence,
      order: order ?? this.order,
      citationUncertain: citationUncertain ?? this.citationUncertain,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractedClaim &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ExtractedClaim(id: $id, order: $order, text: ${text.length > 60 ? "${text.substring(0, 60)}…" : text})';
}
