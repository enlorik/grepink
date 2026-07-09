import 'claim_review_item.dart';
import 'grounded_answer.dart';
import '../services/selected_claims_draft_builder.dart';

enum ClaimReviewSessionStatus { idle, loading, success, error }

enum ClaimDraftSaveStatus { idle, saving, saved, error }

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
  final String? savedDraftContent;
  final String? targetNoteId;
  final ClaimDraftAppendStatus appendStatus;
  final String? appendErrorMessage;
  final String? appendedDraftContent;
  final Set<String> appendedTargetNoteIds;

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
    this.savedDraftContent,
    this.targetNoteId,
    this.appendStatus = ClaimDraftAppendStatus.idle,
    this.appendErrorMessage,
    this.appendedDraftContent,
    this.appendedTargetNoteIds = const {},
  });

  bool get isLoading => status == ClaimReviewSessionStatus.loading;
  bool get isSuccess => status == ClaimReviewSessionStatus.success;
  bool get isError => status == ClaimReviewSessionStatus.error;

  bool get hasReviewItems =>
      groups.any((group) => group.items.isNotEmpty);

  /// True when the current [draft] has already been saved and hasn't
  /// changed since, so a repeat save would create a duplicate note.
  bool get isDraftAlreadySaved =>
      saveStatus == ClaimDraftSaveStatus.saved &&
      draft != null &&
      savedDraftContent == draft!.markdownContent;

  /// True when the current [draft] has already been appended to the
  /// currently selected target note and neither has changed since, so a
  /// repeat append would duplicate that content in the same note. Tracks
  /// every note this exact content has been appended to (not just the most
  /// recent one), so appending to A then B then switching back to A is
  /// still recognized as already done.
  bool get isDraftAlreadyAppended =>
      draft != null &&
      targetNoteId != null &&
      appendedDraftContent == draft!.markdownContent &&
      appendedTargetNoteIds.contains(targetNoteId);

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
    String? savedDraftContent,
    String? targetNoteId,
    ClaimDraftAppendStatus? appendStatus,
    String? appendErrorMessage,
    String? appendedDraftContent,
    Set<String>? appendedTargetNoteIds,
    bool clearSelection = false,
    bool clearError = false,
    bool clearDraft = false,
    bool clearSaveError = false,
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
      savedDraftContent: savedDraftContent ?? this.savedDraftContent,
      targetNoteId:
          clearTargetNoteId ? null : (targetNoteId ?? this.targetNoteId),
      appendStatus: appendStatus ?? this.appendStatus,
      appendErrorMessage: clearAppendError
          ? null
          : (appendErrorMessage ?? this.appendErrorMessage),
      appendedDraftContent: appendedDraftContent ?? this.appendedDraftContent,
      appendedTargetNoteIds:
          appendedTargetNoteIds ?? this.appendedTargetNoteIds,
    );
  }
}
