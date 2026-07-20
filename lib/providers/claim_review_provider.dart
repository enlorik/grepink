import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/claim_review_session_state.dart';
import '../services/claim_deduplication_service.dart';
import '../services/claim_extraction_service.dart';
import '../services/claim_review_mapper.dart';
import '../services/grounded_answer_ingestion_service.dart';
import '../services/grounded_answer_provider.dart';
import '../services/selected_claims_draft_builder.dart';
import '../services/text_similarity_provider.dart';
import '../models/note_draft_review_state.dart';
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
        appendStatus: ClaimDraftAppendStatus.idle,
        clearAppendError: true,
        clearBackgroundAppendError: true,
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
        clearBackgroundAppendError: true,
        clearTargetNoteId: true,
      );
    }
  }

  void toggle(String claimId) {
    final selection = state.selection;
    if (selection == null) return;
    // Do not reset an in-flight append: clearing appendStatus to idle while
    // updateNote is awaiting would allow a second concurrent append to start,
    // potentially duplicating or losing content in the target note.
    final inFlight = state.appendStatus == ClaimDraftAppendStatus.appending;
    state = state.copyWith(
      selection: selection.toggle(claimId),
      clearDraft: true,
      saveStatus: ClaimDraftSaveStatus.idle,
      clearSaveError: true,
      appendStatus: inFlight ? null : ClaimDraftAppendStatus.idle,
      clearAppendError: !inFlight,
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
    final matchesAppendedTarget = state.targetNoteId != null &&
        (state.appendedTargetsByContent[result.markdownContent]
                ?.contains(state.targetNoteId) ??
            false);
    // Do NOT clear an in-flight append lock: if appendToExistingNote is
    // awaiting updateNote, resetting appendStatus → idle here re-enables the
    // append button and can start a second concurrent write against the same
    // target note before the first one finishes.
    final appendInFlight = state.appendStatus == ClaimDraftAppendStatus.appending;
    state = state.copyWith(
      draft: result,
      saveStatus: newSaveStatus,
      clearSaveError: true,
      appendStatus: appendInFlight
          ? null
          : matchesAppendedTarget
              ? ClaimDraftAppendStatus.appended
              : ClaimDraftAppendStatus.idle,
      clearAppendError: !appendInFlight,
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
    if (state.isDraftAlreadyAppendedAnywhere) return ClaimDraftSaveOutcome.ignored;
    if (state.appendStatus == ClaimDraftAppendStatus.appending) return ClaimDraftSaveOutcome.ignored;
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

  /// Selects the note to append to. Ignored while an append is in flight so
  /// a target change cannot race with the in-flight [updateNote].
  void selectTargetNote(String? noteId) {
    if (state.appendStatus == ClaimDraftAppendStatus.appending) return;

    final matchesAppendedTarget = noteId != null &&
        state.draft != null &&
        (state.appendedTargetsByContent[state.draft!.markdownContent]
                ?.contains(noteId) ??
            false);
    state = state.copyWith(
      targetNoteId: noteId,
      clearTargetNoteId: noteId == null,
      appendStatus: matchesAppendedTarget
          ? ClaimDraftAppendStatus.appended
          : ClaimDraftAppendStatus.idle,
      clearAppendError: true,
    );
  }

  /// Appends [ClaimReviewSessionState.draft] to an existing note chosen via
  /// [selectTargetNote]. Does nothing when the draft is not saveable, already
  /// appended to this target, or an append is already in flight.
  Future<void> appendToExistingNote() async {
    final draft = state.draft;
    if (draft == null || !draft.shouldSave) return;
    if (state.appendStatus == ClaimDraftAppendStatus.appending) return;
    if (state.isDraftAlreadySaved) return;
    if (state.pendingDraftContents.contains(draft.markdownContent)) return;
    if (_ref.read(noteDraftReviewProvider).status == NoteDraftReviewStatus.saving) return;
    if (state.isDraftAlreadyAppended) return;

    final targetNoteId = state.targetNoteId;
    if (targetNoteId == null || targetNoteId.isEmpty) {
      state = state.copyWith(
        appendStatus: ClaimDraftAppendStatus.error,
        appendErrorMessage: 'Select a target note before appending.',
      );
      return;
    }

    final appendSessionId = _requestSequence;

    state = state.copyWith(
      appendStatus: ClaimDraftAppendStatus.appending,
      clearAppendError: true,
      clearBackgroundAppendError: true,
    );

    try {
      final repository = _ref.read(noteDraftReviewRepositoryProvider);
      final existingNote = await repository.getNoteById(targetNoteId);
      if (appendSessionId != _requestSequence) return;
      if (existingNote == null) {
        state = state.copyWith(
          appendStatus: ClaimDraftAppendStatus.error,
          appendErrorMessage: 'Selected target note no longer exists.',
        );
        return;
      }

      final updatedNote = existingNote.copyWith(
        content: _appendDraftMarkdown(existingNote.content, draft),
        updatedAt: DateTime.now(),
        embeddingPending: true,
        clearEmbedding: true,
      );
      await repository.updateNote(updatedNote);
      if (appendSessionId != _requestSequence) return;

      final matchesCurrentDraft =
          state.draft?.markdownContent == draft.markdownContent;
      final existingTargets =
          state.appendedTargetsByContent[draft.markdownContent] ??
              const <String>{};
      // Release the appending lock when the draft changed mid-write (e.g.
      // the user toggled a claim). The write succeeded, so record the target,
      // but reset to idle rather than leaving appendStatus stuck at appending.
      state = state.copyWith(
        appendStatus: matchesCurrentDraft
            ? ClaimDraftAppendStatus.appended
            : ClaimDraftAppendStatus.idle,
        appendedTargetsByContent: {
          ...state.appendedTargetsByContent,
          draft.markdownContent: {...existingTargets, targetNoteId},
        },
      );
    } catch (_) {
      if (appendSessionId != _requestSequence) return;
      if (state.draft?.markdownContent != draft.markdownContent) {
        // Draft changed mid-write and the write failed; release the lock and
        // surface a background error rather than silently swallowing it.
        state = state.copyWith(
          appendStatus: ClaimDraftAppendStatus.idle,
          backgroundAppendError:
              'An append failed while you were editing. The target note was not updated.',
        );
        return;
      }
      state = state.copyWith(
        appendStatus: ClaimDraftAppendStatus.error,
        appendErrorMessage: 'Failed to append. Try again.',
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
