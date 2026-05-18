import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/note_draft.dart';
import '../models/note_draft_review_state.dart';
import '../models/note.dart';
import '../services/database_service.dart';

abstract class NoteDraftReviewRepository {
  Future<void> insertNote(Note note);
  Future<void> updateNote(Note note);
  Future<Note?> getNoteById(String id);
}

class DatabaseNoteDraftReviewRepository implements NoteDraftReviewRepository {
  final DatabaseService _databaseService;

  DatabaseNoteDraftReviewRepository({DatabaseService? databaseService})
      : _databaseService = databaseService ?? DatabaseService.instance;

  @override
  Future<Note?> getNoteById(String id) => _databaseService.getNoteById(id);

  @override
  Future<void> insertNote(Note note) => _databaseService.insertNote(note);

  @override
  Future<void> updateNote(Note note) => _databaseService.updateNote(note);
}

final noteDraftReviewRepositoryProvider = Provider<NoteDraftReviewRepository>(
  (ref) => DatabaseNoteDraftReviewRepository(),
);

class NoteDraftReviewNotifier extends StateNotifier<NoteDraftReviewState> {
  final NoteDraftReviewRepository _repository;
  final Uuid _uuid;

  NoteDraftReviewNotifier({
    required NoteDraftReviewRepository repository,
    Uuid? uuid,
  })  : _repository = repository,
        _uuid = uuid ?? const Uuid(),
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

    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: _titleFor(draft),
      content: draft.markdownContent.trim(),
      tags: const [],
      keywords: const [],
      isPinned: false,
      createdAt: now,
      updatedAt: now,
      embeddingPending: true,
    );

    try {
      await _repository.insertNote(note);
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

      final updatedNote = existingNote.copyWith(
        content: _appendDraftMarkdown(existingNote.content, draft),
        updatedAt: DateTime.now(),
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

  String _appendDraftMarkdown(String existingContent, NoteDraft draft) {
    final trimmedExisting = existingContent.trimRight();
    final trimmedDraft = draft.markdownContent.trim();
    final updateHeader = '## Update from question: ${draft.question.trim()}';

    if (trimmedExisting.isEmpty) {
      return '$updateHeader\n\n$trimmedDraft';
    }

    return '$trimmedExisting\n\n---\n\n$updateHeader\n\n$trimmedDraft';
  }
}

final noteDraftReviewProvider =
    StateNotifierProvider<NoteDraftReviewNotifier, NoteDraftReviewState>(
  (ref) => NoteDraftReviewNotifier(
    repository: ref.watch(noteDraftReviewRepositoryProvider),
  ),
);
