import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/models/note_draft_review_state.dart';
import 'package:grepink/widgets/note_draft_review_panel.dart';

NoteDraft _draft() {
  const localEvidence = EvidenceItem(
    id: 'local-1',
    type: EvidenceType.localNote,
    title: 'Existing local note',
    content: 'Existing knowledge',
    sourceNoteId: 'note-1',
  );
  const webEvidence = EvidenceItem(
    id: 'web-1',
    type: EvidenceType.webSearch,
    title: 'Sourced result',
    content: 'Fresh sourced claim',
    sourceUrl: 'https://example.com/source',
  );

  return const NoteDraft(
    question: 'What changed?',
    markdownContent: '# Suggested draft\n\n- Fresh sourced claim',
    action: NoteDraftAction.createNewNote,
    deltas: [
      KnowledgeDelta(
        evidence: webEvidence,
        deltaType: DeltaType.newClaim,
        reason: 'new',
      ),
      KnowledgeDelta(
        evidence: webEvidence,
        deltaType: DeltaType.betterSource,
        reason: 'better source',
      ),
      KnowledgeDelta(
        evidence: webEvidence,
        deltaType: DeltaType.contradiction,
        reason: 'contradiction',
      ),
      KnowledgeDelta(
        evidence: webEvidence,
        deltaType: DeltaType.duplicate,
        reason: 'duplicate',
      ),
    ],
    localEvidence: [localEvidence],
    webEvidence: [webEvidence],
  );
}

NoteDraft _draftWithoutSources() {
  return const NoteDraft(
    question: 'Question with no sources',
    markdownContent: 'No sources available.',
    action: NoteDraftAction.doNotSave,
    deltas: [],
    localEvidence: [],
    webEvidence: [],
  );
}

Widget _buildWidget({
  required NoteDraft draft,
  VoidCallback? onSaveAsNewNote,
  VoidCallback? onAppendToExistingNote,
  VoidCallback? onDiscard,
  List<Note> availableNotes = const [],
  String? selectedTargetNoteId,
  ValueChanged<String?>? onTargetNoteSelected,
  NoteDraftReviewStatus status = NoteDraftReviewStatus.reviewing,
  NoteDraftReviewDecision? selectedDecision,
  String? errorMessage,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: NoteDraftReviewPanel(
          noteDraft: draft,
          onSaveAsNewNote: onSaveAsNewNote,
          onAppendToExistingNote: onAppendToExistingNote,
          onDiscard: onDiscard,
          availableNotes: availableNotes,
          selectedTargetNoteId: selectedTargetNoteId,
          onTargetNoteSelected: onTargetNoteSelected,
          status: status,
          selectedDecision: selectedDecision,
          errorMessage: errorMessage,
        ),
      ),
    ),
  );
}

