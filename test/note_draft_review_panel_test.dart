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
        deltaType: DeltaType.duplicate,
        reason: 'duplicate',
      ),
    ],
    localEvidence: [localEvidence],
    webEvidence: [webEvidence],
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
      expect(find.text('Duplicates ignored: 1'), findsOneWidget);
      expect(find.text('Local notes'), findsOneWidget);
      expect(find.text('Web search results'), findsOneWidget);
      expect(find.text('https://example.com/source'), findsOneWidget);
      expect(find.text('Append target'), findsOneWidget);
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
          status: NoteDraftReviewStatus.saved,
          selectedDecision: NoteDraftReviewDecision.appendToExistingNote,
          onTargetNoteSelected: (value) => selectedTarget = value,
        ),
      );

      expect(find.text('Update appended successfully.'), findsOneWidget);
      expect(find.text('Select a target note before append is enabled.'),
          findsOneWidget);

      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing target note'));
      await tester.pumpAndSettle();

      expect(selectedTarget, targetNote.id);
    });
  });
}
