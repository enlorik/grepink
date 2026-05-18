import 'note_draft.dart';

enum NoteDraftReviewStatus { empty, reviewing, saving, saved, discarded, error }

enum NoteDraftReviewDecision {
  saveAsNewNote,
  appendToExistingNote,
  discard,
}

class NoteDraftReviewState {
  final NoteDraft? noteDraft;
  final NoteDraftReviewStatus status;
  final NoteDraftReviewDecision? selectedDecision;
  final String? targetNoteId;
  final String? errorMessage;

  const NoteDraftReviewState({
    this.noteDraft,
    this.status = NoteDraftReviewStatus.empty,
    this.selectedDecision,
    this.targetNoteId,
    this.errorMessage,
  });

  NoteDraftReviewState copyWith({
    NoteDraft? noteDraft,
    NoteDraftReviewStatus? status,
    NoteDraftReviewDecision? selectedDecision,
    String? targetNoteId,
    String? errorMessage,
    bool clearDraft = false,
    bool clearDecision = false,
    bool clearTargetNoteId = false,
    bool clearError = false,
  }) {
    return NoteDraftReviewState(
      noteDraft: clearDraft ? null : (noteDraft ?? this.noteDraft),
      status: status ?? this.status,
      selectedDecision: clearDecision
          ? null
          : (selectedDecision ?? this.selectedDecision),
      targetNoteId: clearTargetNoteId ? null : (targetNoteId ?? this.targetNoteId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  bool get hasDraft => noteDraft != null;
}
