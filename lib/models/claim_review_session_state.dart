import 'claim_review_item.dart';

enum ClaimReviewSessionStatus { idle, loading, success, error }

class ClaimReviewSessionState {
  final ClaimReviewSessionStatus status;
  final String question;
  final List<ClaimReviewGroup> groups;
  final ClaimReviewSelectionState? selection;
  final String? errorMessage;

  const ClaimReviewSessionState({
    this.status = ClaimReviewSessionStatus.idle,
    this.question = '',
    this.groups = const [],
    this.selection,
    this.errorMessage,
  });

  bool get isLoading => status == ClaimReviewSessionStatus.loading;
  bool get isSuccess => status == ClaimReviewSessionStatus.success;
  bool get isError => status == ClaimReviewSessionStatus.error;

  bool get hasReviewItems =>
      groups.any((group) => group.items.isNotEmpty);

  ClaimReviewSessionState copyWith({
    ClaimReviewSessionStatus? status,
    String? question,
    List<ClaimReviewGroup>? groups,
    ClaimReviewSelectionState? selection,
    String? errorMessage,
    bool clearSelection = false,
    bool clearError = false,
  }) {
    return ClaimReviewSessionState(
      status: status ?? this.status,
      question: question ?? this.question,
      groups: groups ?? this.groups,
      selection: clearSelection ? null : (selection ?? this.selection),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
