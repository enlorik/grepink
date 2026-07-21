import 'claim_deduplication_result.dart';
import 'claim_review_item.dart';
import 'grounded_answer.dart';
import '../services/selected_claims_draft_builder.dart';

enum ClaimReviewSessionStatus {
  idle,
  loading,
  success,
  error,

  /// No real [GroundedAnswerProvider] is configured. The pipeline did not run;
  /// this is distinct from [error] (pipeline ran but threw) and from [idle]
  /// (nothing was asked yet).
  providerNotConfigured,
}

enum ClaimDraftSaveStatus { idle, saving, saved, error }

enum ClaimDraftSaveOutcome { success, failure, cancelled, ignored }

enum ClaimDraftAppendStatus { idle, appending, appended, error }

class ClaimReviewSessionState {
  final ClaimReviewSessionStatus status;
  final String question;
  final List<ClaimReviewGroup> groups;
  final ClaimReviewSelectionState? selection;
  final String? errorMessage;
  final String providerName;
  final List<GroundedAnswerCitation> citations;
  final ClaimDraftResult? draft;
  final ClaimDraftSaveStatus saveStatus;
  final String? saveErrorMessage;
  final Set<String> savedDraftContents;
  // Contents whose repository write is currently in flight. Cleared on
  // completion (success or failure). Kept separate from savedDraftContents
  // so the UI can distinguish "saving now" from "already saved".
  final Set<String> pendingDraftContents;
  // Non-null when a background save (started while the user was on a different
  // draft) failed. Independent of saveStatus so the active draft is not
  // incorrectly flagged. Cleared when the next save attempt begins.
  final String? backgroundSaveError;
  // Non-null when a background append (started while the user was on a
  // different draft) failed. Cleared when the next append attempt begins.
  final String? backgroundAppendError;
  // Non-null when generateDraft() throws. Holds a safe, user-facing message
  // only -- never the raw exception. Cleared on the next successful draft
  // generation or when runReview starts a new session.
  final String? draftGenerationErrorMessage;
  // Append-to-existing-note state.
  final String? targetNoteId;
  final ClaimDraftAppendStatus appendStatus;
  final String? appendErrorMessage;
  // Maps draft content → set of note IDs that content has been appended to.
  // Keyed by content (not a single slot) so switching between distinct drafts
  // never loses earlier append history.
  final Map<String, Set<String>> appendedTargetsByContent;

  const ClaimReviewSessionState({
    this.status = ClaimReviewSessionStatus.idle,
    this.question = '',
    this.groups = const [],
    this.selection,
    this.errorMessage,
    this.providerName = '',
    this.citations = const [],
    this.draft,
    this.saveStatus = ClaimDraftSaveStatus.idle,
    this.saveErrorMessage,
    this.savedDraftContents = const {},
    this.pendingDraftContents = const {},
    this.backgroundSaveError,
    this.backgroundAppendError,
    this.draftGenerationErrorMessage,
    this.targetNoteId,
    this.appendStatus = ClaimDraftAppendStatus.idle,
    this.appendErrorMessage,
    this.appendedTargetsByContent = const {},
  });

  bool get isLoading => status == ClaimReviewSessionStatus.loading;
  bool get isSuccess => status == ClaimReviewSessionStatus.success;
  bool get isError => status == ClaimReviewSessionStatus.error;
  bool get isProviderNotConfigured =>
      status == ClaimReviewSessionStatus.providerNotConfigured;

  bool get hasReviewItems => groups.any((group) => group.items.isNotEmpty);

  /// True when the current [draft]'s content was already saved this session,
  /// so a repeat save would create a duplicate note.
  bool get isDraftAlreadySaved =>
      draft != null && savedDraftContents.contains(draft!.markdownContent);

  /// True when the current [draft] has already been appended to the currently
  /// selected [targetNoteId]. Keyed by content so switching between distinct
  /// drafts never loses earlier history for a given content+target pair.
  bool get isDraftAlreadyAppended =>
      draft != null &&
      targetNoteId != null &&
      (appendedTargetsByContent[draft!.markdownContent]
              ?.contains(targetNoteId) ??
          false);

