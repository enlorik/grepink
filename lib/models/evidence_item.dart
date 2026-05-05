enum EvidenceType { localNote, webSearch, aiGroundedAnswer }

class EvidenceItem {
  final String id;
  final EvidenceType type;
  final String title;
  final String content;
  final String? sourceNoteId;
  final String? sourceUrl;
  final double relevanceScore;

  const EvidenceItem({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    this.sourceNoteId,
    this.sourceUrl,
    this.relevanceScore = 0.0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvidenceItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
