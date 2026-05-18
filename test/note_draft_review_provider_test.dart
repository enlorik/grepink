import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/models/note_draft_review_state.dart';
import 'package:grepink/providers/note_draft_review_provider.dart';

NoteDraft _draft({
  required String question,
  required NoteDraftAction action,
}) {
  const evidence = EvidenceItem(
    id: 'e1',
    type: EvidenceType.webSearch,
    title: 'Evidence',
    content: 'Durable evidence',
    sourceUrl: 'https://example.com',
  );

  return NoteDraft(
    question: question,
    markdownContent: '# Draft',
    action: action,
    deltas: const [
      KnowledgeDelta(
        evidence: evidence,
        deltaType: DeltaType.newClaim,
        reason: 'test',
      ),
    ],
    localEvidence: const [],
    webEvidence: const [evidence],
  );
}

void main() {
  group('NoteDraftReviewNotifier', () {
    test('starts with no draft', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(noteDraftReviewProvider);
      expect(state.status, NoteDraftReviewStatus.empty);
      expect(state.noteDraft, isNull);
      expect(state.selectedDecision, isNull);
    });

    test('startReview defaults to save as new for createNewNote drafts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(noteDraftReviewProvider.notifier).startReview(
            _draft(
              question: 'What is new?',
              action: NoteDraftAction.createNewNote,
            ),
          );

      final state = container.read(noteDraftReviewProvider);
      expect(state.status, NoteDraftReviewStatus.reviewing);
      expect(state.selectedDecision, NoteDraftReviewDecision.saveAsNewNote);
    });

    test('startReview defaults to append for append drafts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(noteDraftReviewProvider.notifier).startReview(
            _draft(
              question: 'Add citation',
              action: NoteDraftAction.appendToExistingNote,
            ),
          );

      final state = container.read(noteDraftReviewProvider);
      expect(
        state.selectedDecision,
        NoteDraftReviewDecision.appendToExistingNote,
      );
    });

    test('can represent append target selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(
        _draft(
          question: 'Append this',
          action: NoteDraftAction.createNewNote,
        ),
      );
      notifier.selectDecision(NoteDraftReviewDecision.appendToExistingNote);
      notifier.selectTargetNote('note-123');

      final state = container.read(noteDraftReviewProvider);
      expect(
        state.selectedDecision,
        NoteDraftReviewDecision.appendToExistingNote,
      );
      expect(state.targetNoteId, 'note-123');
    });

    test('discard transitions to discarded state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(
        _draft(
          question: 'Discard this',
          action: NoteDraftAction.createNewNote,
        ),
      );
      notifier.discard();

      final state = container.read(noteDraftReviewProvider);
      expect(state.status, NoteDraftReviewStatus.discarded);
      expect(state.selectedDecision, NoteDraftReviewDecision.discard);
      expect(state.targetNoteId, isNull);
    });

    test('saving and saved states are represented without persistence', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(
        _draft(
          question: 'Save this',
          action: NoteDraftAction.createNewNote,
        ),
      );
      notifier.markSaving();
      expect(
        container.read(noteDraftReviewProvider).status,
        NoteDraftReviewStatus.saving,
      );

      notifier.markSaved();
      expect(
        container.read(noteDraftReviewProvider).status,
        NoteDraftReviewStatus.saved,
      );
    });

    test('setError stores an error message without clearing the draft', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(noteDraftReviewProvider.notifier);
      final draft = _draft(
        question: 'Broken save',
        action: NoteDraftAction.createNewNote,
      );

      notifier.startReview(draft);
      notifier.setError('save failed');

      final state = container.read(noteDraftReviewProvider);
      expect(state.status, NoteDraftReviewStatus.error);
      expect(state.errorMessage, 'save failed');
      expect(state.noteDraft, same(draft));
    });
  });
}
