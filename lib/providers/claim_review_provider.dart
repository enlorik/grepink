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
        appendStatus: ClaimDraftAppendStatus.idle,
        clearAppendError: true,
        clearTargetNoteId: true,
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
        appendStatus: ClaimDraftAppendStatus.idle,
        clearAppendError: true,
        clearTargetNoteId: true,
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
      appendStatus: ClaimDraftAppendStatus.idle,
      clearAppendError: true,
    );
  }

  void selectTargetNote(String? noteId) {
    state = state.copyWith(
      targetNoteId: noteId,
      clearTargetNoteId: noteId == null,
      clearAppendError: true,
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
    // Regenerating an unchanged selection produces markdown identical to
    // what was already saved. Keep it marked as saved instead of resetting
    // to idle, otherwise the Save button re-enables and a repeat tap would
    // insert a duplicate note with the same content.
    final matchesSavedDraft = state.savedDraftContent == result.markdownContent;
    state = state.copyWith(
      draft: result,
      saveStatus: matchesSavedDraft
          ? ClaimDraftSaveStatus.saved
          : ClaimDraftSaveStatus.idle,
      clearSaveError: true,
      appendStatus: ClaimDraftAppendStatus.idle,
      clearAppendError: true,
    );
  }

  /// Saves [ClaimReviewSessionState.draft] as a new note using the same
  /// persistence path as the existing note-draft review flow.
  ///
  /// Does nothing if there is no draft, the draft is not saveable
  /// ([ClaimDraftResult.shouldSave] is false), or the exact same draft
  /// content was already saved successfully.
  Future<void> saveAsNewNote() async {
    final draft = state.draft;
    if (draft == null || !draft.shouldSave) return;
    if (state.isDraftAlreadySaved) return;
    if (state.saveStatus == ClaimDraftSaveStatus.saving) return;

    state = state.copyWith(
      saveStatus: ClaimDraftSaveStatus.saving,
      clearSaveError: true,
    );

    try {
      final repository = _ref.read(noteDraftReviewRepositoryProvider);
      await repository.insertNote(
        title: _titleFor(state.question),
        content: draft.markdownContent,
      );
      // The current draft may have been replaced (toggled, regenerated, or
      // the session reset) while insertNote was in flight. savedDraftContent
      // always records the markdown that was actually persisted, so that if
      // the user later returns to that same selection it is still
      // recognized as already saved instead of being inserted again. Only
      // flip saveStatus to saved when the current draft is the one that was
      // just persisted, so an unrelated in-progress draft isn't mislabeled.
      final matchesCurrentDraft =
          state.draft?.markdownContent == draft.markdownContent;
      state = state.copyWith(
        saveStatus:
            matchesCurrentDraft ? ClaimDraftSaveStatus.saved : state.saveStatus,
        savedDraftContent: draft.markdownContent,
      );
    } catch (error) {
      if (state.draft?.markdownContent == draft.markdownContent) {
        state = state.copyWith(
          saveStatus: ClaimDraftSaveStatus.error,
          saveErrorMessage: error.toString(),
        );
      }
    }
  }

  /// Appends [ClaimReviewSessionState.draft] to an existing note chosen via
  /// [selectTargetNote], using the same repository as the note-draft review
  /// flow's append action.
  ///
  /// Does nothing if there is no draft or the draft is not saveable
  /// ([ClaimDraftResult.shouldSave] is false).
  Future<void> appendToExistingNote() async {
    final draft = state.draft;
    if (draft == null || !draft.shouldSave) return;
    if (state.appendStatus == ClaimDraftAppendStatus.appending) return;

    final targetNoteId = state.targetNoteId;
    if (targetNoteId == null || targetNoteId.isEmpty) {
      state = state.copyWith(
        appendStatus: ClaimDraftAppendStatus.error,
        appendErrorMessage: 'Select a target note before appending.',
      );
      return;
    }

    state = state.copyWith(
      appendStatus: ClaimDraftAppendStatus.appending,
      clearAppendError: true,
    );

    try {
      final repository = _ref.read(noteDraftReviewRepositoryProvider);
      final existingNote = await repository.getNoteById(targetNoteId);
      if (existingNote == null) {
        if (state.draft?.markdownContent != draft.markdownContent) return;
        state = state.copyWith(
          appendStatus: ClaimDraftAppendStatus.error,
          appendErrorMessage: 'Selected target note no longer exists.',
        );
        return;
      }

      final now = DateTime.now();
      final updatedNote = existingNote.copyWith(
        content: _appendDraftMarkdown(existingNote.content, draft),
        updatedAt: now,
        embeddingPending: true,
        clearEmbedding: true,
      );
      await repository.updateNote(updatedNote);

      // See saveAsNewNote for why this compares content rather than
      // relying on the draft still being the current one.
      if (state.draft?.markdownContent == draft.markdownContent) {
        state = state.copyWith(appendStatus: ClaimDraftAppendStatus.appended);
      }
    } catch (error) {
      if (state.draft?.markdownContent != draft.markdownContent) return;
      state = state.copyWith(
        appendStatus: ClaimDraftAppendStatus.error,
        appendErrorMessage: error.toString(),
      );
    }
  }

  String _appendDraftMarkdown(String existingContent, ClaimDraftResult draft) {
    final trimmedExisting = existingContent.trimRight();
    final trimmedDraft = draft.markdownContent.trim();
    if (trimmedExisting.isEmpty) return trimmedDraft;
    return '$trimmedExisting\n\n---\n\n$trimmedDraft';
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
