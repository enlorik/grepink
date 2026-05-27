import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_draft.dart';
import '../models/note_draft_review_state.dart';
import '../models/note.dart';
import '../services/database_service.dart';
import 'notes_provider.dart';

abstract class NoteDraftReviewRepository {
  Future<Note> insertNote({required String title, required String content});
  Future<void> updateNote(Note note);
  Future<Note?> getNoteById(String id);
}

class NotesNotifierNoteDraftReviewRepository
    implements NoteDraftReviewRepository {
  final NotesNotifier _notesNotifier;

  NotesNotifierNoteDraftReviewRepository(this._notesNotifier);

  @override
  Future<Note> insertNote({required String title, required String content}) =>
      _notesNotifier.addNote(title: title, content: content);

  @override
  Future<void> updateNote(Note note) => _notesNotifier.updateNote(note);

  @override
  Future<Note?> getNoteById(String id) =>
      DatabaseService.instance.getNoteById(id);
}

final noteDraftReviewRepositoryProvider = Provider<NoteDraftReviewRepository>(
  (ref) => NotesNotifierNoteDraftReviewRepository(
    ref.read(notesProvider.notifier),
  ),
);

class NoteDraftReviewNotifier extends StateNotifier<NoteDraftReviewState> {
  final NoteDraftReviewRepository _repository;

  NoteDraftReviewNotifier({
    required NoteDraftReviewRepository repository,
  })  : _repository = repository,
        super(const NoteDraftReviewState());

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
      clearDraft: true,
      clearTargetNoteId: true,
      clearError: true,
    );
  }

  Future<Note?> saveAsNewNote() async {
    final draft = state.noteDraft;
    if (draft == null) return null;

    state = state.copyWith(
      status: NoteDraftReviewStatus.saving,
      selectedDecision: NoteDraftReviewDecision.saveAsNewNote,
      clearError: true,
    );

    try {
      final note = await _repository.insertNote(
        title: _titleFor(draft),
        content: _buildGeneratedNoteMarkdown(
          draft,
          action: NoteDraftAction.createNewNote,
          generatedAt: DateTime.now(),
        ),
      );
      state = state.copyWith(status: NoteDraftReviewStatus.saved);
      return note;
    } catch (error) {
      state = state.copyWith(
        status: NoteDraftReviewStatus.error,
        errorMessage: error.toString(),
      );
      return null;
    }
  }

  Future<Note?> appendToExistingNote() async {
    final draft = state.noteDraft;
    final targetNoteId = state.targetNoteId;
    if (draft == null) return null;
    if (targetNoteId == null || targetNoteId.isEmpty) {
      state = state.copyWith(
        status: NoteDraftReviewStatus.error,
        errorMessage: 'Select a target note before appending.',
      );
      return null;
    }

    state = state.copyWith(
      status: NoteDraftReviewStatus.saving,
      selectedDecision: NoteDraftReviewDecision.appendToExistingNote,
      clearError: true,
    );

    try {
      final existingNote = await _repository.getNoteById(targetNoteId);
      if (existingNote == null) {
        state = state.copyWith(
          status: NoteDraftReviewStatus.error,
          errorMessage: 'Selected target note no longer exists.',
        );
        return null;
      }

      final now = DateTime.now();
      final updatedNote = existingNote.copyWith(
        content: _appendDraftMarkdown(
          existingNote.content,
          draft,
          generatedAt: now,
        ),
        updatedAt: now,
        embeddingPending: true,
        clearEmbedding: true,
      );

      await _repository.updateNote(updatedNote);
      state = state.copyWith(status: NoteDraftReviewStatus.saved);
      return updatedNote;
    } catch (error) {
      state = state.copyWith(
        status: NoteDraftReviewStatus.error,
        errorMessage: error.toString(),
      );
      return null;
    }
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

  String _titleFor(NoteDraft draft) {
    final compactQuestion = draft.question.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compactQuestion.isEmpty) return 'Generated note';
    if (compactQuestion.length <= 80) return compactQuestion;
    return '${compactQuestion.substring(0, 77)}...';
  }

  String _buildGeneratedNoteMarkdown(
    NoteDraft draft, {
    required NoteDraftAction action,
    required DateTime generatedAt,
  }) {
    final trimmedDraft = draft.markdownContent.trim();
    final metadataComment = _buildGeneratedMetadataComment(
      draft,
      action: action,
      generatedAt: generatedAt,
    );

    return '$metadataComment\n\n$trimmedDraft';
  }

  String _buildGeneratedMetadataComment(
    NoteDraft draft, {
    required NoteDraftAction action,
    required DateTime generatedAt,
  }) {
    final sanitizedQuestion = _sanitizeMetadataValue(draft.question);
    final generatedAtValue = generatedAt.toUtc().toIso8601String();
    final sourceCount = draft.localEvidence.length + draft.webEvidence.length;

    return '''<!-- grepink-generated-note
question: $sanitizedQuestion
generated_at: $generatedAtValue
action: ${action.name}
source_count: $sourceCount
-->''';
  }

  String _sanitizeMetadataValue(String value) {
    final compactValue = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compactValue.replaceAll('--', '- -');
  }

  String _appendDraftMarkdown(
    String existingContent,
    NoteDraft draft, {
    required DateTime generatedAt,
  }) {
    final trimmedExisting = existingContent.trimRight();
    final trimmedDraft = draft.markdownContent.trim();
    final updateHeader = '## Update from question: ${draft.question.trim()}';
    final metadataComment = _buildGeneratedMetadataComment(
      draft,
      action: NoteDraftAction.appendToExistingNote,
      generatedAt: generatedAt,
    );

    if (trimmedExisting.isEmpty) {
      return '$metadataComment\n\n$updateHeader\n\n$trimmedDraft';
    }

    return '$trimmedExisting\n\n---\n\n$metadataComment\n\n$updateHeader\n\n$trimmedDraft';
  }
}

final noteDraftReviewProvider =
    StateNotifierProvider<NoteDraftReviewNotifier, NoteDraftReviewState>(
  (ref) => NoteDraftReviewNotifier(
    repository: ref.watch(noteDraftReviewRepositoryProvider),
  ),
);
