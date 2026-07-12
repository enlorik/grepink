import 'claim_review_item.dart';
import 'grounded_answer.dart';
import '../services/selected_claims_draft_builder.dart';

enum ClaimReviewSessionStatus { idle, loading, success, error }

enum ClaimDraftSaveStatus { idle, saving, saved, error }

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
    bool clearSelection = false,
    bool clearError = false,
    bool clearDraft = false,
    bool clearSaveError = false,
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
    );
  }
}
