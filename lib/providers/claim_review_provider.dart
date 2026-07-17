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
import 'note_draft_review_provider.dart';

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
        saveStatus: ClaimDraftSaveStatus.idle,
        clearSaveError: true,
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
        saveStatus: ClaimDraftSaveStatus.idle,
        clearSaveError: true,
      );
    }
  }

  void toggle(String claimId) {
    final selection = state.selection;
    if (selection == null) return;
    state = state.copyWith(
      selection: selection.toggle(claimId),
      clearDraft: true,
      saveStatus: ClaimDraftSaveStatus.idle,
      clearSaveError: true,
    );
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
    // Determine the correct save status for this draft content:
    // - already confirmed saved → saved
    // - in-flight save for this exact content → saving
    // - otherwise → idle
    // Do NOT inherit saving from state.saveStatus: a different draft may be
    // in flight, and marking unrelated content as saving would leave it stuck
    // disabled after the in-flight insert completes.
    final inSaved = state.savedDraftContents.contains(result.markdownContent);
    final inPending = state.pendingDraftContents.contains(result.markdownContent);
    final ClaimDraftSaveStatus newSaveStatus;
    if (inSaved) {
      newSaveStatus = ClaimDraftSaveStatus.saved;
    } else if (inPending) {
      newSaveStatus = ClaimDraftSaveStatus.saving;
    } else {
      newSaveStatus = ClaimDraftSaveStatus.idle;
    }
    state = state.copyWith(
      draft: result,
      saveStatus: newSaveStatus,
      clearSaveError: true,
    );
  }

  /// Saves [ClaimReviewSessionState.draft] as a new note using the same
  /// persistence path as the existing note-draft review flow.
  ///
  /// Does nothing if there is no draft, the draft is not saveable
  /// ([ClaimDraftResult.shouldSave] is false), or the exact same draft
  /// content was already saved successfully.
  Future<ClaimDraftSaveOutcome> saveAsNewNote() async {
    final draft = state.draft;
    if (draft == null || !draft.shouldSave) return ClaimDraftSaveOutcome.ignored;
    if (state.isDraftAlreadySaved) return ClaimDraftSaveOutcome.ignored;
    // Block if this exact content is already being written — guards the window
    // where the user toggles away, returns to the same selection, and taps
    // Save again before the first insertNote resolves.
    if (state.pendingDraftContents.contains(draft.markdownContent)) return ClaimDraftSaveOutcome.ignored;
    if (state.saveStatus == ClaimDraftSaveStatus.saving) return ClaimDraftSaveOutcome.ignored;

    // Snapshot the session token before the async gap. reset() increments
    // _requestSequence; any mismatch after the await means a new session
    // started and this completion must not touch the new session's state.
    final saveSessionId = _requestSequence;

    state = state.copyWith(
      saveStatus: ClaimDraftSaveStatus.saving,
      clearSaveError: true,
      clearBackgroundSaveError: true,
      pendingDraftContents: {...state.pendingDraftContents, draft.markdownContent},
    );

    try {
      final repository = _ref.read(noteDraftReviewRepositoryProvider);
      await repository.insertNote(
        title: _titleFor(state.question),
        content: draft.markdownContent,
      );
      // Abandon if reset() was called while insertNote was in flight —
      // the new session must not inherit old savedDraftContents entries.
      if (saveSessionId != _requestSequence) return ClaimDraftSaveOutcome.cancelled;
      // The current draft may have been replaced (toggled, regenerated, or
      // the session reset) while insertNote was in flight. savedDraftContents
      // always records every markdown that was actually persisted this session,
      // so returning to any prior selection is still recognized as already
      // saved instead of allowing a duplicate insert. Only flip saveStatus to
      // saved when the current draft is the one that was just persisted, so an
      // unrelated in-progress draft isn't mislabeled.
      final matchesCurrentDraft =
          state.draft?.markdownContent == draft.markdownContent;
      state = state.copyWith(
        saveStatus:
            matchesCurrentDraft ? ClaimDraftSaveStatus.saved : state.saveStatus,
        savedDraftContents: {...state.savedDraftContents, draft.markdownContent},
        pendingDraftContents:
            state.pendingDraftContents.difference({draft.markdownContent}),
      );
      return ClaimDraftSaveOutcome.success;
    } catch (error) {
      // Abandon if reset() was called — don't surface old errors in the new
      // session, and don't touch pending (reset already cleared it).
      if (saveSessionId != _requestSequence) return ClaimDraftSaveOutcome.cancelled;
      final isCurrentDraft = state.draft?.markdownContent == draft.markdownContent;
      // Always remove from pending so the user can retry.
      // When the draft changed while the save was in flight, surface the
      // failure via backgroundSaveError instead of marking the new draft
      // as failed.
      if (isCurrentDraft) {
        state = state.copyWith(
          saveStatus: ClaimDraftSaveStatus.error,
          saveErrorMessage: error.toString(),
          pendingDraftContents:
              state.pendingDraftContents.difference({draft.markdownContent}),
        );
      } else {
        state = state.copyWith(
          backgroundSaveError:
              'A save failed while you were editing. No note was created.',
          pendingDraftContents:
              state.pendingDraftContents.difference({draft.markdownContent}),
        );
      }
      return ClaimDraftSaveOutcome.failure;
    }
  }

  String _titleFor(String question) {
    final compact = question.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return 'Generated note';
    if (compact.length <= 80) return compact;
    return '${compact.substring(0, 77)}...';
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
