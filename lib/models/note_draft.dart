import 'evidence_item.dart';
import 'knowledge_delta.dart';

enum NoteDraftAction { createNewNote, appendToExistingNote, doNotSave }

class NoteDraft {
  final String question;
  final String markdownContent;
  final NoteDraftAction action;
  final List<KnowledgeDelta> deltas;
  final List<EvidenceItem> localEvidence;
  final List<EvidenceItem> webEvidence;

  const NoteDraft({
    required this.question,
    required this.markdownContent,
    required this.action,
    required this.deltas,
    required this.localEvidence,
    required this.webEvidence,
  });
}
