import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/claim_review_session_state.dart';
import '../services/claim_deduplication_service.dart';
import '../services/claim_extraction_service.dart';
import '../services/claim_review_mapper.dart';
import '../services/grounded_answer_ingestion_service.dart';
import '../services/grounded_answer_provider.dart';
import '../services/selected_claims_draft_builder.dart';
import '../services/text_similarity_provider.dart';
import 'knowledge_ingestion_provider.dart';

/// No real grounded-answer provider is wired up yet. Using the null
/// implementation keeps this pipeline inert (no network calls, no fake
/// Brave AI Answers) until a real provider is configured in a later PR.
final groundedAnswerProviderProvider = Provider<GroundedAnswerProvider>(
  (ref) => const NullGroundedAnswerProvider(),
);

final claimExtractionServiceProvider = Provider<ClaimExtractionService>(
  (ref) => const RuleBasedClaimExtractionService(),
);

final claimTextSimilarityProviderProvider = Provider<TextSimilarityProvider>(
  (ref) => const JaccardTextSimilarityProvider(),
);

final claimDeduplicationServiceProvider = Provider<ClaimDeduplicationService>(
  (ref) => TextSimilarityClaimDeduplicationService(
    ref.watch(claimTextSimilarityProviderProvider),
  ),
);

final claimReviewMapperProvider = Provider<ClaimReviewMapper>(
  (ref) => const ClaimReviewMapper(),
);

final groundedAnswerIngestionServiceProvider =
    Provider<GroundedAnswerIngestionService>(
  (ref) => GroundedAnswerIngestionService(
    provider: ref.watch(groundedAnswerProviderProvider),
    extractor: ref.watch(claimExtractionServiceProvider),
    deduplicator: ref.watch(claimDeduplicationServiceProvider),
    localEvidence: ref.watch(localEvidenceRetrieverProvider),
  ),
);

class ClaimReviewNotifier extends StateNotifier<ClaimReviewSessionState> {
  final Ref _ref;
  int _requestSequence = 0;

  ClaimReviewNotifier(this._ref) : super(const ClaimReviewSessionState());

  Future<void> runReview(String question) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) {
      reset();
      return;
    }

    // Skip the entire pipeline when no real provider is wired up.
    if (!_ref.read(groundedAnswerIngestionServiceProvider).isConfigured) return;

    final requestId = ++_requestSequence;

    state = state.copyWith(
      status: ClaimReviewSessionStatus.loading,
      question: trimmedQuestion,
      clearSelection: true,
      clearError: true,
    );

    try {
      final service = _ref.read(groundedAnswerIngestionServiceProvider);
      final mapper = _ref.read(claimReviewMapperProvider);
      final ingestion = await service.ingest(trimmedQuestion);
      if (requestId != _requestSequence) return;

      final groups = mapper.toGroups(ingestion);
      final selection = mapper.toSelectionState(ingestion);

      state = state.copyWith(
        status: ClaimReviewSessionStatus.success,
        question: trimmedQuestion,
        groups: groups,
        selection: selection,
        providerName: ingestion.providerName,
        citations: ingestion.citations,
        clearError: true,
        clearDraft: true,
      );
    } catch (error) {
      if (requestId != _requestSequence) return;
      state = state.copyWith(
        status: ClaimReviewSessionStatus.error,
        question: trimmedQuestion,
        groups: const [],
        clearSelection: true,
        errorMessage: error.toString(),
        clearDraft: true,
      );
    }
  }

  void toggle(String claimId) {
    final selection = state.selection;
    if (selection == null) return;
    state = state.copyWith(selection: selection.toggle(claimId), clearDraft: true);
  }

  /// Builds a markdown draft from the currently selected saveable claims.
  ///
  /// Uses only [ClaimReviewSelectionState.selectedSaveableItems], so
  /// alreadyKnown and unselected claims are never included. Does not persist
  /// anything.
  void generateDraft() {
    final selection = state.selection;
    if (selection == null) return;

    const builder = SelectedClaimsDraftBuilder();
    final result = builder.build(
      question: state.question,
      selected: selection.selectedSaveableItems,
      providerName: state.providerName,
      citations: state.citations,
    );
    state = state.copyWith(draft: result);
  }

  void reset() {
    _requestSequence++;
    state = const ClaimReviewSessionState();
  }
}

final claimReviewProvider =
    StateNotifierProvider<ClaimReviewNotifier, ClaimReviewSessionState>(
  (ref) => ClaimReviewNotifier(ref),
);