  /// True when the current [draft] has been appended to at least one note this
  /// session. Used to block saving after appending so the same generated
  /// markdown is not persisted twice via the two different actions.
  bool get isDraftAlreadyAppendedAnywhere =>
      draft != null &&
      (appendedTargetsByContent[draft!.markdownContent]?.isNotEmpty ?? false);

  /// True when a save repository write is currently in flight.
  /// More reliable than checking [saveStatus] == saving because [toggle]
  /// resets [saveStatus] to idle even while [insertNote] is still awaiting.
  bool get isSaveInFlight => pendingDraftContents.isNotEmpty;

  /// True when the review succeeded but the provider returned no grounded
  /// answer at all. Distinct from [hasNoClaimsExtracted] (answer returned,
  /// but the extractor found nothing) and from an unconfigured provider
  /// (which skips the pipeline entirely and stays in the idle state).
  bool get hasNoAnswer => isSuccess && !hasReviewItems && providerName.isEmpty;

  /// True when the review succeeded, a grounded answer was returned, but
  /// no claims could be extracted from it.
  bool get hasNoClaimsExtracted =>
      isSuccess && !hasReviewItems && providerName.isNotEmpty;

  /// True when the review succeeded and claims were found, but every single
  /// one was classified as already known — nothing new to save.
  bool get isAllClaimsAlreadyKnown =>
      isSuccess &&
      hasReviewItems &&
      groups
          .where((g) =>
              g.classification != ClaimNoveltyClassification.alreadyKnown)
          .every((g) => g.items.isEmpty);

  ClaimReviewSessionState copyWith({
    ClaimReviewSessionStatus? status,
    String? question,
    List<ClaimReviewGroup>? groups,
    ClaimReviewSelectionState? selection,
    String? errorMessage,
    String? providerName,
    List<GroundedAnswerCitation>? citations,
    ClaimDraftResult? draft,
    ClaimDraftSaveStatus? saveStatus,
    String? saveErrorMessage,
    Set<String>? savedDraftContents,
    Set<String>? pendingDraftContents,
    String? backgroundSaveError,
    String? backgroundAppendError,
    String? draftGenerationErrorMessage,
    String? targetNoteId,
    ClaimDraftAppendStatus? appendStatus,
    String? appendErrorMessage,
    Map<String, Set<String>>? appendedTargetsByContent,
    bool clearSelection = false,
    bool clearError = false,
    bool clearDraft = false,
    bool clearSaveError = false,
    bool clearBackgroundSaveError = false,
    bool clearBackgroundAppendError = false,
    bool clearDraftGenerationError = false,
    bool clearTargetNoteId = false,
    bool clearAppendError = false,
  }) {
    return ClaimReviewSessionState(
      status: status ?? this.status,
      question: question ?? this.question,
      groups: groups ?? this.groups,
      selection: clearSelection ? null : (selection ?? this.selection),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      providerName: providerName ?? this.providerName,
      citations: citations ?? this.citations,
      draft: clearDraft ? null : (draft ?? this.draft),
      saveStatus: saveStatus ?? this.saveStatus,
      saveErrorMessage:
          clearSaveError ? null : (saveErrorMessage ?? this.saveErrorMessage),
      savedDraftContents: savedDraftContents ?? this.savedDraftContents,
      pendingDraftContents: pendingDraftContents ?? this.pendingDraftContents,
      backgroundSaveError: clearBackgroundSaveError
          ? null
          : (backgroundSaveError ?? this.backgroundSaveError),
      backgroundAppendError: clearBackgroundAppendError
          ? null
          : (backgroundAppendError ?? this.backgroundAppendError),
      draftGenerationErrorMessage: clearDraftGenerationError
          ? null
          : (draftGenerationErrorMessage ?? this.draftGenerationErrorMessage),
      targetNoteId:
          clearTargetNoteId ? null : (targetNoteId ?? this.targetNoteId),
      appendStatus: appendStatus ?? this.appendStatus,
      appendErrorMessage: clearAppendError
          ? null
          : (appendErrorMessage ?? this.appendErrorMessage),
      appendedTargetsByContent:
          appendedTargetsByContent ?? this.appendedTargetsByContent,
    );
  }
}
