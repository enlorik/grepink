import '../models/note_draft.dart';
import 'delta_detector.dart';
import 'local_evidence_retriever.dart';
import 'summary_writer.dart';
import 'web_evidence_provider.dart';

abstract class KnowledgeIngestionService {
  Future<NoteDraft> ingest(String question);
}

class KnowledgeIngestionServiceImpl implements KnowledgeIngestionService {
  final LocalEvidenceRetriever _localRetriever;
  final WebEvidenceProvider _webProvider;
  final DeltaDetector _deltaDetector;
  final SummaryWriter _summaryWriter;

  KnowledgeIngestionServiceImpl({
    required LocalEvidenceRetriever localRetriever,
    required WebEvidenceProvider webProvider,
    required DeltaDetector deltaDetector,
    required SummaryWriter summaryWriter,
  })  : _localRetriever = localRetriever,
        _webProvider = webProvider,
        _deltaDetector = deltaDetector,
        _summaryWriter = summaryWriter;

  @override
  Future<NoteDraft> ingest(String question) async {
    final localEvidence = await _localRetriever.retrieve(question);
    final webEvidence = await _webProvider.fetch(question);
    final deltas = await _deltaDetector.detect(localEvidence, webEvidence);
    return _summaryWriter.write(
      question: question,
      localEvidence: localEvidence,
      webEvidence: webEvidence,
      deltas: deltas,
    );
  }
}
