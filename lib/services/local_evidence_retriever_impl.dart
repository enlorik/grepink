import '../models/evidence_item.dart';
import 'database_service.dart';
import 'local_evidence_retriever.dart';

class LocalEvidenceRetrieverImpl implements LocalEvidenceRetriever {
  final DatabaseService _db;

  LocalEvidenceRetrieverImpl({DatabaseService? db})
      : _db = db ?? DatabaseService.instance;

  @override
  Future<List<EvidenceItem>> retrieve(String question) async {
    if (question.trim().isEmpty) return [];
    try {
      final rows = await _db.searchFts(question);
      return rows.map((row) {
        final id = row['id'] as String;
        final title = (row['title'] as String?) ?? '';
        final content = (row['content'] as String?) ?? '';
        final rank = (row['fts_rank'] as num?)?.toDouble() ?? 0.0;
        final normalizedScore = rank < 0 ? ((-rank) / 10.0).clamp(0.0, 1.0) : 0.0;
        return EvidenceItem(
          id: 'local_$id',
          type: EvidenceType.localNote,
          title: title,
          content: content,
          sourceNoteId: id,
          relevanceScore: normalizedScore,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
