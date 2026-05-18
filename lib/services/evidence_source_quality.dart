import '../models/evidence_item.dart';

class EvidenceSourceQuality {
  const EvidenceSourceQuality._();

  static double score(EvidenceItem item) {
    var score = switch (item.type) {
      EvidenceType.aiGroundedAnswer => 60.0,
      EvidenceType.localNote => 50.0,
      EvidenceType.webSearch => 40.0,
    };

    if (_hasText(item.sourceUrl)) {
      score += 20.0;
    }

    if (item.type == EvidenceType.localNote && _hasText(item.sourceNoteId)) {
      score += 10.0;
    }

    if (_hasText(item.title)) {
      score += 5.0;
    } else {
      score -= 5.0;
    }

    if (_hasText(item.content)) {
      score += 10.0;
    } else {
      score -= 20.0;
    }

    score += item.relevanceScore.clamp(0.0, 1.0) * 10.0;
    return score;
  }

  static int compare(EvidenceItem a, EvidenceItem b) {
    final scoreComparison = score(b).compareTo(score(a));
    if (scoreComparison != 0) {
      return scoreComparison;
    }

    return a.id.compareTo(b.id);
  }

  static bool isWebCitation(EvidenceItem item) {
    return item.type != EvidenceType.localNote && _hasText(item.sourceUrl);
  }

  static bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}
