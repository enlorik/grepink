import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note_draft.dart';
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
        ),
      ),
    ),
  );
}

void main() {
  group('NoteDraftReviewPanel', () {
    testWidgets('shows question, markdown, recommendation, counts, and sources',
        (tester) async {
      await tester.pumpWidget(_buildWidget(draft: _draft()));

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
  });
}
