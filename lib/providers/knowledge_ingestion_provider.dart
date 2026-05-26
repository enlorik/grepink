import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/knowledge_ingestion_state.dart';
import '../services/configured_summary_writer_factory.dart';
import '../services/delta_detector.dart';
import '../services/delta_detector_impl.dart';
import '../services/knowledge_ingestion_service.dart';
import '../services/local_evidence_retriever.dart';
import '../services/local_evidence_retriever_impl.dart';
import '../services/summary_writer.dart';
import '../services/web_evidence_provider.dart';
import 'llm_settings_provider.dart';

final localEvidenceRetrieverProvider = Provider<LocalEvidenceRetriever>(
  (ref) => LocalEvidenceRetrieverImpl(),
);

final knowledgeWebEvidenceProvider = Provider<WebEvidenceProvider>(
  (ref) => EmptyWebEvidenceProvider(),
);

final deltaDetectorProvider = Provider<DeltaDetector>(
  (ref) => DeltaDetectorImpl(),
);

final configuredSummaryWriterFactoryProvider =
    FutureProvider<ConfiguredSummaryWriterFactory>((ref) async {
  final settingsService = await ref.watch(llmSettingsServiceProvider.future);
  return ConfiguredSummaryWriterFactory(settingsService: settingsService);
});

final summaryWriterProvider = FutureProvider<SummaryWriter>((ref) async {
  final factory = await ref.watch(configuredSummaryWriterFactoryProvider.future);
  return factory.create();
});

final knowledgeIngestionServiceProvider =
    FutureProvider<KnowledgeIngestionService>((ref) async {
  final summaryWriter = await ref.watch(summaryWriterProvider.future);
  return KnowledgeIngestionServiceImpl(
    localRetriever: ref.watch(localEvidenceRetrieverProvider),
    webProvider: ref.watch(knowledgeWebEvidenceProvider),
    deltaDetector: ref.watch(deltaDetectorProvider),
    summaryWriter: summaryWriter,
  );
});

class KnowledgeIngestionNotifier extends StateNotifier<KnowledgeIngestionState> {
  final Ref _ref;
  int _requestSequence = 0;

  KnowledgeIngestionNotifier(this._ref) : super(const KnowledgeIngestionState());

  Future<void> ingest(String question) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) {
      reset();
      return;
    }

    final requestId = ++_requestSequence;

    state = state.copyWith(
      status: KnowledgeIngestionStatus.loading,
      question: trimmedQuestion,
      clearDraft: true,
      clearError: true,
    );

    try {
      final service = await _ref.read(knowledgeIngestionServiceProvider.future);
      final noteDraft = await service.ingest(trimmedQuestion);
      if (requestId != _requestSequence) return;

      state = state.copyWith(
        status: KnowledgeIngestionStatus.success,
        question: trimmedQuestion,
        noteDraft: noteDraft,
        clearError: true,
      );
    } catch (error) {
      if (requestId != _requestSequence) return;
      state = state.copyWith(
        status: KnowledgeIngestionStatus.error,
        question: trimmedQuestion,
        errorMessage: error.toString(),
        clearDraft: true,
      );
    }
  }

  void reset() {
    _requestSequence++;
    state = const KnowledgeIngestionState();
  }
}

final knowledgeIngestionProvider = StateNotifierProvider<
    KnowledgeIngestionNotifier, KnowledgeIngestionState>(
  (ref) => KnowledgeIngestionNotifier(ref),
);
