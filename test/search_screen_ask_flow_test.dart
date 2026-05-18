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

class _FakeNoteDraftReviewRepository implements NoteDraftReviewRepository {
  final Map<String, Note> notesById = <String, Note>{};
  int insertedNotes = 0;
  int updatedNotes = 0;

  @override
  Future<Note?> getNoteById(String id) async => notesById[id];

  @override
  Future<void> insertNote(Note note) async {
    insertedNotes++;
    notesById[note.id] = note;
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

Future<void> _pumpSearchScreen(
  WidgetTester tester, {
  required KnowledgeIngestionService ingestionService,
  required _FakeNoteDraftReviewRepository repository,
  List<Note> notes = const <Note>[],
  List<Note> recentNotes = const <Note>[],
  void Function()? onRefresh,
}) async {
  await tester.pumpWidget(
    ProviderScope(
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
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SearchScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _askQuestion(WidgetTester tester, String question) async {
  await tester.enterText(find.byKey(const Key('ask-question-field')), question);
  await tester.pump();
  await tester.tap(find.byKey(const Key('ask-question-button')));
  await tester.pump();
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void _expectNoOverflow(WidgetTester tester) {
  final exception = tester.takeException();
  expect(exception, isNull);
}

void main() {
  group('SearchScreen ask flow', () {
    testWidgets('shows loading and then the draft review panel',
        (tester) async {
      final completer = Completer<NoteDraft>();
      final repository = _FakeNoteDraftReviewRepository();

      await _pumpSearchScreen(
        tester,
        ingestionService: _FakeKnowledgeIngestionService((_) => completer.future),
        repository: repository,
      );

      await _askQuestion(tester, 'What changed?');

      expect(find.text('Generating draft...'), findsOneWidget);

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
      expect(find.text('Save as new note'), findsOneWidget);
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
      expect(find.textContaining('Recommended action: Do not save yet'),
          findsOneWidget);
    });

    testWidgets('save as new note only persists after the explicit save tap',
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
        recentNotes: const <Note>[],
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

    testWidgets('append requires a selected target and only persists after tap',
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
          Note(
            id: 'note-1',
            title: 'Existing note',
            content: 'Existing content',
            tags: [],
            keywords: [],
            isPinned: false,
            createdAt: DateTime(2026, 5, 18),
            updatedAt: DateTime(2026, 5, 18),
            embeddingPending: false,
          ),
        ],
        recentNotes: const <Note>[],
      );

      await _askQuestion(tester, 'Append this');
      await tester.pumpAndSettle();

      expect(repository.updatedNotes, 0);

      final appendButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Append to existing note'),
      );
      expect(appendButton.onPressed, isNull);

      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing note').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Append to existing note'));
      await tester.tap(find.text('Append to existing note'));
      await tester.pumpAndSettle();

      expect(repository.updatedNotes, 1);
      expect(find.text('Update appended successfully.'), findsOneWidget);
    });

    testWidgets('discard clears the review flow without persistence',
        (tester) async {
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
      expect(find.text('Draft discarded. Nothing was saved.'), findsOneWidget);
    });

    testWidgets('renders the ask and review flow on iPhone 13 portrait',
        (tester) async {
      await _setSurfaceSize(tester, const Size(390, 844));
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
            question: 'Layout test',
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

      await tester.ensureVisible(find.byKey(const Key('ask-question-button')));
      await _askQuestion(tester, 'Layout test');
      await tester.pumpAndSettle();

      _expectNoOverflow(tester);
      expect(find.byKey(const Key('ask-question-button')), findsOneWidget);
      await tester.ensureVisible(find.text('Save as new note'));
      await tester.ensureVisible(find.text('Append to existing note'));
      await tester.ensureVisible(find.text('Discard'));
      _expectNoOverflow(tester);
    });

    testWidgets('renders the ask and review flow on tablet landscape',
        (tester) async {
      await _setSurfaceSize(tester, const Size(1024, 768));
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
            question: 'Tablet layout test',
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

      await tester.ensureVisible(find.byKey(const Key('ask-question-button')));
      await _askQuestion(tester, 'Tablet layout test');
      await tester.pumpAndSettle();

      _expectNoOverflow(tester);
      expect(find.byKey(const Key('ask-question-button')), findsOneWidget);
      await tester.ensureVisible(find.text('Save as new note'));
      await tester.ensureVisible(find.text('Append to existing note'));
      await tester.ensureVisible(find.text('Discard'));
      _expectNoOverflow(tester);
    });

    testWidgets('renders the ask and review flow on desktop layout',
        (tester) async {
      await _setSurfaceSize(tester, const Size(1440, 900));
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
            question: 'Desktop layout test',
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

      await tester.ensureVisible(find.byKey(const Key('ask-question-button')));
      await _askQuestion(tester, 'Desktop layout test');
      await tester.pumpAndSettle();

      _expectNoOverflow(tester);
      expect(find.byKey(const Key('ask-question-button')), findsOneWidget);
      await tester.ensureVisible(find.text('Save as new note'));
      await tester.ensureVisible(find.text('Append to existing note'));
      await tester.ensureVisible(find.text('Discard'));
      _expectNoOverflow(tester);
    });
  });
}
