import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/providers/knowledge_ingestion_provider.dart';
import 'package:grepink/providers/note_draft_review_provider.dart';
import 'package:grepink/providers/notes_provider.dart';
import 'package:grepink/screens/search_screen.dart';
import 'package:grepink/services/knowledge_ingestion_service.dart';

class _FakeKnowledgeIngestionService implements KnowledgeIngestionService {
  final Future<NoteDraft> Function(String question) _onIngest;

  _FakeKnowledgeIngestionService(this._onIngest);

  @override
  Future<NoteDraft> ingest(String question) => _onIngest(question);
}

class _PendingKnowledgeIngestionService implements KnowledgeIngestionService {
  final Map<String, Completer<NoteDraft>> _completers =
      <String, Completer<NoteDraft>>{};

  Completer<NoteDraft> completerFor(String question) {
    return _completers.putIfAbsent(question, () => Completer<NoteDraft>());
  }

  @override
  Future<NoteDraft> ingest(String question) => completerFor(question).future;
}

class _FakeNoteDraftReviewRepository implements NoteDraftReviewRepository {
  final Map<String, Note> notesById = <String, Note>{};
  int insertedNotes = 0;
  int updatedNotes = 0;

  @override
  Future<Note?> getNoteById(String id) async => notesById[id];

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    insertedNotes++;
    final now = DateTime(2026, 5, 18);
    final note = Note(
      id: 'generated-$insertedNotes',
      title: title,
      content: content,
      tags: const [],
      keywords: const [],
      isPinned: false,
      createdAt: now,
      updatedAt: now,
      embeddingPending: true,
    );
    notesById[note.id] = note;
    return note;
  }

  @override
  Future<void> updateNote(Note note) async {
    updatedNotes++;
    notesById[note.id] = note;
  }
}

NoteDraft _draft({
  required String question,
  required NoteDraftAction action,
}) {
  const evidence = EvidenceItem(
    id: 'web-1',
    type: EvidenceType.webSearch,
    title: 'Sourced result',
    content: 'Fresh sourced claim',
    sourceUrl: 'https://example.com/source',
  );

  return NoteDraft(
    question: question,
    markdownContent: '# Suggested draft\n\n- Fresh sourced claim',
    action: action,
    deltas: const [
      KnowledgeDelta(
        evidence: evidence,
        deltaType: DeltaType.newClaim,
        reason: 'new',
      ),
    ],
    localEvidence: const [],
    webEvidence: const [evidence],
  );
}

Note _note({
  required String id,
  required String title,
  required String content,
}) {
  final now = DateTime(2026, 5, 18);
  return Note(
    id: id,
    title: title,
    content: content,
    tags: const [],
    keywords: const [],
    isPinned: false,
    createdAt: now,
    updatedAt: now,
    embeddingPending: false,
  );
}

