import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../services/database_service.dart';
import '../services/embedding_service.dart';
import 'settings_provider.dart';

class NotesNotifier extends StateNotifier<AsyncValue<List<Note>>> {
  final Ref _ref;

  NotesNotifier(this._ref) : super(const AsyncValue.loading()) {
    loadNotes();
  }

  Future<void> loadNotes() async {
    state = const AsyncValue.loading();
    try {
      final notes = await DatabaseService.instance.getAllNotes();
      state = AsyncValue.data(notes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Note> addNote({
    required String title,
    required String content,
    List<String> tags = const [],
    List<String> keywords = const [],
  }) async {
    final note = Note(
      id: const Uuid().v4(),
      title: title.isEmpty ? 'Untitled' : title,
      content: content,
      tags: tags,
      keywords: keywords,
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      embeddingPending: true,
    );
    await DatabaseService.instance.insertNote(note);
    await loadNotes();
    _triggerEmbedding(note);
    return note;
  }

  Future<void> updateNote(Note note) async {
    final updated = note.copyWith(
      updatedAt: DateTime.now(),
      embeddingPending: true,
    );
    await DatabaseService.instance.updateNote(updated);
    await loadNotes();
    _triggerEmbedding(updated);
  }

  Future<void> deleteNote(String id) async {
    await DatabaseService.instance.deleteNote(id);
    await loadNotes();
  }

  Future<void> togglePin(String id) async {
    final notes = state.valueOrNull ?? [];
    final note = notes.firstWhere((n) => n.id == id);
    final updated = note.copyWith(isPinned: !note.isPinned, updatedAt: DateTime.now());
    await DatabaseService.instance.updateNote(updated);
    await loadNotes();
  }

  Future<void> reindexEmbeddings() async {
    final settings = await _ref.read(settingsProvider.future);
    final apiKey = settings.apiKey;
    if (apiKey.isEmpty) return;

    final notes = state.valueOrNull ?? [];
    for (final note in notes) {
      try {
        final embedding = await EmbeddingService.instance.embedNote(note, apiKey);
        await DatabaseService.instance.updateEmbedding(note.id, embedding);
      } catch (_) {
        // Continue with next note
      }
    }
    await loadNotes();
  }

  void _triggerEmbedding(Note note) async {
    try {
      final settings = await _ref.read(settingsProvider.future);
      final apiKey = settings.apiKey;
      if (apiKey.isEmpty) return;
      final embedding = await EmbeddingService.instance.embedNote(note, apiKey);
      await DatabaseService.instance.updateEmbedding(note.id, embedding);
      await loadNotes();
    } catch (_) {
      // Silently fail - embedding will be retried on reindex
    }
  }
}

final notesProvider = StateNotifierProvider<NotesNotifier, AsyncValue<List<Note>>>(
  (ref) => NotesNotifier(ref),
);

final pinnedNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(notesProvider).valueOrNull ?? [];
  return notes.where((n) => n.isPinned).toList();
});

final unpinnedNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(notesProvider).valueOrNull ?? [];
  return notes.where((n) => !n.isPinned).toList();
});
