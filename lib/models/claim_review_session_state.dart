import 'claim_review_item.dart';
import 'grounded_answer.dart';
import '../services/selected_claims_draft_builder.dart';

enum ClaimReviewSessionStatus { idle, loading, success, error }

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
    this.targetNoteId,
    this.appendStatus = ClaimDraftAppendStatus.idle,
    this.appendErrorMessage,
    this.appendedTargetsByContent = const {},
  });

  bool get isLoading => status == ClaimReviewSessionStatus.loading;
  bool get isSuccess => status == ClaimReviewSessionStatus.success;
  bool get isError => status == ClaimReviewSessionStatus.error;

  bool get hasReviewItems =>
      groups.any((group) => group.items.isNotEmpty);

  /// True when the current [draft]'s content was already saved this session,
  /// so a repeat save would create a duplicate note.
  bool get isDraftAlreadySaved =>
      draft != null &&
      savedDraftContents.contains(draft!.markdownContent);

  /// True when the current [draft] has already been appended to the currently
  /// selected [targetNoteId]. Keyed by content so switching between distinct
  /// drafts never loses earlier history for a given content+target pair.
  bool get isDraftAlreadyAppended =>
      draft != null &&
      targetNoteId != null &&
      (appendedTargetsByContent[draft!.markdownContent]?.contains(targetNoteId) ??
          false);

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
    String? targetNoteId,
    ClaimDraftAppendStatus? appendStatus,
    String? appendErrorMessage,
    Map<String, Set<String>>? appendedTargetsByContent,
    bool clearSelection = false,
    bool clearError = false,
    bool clearDraft = false,
    bool clearSaveError = false,
    bool clearBackgroundSaveError = false,
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
