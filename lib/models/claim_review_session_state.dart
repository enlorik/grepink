import 'claim_deduplication_result.dart';
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
  final Set<String> savedDraftContents;
  final String? targetNoteId;
  final ClaimDraftAppendStatus appendStatus;
  final String? appendErrorMessage;
  final Map<String, Set<String>> appendedTargetsByContent;

  /// True from the moment a save/append repository call actually starts
  /// until it actually resolves. Unlike [saveStatus]/[appendStatus] (which
  /// [toggle]/[generateDraft] on the notifier legitimately reset to idle to
  /// reflect the currently-displayed draft), these are never reset except by
  /// the write itself finishing, so other guards (the Discard button,
  /// switching the append target) can tell a real write is still in flight
  /// even after the displayed status has moved on.
  final bool isSaveInFlight;
  final bool isAppendInFlight;

  /// Set when building a markdown draft from the current selection throws.
  /// Holds a safe, user-facing message only -- never the raw exception.
  final String? draftGenerationErrorMessage;

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
    this.targetNoteId,
    this.appendStatus = ClaimDraftAppendStatus.idle,
    this.appendErrorMessage,
    this.appendedTargetsByContent = const {},
    this.isSaveInFlight = false,
    this.isAppendInFlight = false,
    this.draftGenerationErrorMessage,
  });

  bool get isLoading => status == ClaimReviewSessionStatus.loading;
  bool get isSuccess => status == ClaimReviewSessionStatus.success;
  bool get isError => status == ClaimReviewSessionStatus.error;

  bool get hasReviewItems =>
      groups.any((group) => group.items.isNotEmpty);

  /// True when the ask succeeded but no grounded answer came back at all
  /// (as opposed to an answer that yielded zero claims -- see
  /// [hasNoClaimsExtracted]).
  bool get hasNoAnswer =>
      isSuccess && !hasReviewItems && providerName.isEmpty;

  /// True when the ask succeeded and a grounded answer came back, but no
  /// claims could be extracted from it.
  bool get hasNoClaimsExtracted =>
      isSuccess && !hasReviewItems && providerName.isNotEmpty;

  /// True when every extracted claim was classified as already known, so
  /// there is nothing new worth reviewing or saving.
  bool get isAllClaimsAlreadyKnown =>
      isSuccess &&
      hasReviewItems &&
      groups
          .where((g) => g.classification != ClaimNoveltyClassification.alreadyKnown)
          .every((g) => g.items.isEmpty);

  /// True when the current [draft] has already been saved and hasn't
  /// changed since, so a repeat save would create a duplicate note. Tracks
  /// every distinct draft content that has been saved (not just the most
  /// recent one), so saving draft A, then draft B, then returning to A is
  /// still recognized as already-saved instead of allowing a duplicate.
  bool get isDraftAlreadySaved =>
      saveStatus == ClaimDraftSaveStatus.saved &&
      draft != null &&
      savedDraftContents.contains(draft!.markdownContent);

  /// True when the current [draft] has already been appended to the
  /// currently selected target note and neither has changed since, so a
  /// repeat append would duplicate that content in the same note. Tracks
  /// every note each distinct draft content has been appended to (keyed by
  /// content), so appending draft X to A, generating a different draft Y,
  /// then returning to X is still recognized as already-appended for X/A
  /// rather than losing that history.
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
    String? targetNoteId,
    ClaimDraftAppendStatus? appendStatus,
    String? appendErrorMessage,
    Map<String, Set<String>>? appendedTargetsByContent,
    bool? isSaveInFlight,
    bool? isAppendInFlight,
    String? draftGenerationErrorMessage,
    bool clearSelection = false,
    bool clearError = false,
    bool clearDraft = false,
    bool clearSaveError = false,
    bool clearTargetNoteId = false,
    bool clearAppendError = false,
    bool clearDraftGenerationError = false,
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
      targetNoteId:
          clearTargetNoteId ? null : (targetNoteId ?? this.targetNoteId),
      appendStatus: appendStatus ?? this.appendStatus,
      appendErrorMessage: clearAppendError
          ? null
          : (appendErrorMessage ?? this.appendErrorMessage),
      appendedTargetsByContent:
          appendedTargetsByContent ?? this.appendedTargetsByContent,
      isSaveInFlight: isSaveInFlight ?? this.isSaveInFlight,
      isAppendInFlight: isAppendInFlight ?? this.isAppendInFlight,
      draftGenerationErrorMessage: clearDraftGenerationError
          ? null
          : (draftGenerationErrorMessage ?? this.draftGenerationErrorMessage),
    );
  }
}