Future<ProviderContainer> _pumpSearchScreen(
  WidgetTester tester, {
  required KnowledgeIngestionService ingestionService,
  required _FakeNoteDraftReviewRepository repository,
  List<Note> notes = const <Note>[],
  List<Note> recentNotes = const <Note>[],
  void Function()? onRefresh,
}) async {
  final container = ProviderContainer(
    overrides: [
      knowledgeIngestionServiceProvider.overrideWith(
        (ref) async => ingestionService,
      ),
      noteDraftReviewRepositoryProvider.overrideWithValue(repository),
      allNotesProvider.overrideWithValue(notes),
      recentNotesProvider.overrideWithValue(recentNotes),
      refreshNotesProvider.overrideWithValue(() async {
        onRefresh?.call();
      }),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SearchScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(container.dispose);
  return container;
}

Future<void> _askQuestion(WidgetTester tester, String question) async {
  await tester.enterText(find.byKey(const Key('ask-question-field')), question);
  await tester.pump();
  await tester.tap(find.byKey(const Key('ask-question-button')));
  await tester.pump();
}

void main() {
  group('SearchScreen ask flow', () {
    testWidgets('shows loading and then the draft review panel', (tester) async {
      final completer = Completer<NoteDraft>();
      final repository = _FakeNoteDraftReviewRepository();

      await _pumpSearchScreen(
        tester,
        ingestionService: _FakeKnowledgeIngestionService((_) => completer.future),
        repository: repository,
      );

      await _askQuestion(tester, 'What changed?');

      expect(find.text('Generating draft...'), findsOneWidget);
      final askButton = tester.widget<FilledButton>(
        find.byKey(const Key('ask-question-button')),
      );
      expect(askButton.onPressed, isNull);

      completer.complete(
        _draft(
          question: 'What changed?',
          action: NoteDraftAction.createNewNote,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Draft Review'), findsOneWidget);
      expect(find.textContaining('Recommended action: Save as new note'),
          findsOneWidget);
    });

    testWidgets('shows the do-not-save state clearly', (tester) async {
      final repository = _FakeNoteDraftReviewRepository();

      await _pumpSearchScreen(
        tester,
        ingestionService: _FakeKnowledgeIngestionService(
          (_) async => _draft(
            question: 'Did I already know this?',
            action: NoteDraftAction.doNotSave,
          ),
        ),
        repository: repository,
      );

      await _askQuestion(tester, 'Did I already know this?');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No new knowledge was detected'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Recommended action: Discard'),
        findsOneWidget,
      );
    });

    testWidgets('save as new note calls review notifier persistence path',
        (tester) async {
      final repository = _FakeNoteDraftReviewRepository();
      var refreshCalls = 0;

      await _pumpSearchScreen(
        tester,
        ingestionService: _FakeKnowledgeIngestionService(
          (_) async => _draft(
            question: 'Save this',
            action: NoteDraftAction.createNewNote,
          ),
        ),
        repository: repository,
        onRefresh: () => refreshCalls++,
      );

      await _askQuestion(tester, 'Save this');
      await tester.pumpAndSettle();
      expect(repository.insertedNotes, 0);

      await tester.ensureVisible(find.text('Save as new note'));
      await tester.tap(find.text('Save as new note'));
      await tester.pumpAndSettle();

      expect(repository.insertedNotes, 1);
      expect(refreshCalls, 1);
      expect(find.text('Draft saved successfully.'), findsOneWidget);
    });

    testWidgets('append calls review notifier path after target selection',
        (tester) async {
      final repository = _FakeNoteDraftReviewRepository();
      repository.notesById['note-1'] = _note(
        id: 'note-1',
        title: 'Existing note',
        content: 'Existing content',
      );

      await _pumpSearchScreen(
        tester,
        ingestionService: _FakeKnowledgeIngestionService(
          (_) async => _draft(
            question: 'Append this',
            action: NoteDraftAction.appendToExistingNote,
          ),
        ),
        repository: repository,
        notes: [
          _note(
            id: 'note-1',
            title: 'Existing note',
            content: 'Existing content',
          ),
        ],
      );

      await _askQuestion(tester, 'Append this');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('append-target-dropdown')), findsOneWidget);
      expect(repository.updatedNotes, 0);

      await tester.tap(find.byKey(const Key('append-target-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing note').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Append to existing note'));
      await tester.tap(find.text('Append to existing note'));
      await tester.pumpAndSettle();

      expect(repository.updatedNotes, 1);
      expect(find.text('Update appended successfully.'), findsOneWidget);
    });

    testWidgets('discard clears draft and does not persist', (tester) async {
      final repository = _FakeNoteDraftReviewRepository();

      await _pumpSearchScreen(
        tester,
        ingestionService: _FakeKnowledgeIngestionService(
          (_) async => _draft(
            question: 'Discard this',
            action: NoteDraftAction.createNewNote,
          ),
        ),
        repository: repository,
      );

      await _askQuestion(tester, 'Discard this');
      await tester.pumpAndSettle();
      expect(find.text('Draft Review'), findsOneWidget);

      await tester.ensureVisible(find.text('Discard'));
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(repository.insertedNotes, 0);
      expect(repository.updatedNotes, 0);
      expect(find.text('Draft Review'), findsNothing);
      expect(find.text('Draft discarded. Nothing was saved.'), findsAtLeastNWidgets(1));
    });

    testWidgets('loading disables asking again until the current draft resolves',
        (tester) async {
      final repository = _FakeNoteDraftReviewRepository();
      final service = _PendingKnowledgeIngestionService();

      await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repository,
      );

      await _askQuestion(tester, 'First question');
      final askButton = tester.widget<FilledButton>(
        find.byKey(const Key('ask-question-button')),
      );
      expect(askButton.onPressed, isNull);
      expect(find.text('Generating draft...'), findsOneWidget);

      service.completerFor('First question').complete(
            _draft(
              question: 'First question',
              action: NoteDraftAction.createNewNote,
            ),
          );
      await tester.pumpAndSettle();

      final enabledAskButton = tester.widget<FilledButton>(
        find.byKey(const Key('ask-question-button')),
      );
      expect(enabledAskButton.onPressed, isNotNull);
      expect(find.text('Draft Review'), findsOneWidget);
    });
  });

  group('SearchScreen layout smoke tests', () {
    Future<void> setSurface(WidgetTester tester, Size size) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    Future<void> pumpWithDraft(
      WidgetTester tester, {
      required NoteDraftAction action,
      List<Note> notes = const [],
    }) async {
      await _pumpSearchScreen(
        tester,
        ingestionService: _FakeKnowledgeIngestionService(
          (_) async => _draft(question: 'Layout test', action: action),
        ),
        repository: _FakeNoteDraftReviewRepository(),
        notes: notes,
      );
      await _askQuestion(tester, 'Layout test');
      await tester.pumpAndSettle();
    }

    // ── phone ──────────────────────────────────────────────────────────────

    testWidgets('phone – ask form fields are accessible', (tester) async {
      await setSurface(tester, const Size(360, 640));
      await _pumpSearchScreen(
        tester,
        ingestionService: _FakeKnowledgeIngestionService((_) async => _draft(
              question: 'x',
              action: NoteDraftAction.createNewNote,
            )),
        repository: _FakeNoteDraftReviewRepository(),
      );

      expect(find.byKey(const Key('ask-question-field')), findsOneWidget);
      expect(find.byKey(const Key('ask-question-button')), findsOneWidget);
    });

    testWidgets('phone – loading indicator is accessible', (tester) async {
      await setSurface(tester, const Size(360, 640));
      final completer = Completer<NoteDraft>();
      await _pumpSearchScreen(
        tester,
        ingestionService:
            _FakeKnowledgeIngestionService((_) => completer.future),
        repository: _FakeNoteDraftReviewRepository(),
      );

      await _askQuestion(tester, 'Loading test');

      expect(find.text('Generating draft...'), findsOneWidget);
      final askBtn =
          tester.widget<FilledButton>(find.byKey(const Key('ask-question-button')));
      expect(askBtn.onPressed, isNull);
    });

    testWidgets('phone – save and discard buttons are reachable after ask',
        (tester) async {
      await setSurface(tester, const Size(360, 640));
      await pumpWithDraft(tester, action: NoteDraftAction.createNewNote);

      expect(find.text('Draft Review'), findsOneWidget);
      await tester.ensureVisible(find.text('Save as new note'));
      expect(find.text('Save as new note'), findsOneWidget);
      await tester.ensureVisible(find.text('Discard'));
      expect(find.text('Discard'), findsOneWidget);
    });

    testWidgets('phone – append target dropdown is accessible and does not overflow',
        (tester) async {
      await setSurface(tester, const Size(360, 640));
      final note = _note(id: 'n1', title: 'Target', content: 'c');
      await pumpWithDraft(
        tester,
        action: NoteDraftAction.appendToExistingNote,
        notes: [note],
      );

      expect(find.byKey(const Key('append-target-dropdown')), findsOneWidget);

      // Verify the dropdown fits within the 360px screen width (no overflow)
      final dropdownRect = tester.getRect(
        find.byKey(const Key('append-target-dropdown')),
      );
      expect(dropdownRect.right, lessThanOrEqualTo(360.0),
          reason: 'Dropdown must not exceed screen width on a narrow phone');
    });

    testWidgets('phone – append and save buttons reachable after ask (createNewNote)',
        (tester) async {
      await setSurface(tester, const Size(360, 640));
      await pumpWithDraft(tester, action: NoteDraftAction.createNewNote);

      await tester.ensureVisible(find.text('Append to existing note'));
      expect(find.text('Append to existing note'), findsOneWidget);
    });

    // ── tablet ─────────────────────────────────────────────────────────────

    testWidgets('tablet – ask form and review panel are accessible', (tester) async {
      await setSurface(tester, const Size(768, 1024));
      await pumpWithDraft(tester, action: NoteDraftAction.createNewNote);

      expect(find.byKey(const Key('ask-question-field')), findsOneWidget);
      expect(find.text('Draft Review'), findsOneWidget);
      await tester.ensureVisible(find.text('Save as new note'));
      expect(find.text('Save as new note'), findsOneWidget);
      await tester.ensureVisible(find.text('Discard'));
      expect(find.text('Discard'), findsOneWidget);
    });

    testWidgets('tablet – append target dropdown is accessible', (tester) async {
      await setSurface(tester, const Size(768, 1024));
      final note = _note(id: 'n1', title: 'Target', content: 'c');
      await pumpWithDraft(
        tester,
        action: NoteDraftAction.appendToExistingNote,
        notes: [note],
      );

      expect(find.byKey(const Key('append-target-dropdown')), findsOneWidget);
    });

    // ── desktop ────────────────────────────────────────────────────────────

    testWidgets('desktop – ask form and review panel are accessible', (tester) async {
      await setSurface(tester, const Size(1280, 800));
      await pumpWithDraft(tester, action: NoteDraftAction.createNewNote);

      expect(find.byKey(const Key('ask-question-field')), findsOneWidget);
      expect(find.text('Draft Review'), findsOneWidget);
      await tester.ensureVisible(find.text('Save as new note'));
      expect(find.text('Save as new note'), findsOneWidget);
    });

    testWidgets('desktop – discard button is reachable', (tester) async {
      await setSurface(tester, const Size(1280, 800));
      await pumpWithDraft(tester, action: NoteDraftAction.createNewNote);

      await tester.ensureVisible(find.text('Discard'));
      expect(find.text('Discard'), findsOneWidget);
    });
  });
}
