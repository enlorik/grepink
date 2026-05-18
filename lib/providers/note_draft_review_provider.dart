import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_draft.dart';
import '../models/note_draft_review_state.dart';

class NoteDraftReviewNotifier extends StateNotifier<NoteDraftReviewState> {
  NoteDraftReviewNotifier() : super(const NoteDraftReviewState());

  void startReview(NoteDraft noteDraft) {
    state = NoteDraftReviewState(
      noteDraft: noteDraft,
      status: NoteDraftReviewStatus.reviewing,
      selectedDecision: _defaultDecisionFor(noteDraft.action),
    );
  }

  void selectDecision(NoteDraftReviewDecision decision) {
    state = state.copyWith(
      status: NoteDraftReviewStatus.reviewing,
      selectedDecision: decision,
      clearTargetNoteId: decision != NoteDraftReviewDecision.appendToExistingNote,
      clearError: true,
    );
  }

  void selectTargetNote(String? noteId) {
    state = state.copyWith(targetNoteId: noteId, clearError: true);
  }

  void markSaving() {
    if (!state.hasDraft) return;
    state = state.copyWith(
      status: NoteDraftReviewStatus.saving,
      clearError: true,
    );
  }

  void markSaved() {
    if (!state.hasDraft) return;
    state = state.copyWith(
      status: NoteDraftReviewStatus.saved,
      clearError: true,
    );
  }

  void discard() {
    if (!state.hasDraft) return;
    state = state.copyWith(
      status: NoteDraftReviewStatus.discarded,
      selectedDecision: NoteDraftReviewDecision.discard,
      clearTargetNoteId: true,
      clearError: true,
    );
  }

  void setError(String message) {
    state = state.copyWith(
      status: NoteDraftReviewStatus.error,
      errorMessage: message,
    );
  }

  void clear() {
    state = const NoteDraftReviewState();
  }

  NoteDraftReviewDecision _defaultDecisionFor(NoteDraftAction action) {
    return switch (action) {
      NoteDraftAction.createNewNote => NoteDraftReviewDecision.saveAsNewNote,
      NoteDraftAction.appendToExistingNote =>
        NoteDraftReviewDecision.appendToExistingNote,
      NoteDraftAction.doNotSave => NoteDraftReviewDecision.discard,
    };
  }
}

final noteDraftReviewProvider =
    StateNotifierProvider<NoteDraftReviewNotifier, NoteDraftReviewState>(
  (ref) => NoteDraftReviewNotifier(),
);