void main() {
  group('NoteDraftReviewPanel', () {
    final targetNote = Note(
      id: 'note-1',
      title: 'Existing target note',
      content: 'Existing content',
      tags: [],
      keywords: [],
      isPinned: false,
      createdAt: DateTime(2026, 5, 18),
      updatedAt: DateTime(2026, 5, 18),
      embeddingPending: false,
    );

    testWidgets('shows question, markdown, recommendation, counts, and sources',
        (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          draft: _draft(),
          availableNotes: [targetNote],
        ),
      );

      expect(find.text('Draft Review'), findsOneWidget);
      expect(find.text('What changed?'), findsOneWidget);
      expect(find.textContaining('Recommended action: Save as new note'),
          findsOneWidget);
      expect(find.text('New claims: 1'), findsOneWidget);
      expect(find.text('Better sources: 1'), findsOneWidget);
      expect(find.text('Contradictions: 1'), findsOneWidget);
      expect(find.text('Duplicates ignored: 1'), findsOneWidget);
      expect(find.text('Local notes (1)'), findsOneWidget);
      expect(find.text('Web search results (1)'), findsOneWidget);
      expect(find.text('Ignored duplicates (1)'), findsOneWidget);
      expect(find.text('Existing local note'), findsWidgets);
      expect(find.text('Fresh sourced claim'), findsWidgets);
      expect(find.text('https://example.com/source'), findsWidgets);
      expect(find.text('Append target'), findsOneWidget);
      expect(
        find.text('No target selected. Append stays blocked until you choose a note.'),
        findsOneWidget,
      );
      expect(find.text('Select a target note before append is enabled.'),
          findsOneWidget);
      expect(find.text('Save as new note'), findsOneWidget);
      expect(find.text('Append to existing note'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
    });

    testWidgets('button callbacks are invoked without persistence',
        (tester) async {
      var saveTapped = 0;
      var appendTapped = 0;
      var discardTapped = 0;

      await tester.pumpWidget(
        _buildWidget(
          draft: _draft(),
          availableNotes: [targetNote],
          selectedTargetNoteId: targetNote.id,
          onSaveAsNewNote: () => saveTapped++,
          onAppendToExistingNote: () => appendTapped++,
          onDiscard: () => discardTapped++,
        ),
      );

      await tester.ensureVisible(find.text('Save as new note'));
      await tester.tap(find.text('Save as new note'));
      await tester.ensureVisible(find.text('Append to existing note'));
      await tester.tap(find.text('Append to existing note'));
      await tester.ensureVisible(find.text('Discard'));
      await tester.tap(find.text('Discard'));

      expect(saveTapped, 1);
      expect(appendTapped, 1);
      expect(discardTapped, 1);
    });

    testWidgets('hides sources section when there are no grouped sources',
        (tester) async {
      await tester.pumpWidget(_buildWidget(draft: _draftWithoutSources()));

      expect(find.text('Sources'), findsNothing);
      expect(find.text('Local notes'), findsNothing);
      expect(find.text('Web search results'), findsNothing);
      expect(find.text('Grounded AI answer sources'), findsNothing);
      expect(find.text('Ignored duplicates'), findsNothing);
    });

    testWidgets('shows saved status and append target selection state',
        (tester) async {
      String? selectedTarget;
      final alternateNote = Note(
        id: 'note-2',
        title: 'Another note',
        content: 'Other content',
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime(2026, 5, 18),
        updatedAt: DateTime(2026, 5, 18),
        embeddingPending: false,
      );

      await tester.pumpWidget(
        _buildWidget(
          draft: _draft(),
          availableNotes: [targetNote, alternateNote],
          selectedTargetNoteId: targetNote.id,
          status: NoteDraftReviewStatus.saved,
          selectedDecision: NoteDraftReviewDecision.appendToExistingNote,
          onTargetNoteSelected: (value) => selectedTarget = value,
        ),
      );

      expect(find.text('Append success for "Existing target note".'), findsOneWidget);
      expect(find.text('Append will update the selected note only.'), findsOneWidget);

      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing target note').last);
      await tester.pumpAndSettle();

      expect(selectedTarget, targetNote.id);
    });

    testWidgets('append button stays disabled until a target note is selected',
        (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          draft: _draft(),
          availableNotes: [targetNote],
        ),
      );

      final appendButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Append to existing note'),
      );
      expect(appendButton.onPressed, isNull);

      await tester.pumpWidget(
        _buildWidget(
          draft: _draft(),
          availableNotes: [targetNote],
          selectedTargetNoteId: targetNote.id,
          onAppendToExistingNote: () {},
        ),
      );

      final enabledAppendButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Append to existing note'),
      );
      expect(enabledAppendButton.onPressed, isNotNull);
      expect(find.text('Target selected: "Existing target note".'), findsOneWidget);
    });

    testWidgets('web sources with URL appear before unsourced web items',
        (tester) async {
      const sourced = EvidenceItem(
        id: 'web-sourced',
        type: EvidenceType.webSearch,
        title: 'Sourced web result',
        content: 'Has a source URL',
        sourceUrl: 'https://example.com/sourced',
      );
      const unsourced = EvidenceItem(
        id: 'web-unsourced',
        type: EvidenceType.webSearch,
        title: 'Unsourced web result',
        content: 'No URL attached',
      );

      const draft = NoteDraft(
        question: 'Sort order test',
        markdownContent: '# Test',
        action: NoteDraftAction.doNotSave,
        deltas: [],
        localEvidence: [],
        webEvidence: [unsourced, sourced],
      );

      await tester.pumpWidget(_buildWidget(draft: draft));
      await tester.pump();

      final sourcedCardOffset =
          tester.getTopLeft(find.text('Sourced web result').first);
      final unsourcedCardOffset =
          tester.getTopLeft(find.text('Unsourced web result').first);

      expect(sourcedCardOffset.dy, lessThan(unsourcedCardOffset.dy),
          reason: 'sourced item should appear above unsourced item');
    });

    testWidgets('local notes with sourceNoteId appear before those without',
        (tester) async {
      const withId = EvidenceItem(
        id: 'local-with-id',
        type: EvidenceType.localNote,
        title: 'Note with source ID',
        content: 'Has source note id',
        sourceNoteId: 'note-ref-1',
      );
      const withoutId = EvidenceItem(
        id: 'local-no-id',
        type: EvidenceType.localNote,
        title: 'Note without source ID',
        content: 'No source note id',
      );

      const draft = NoteDraft(
        question: 'Local sort test',
        markdownContent: '# Local',
        action: NoteDraftAction.doNotSave,
        deltas: [],
        localEvidence: [withoutId, withId],
        webEvidence: [],
      );

      await tester.pumpWidget(_buildWidget(draft: draft));
      await tester.pump();

      final withIdOffset =
          tester.getTopLeft(find.text('Note with source ID').first);
      final withoutIdOffset =
          tester.getTopLeft(find.text('Note without source ID').first);

      expect(withIdOffset.dy, lessThan(withoutIdOffset.dy),
          reason: 'local note with sourceNoteId should appear above one without');
    });
  });
}
