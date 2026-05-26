import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/knowledge_ingestion_state.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/providers/knowledge_ingestion_provider.dart';
import 'package:grepink/services/knowledge_ingestion_service.dart';
import 'package:grepink/services/web_evidence_provider.dart';

class _FakeKnowledgeIngestionService implements KnowledgeIngestionService {
  final NoteDraft? draft;
  final Object? error;

  _FakeKnowledgeIngestionService({
    this.draft,
    this.error,
  });

  @override
  Future<NoteDraft> ingest(String question) async {
    if (error != null) throw error!;
    return draft!;
  }
}

class _PendingKnowledgeIngestionService implements KnowledgeIngestionService {
  final Map<String, Completer<NoteDraft>> _completersByQuestion =
      <String, Completer<NoteDraft>>{};

  Completer<NoteDraft> completerFor(String question) {
    return _completersByQuestion.putIfAbsent(
      question,
      () => Completer<NoteDraft>(),
    );
  }

  @override
  Future<NoteDraft> ingest(String question) {
    return completerFor(question).future;
  }
}

NoteDraft _draft({
  required String question,
  required NoteDraftAction action,
}) {
  const evidence = EvidenceItem(
    id: 'web_1',
    type: EvidenceType.webSearch,
    title: 'Evidence',
    content: 'Fresh claim',
    sourceUrl: 'https://example.com',
  );

  return NoteDraft(
    question: question,
    markdownContent: '# Draft',
    action: action,
    deltas: [
      KnowledgeDelta(
        evidence: evidence,
        deltaType: action == NoteDraftAction.doNotSave
            ? DeltaType.duplicate
            : DeltaType.newClaim,
        reason: 'test',
      ),
    ],
    localEvidence: const [],
    webEvidence: const [evidence],
  );
}

void main() {
  group('knowledgeWebEvidenceProvider', () {
    test('uses empty provider by default', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final provider = container.read(knowledgeWebEvidenceProvider);
      final evidence = await provider.fetch('any question');
      expect(provider, isA<EmptyWebEvidenceProvider>());
      expect(evidence, isEmpty);
    });
  });

  group('KnowledgeIngestionNotifier', () {
    test('starts idle with no question or draft', () {
      final container = ProviderContainer(
        overrides: [
          knowledgeIngestionServiceProvider.overrideWith(
            (ref) async => _FakeKnowledgeIngestionService(
              draft: _draft(
                question: 'unused',
                action: NoteDraftAction.createNewNote,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(knowledgeIngestionProvider);
      expect(state.status, KnowledgeIngestionStatus.idle);
      expect(state.question, isEmpty);
      expect(state.noteDraft, isNull);
      expect(state.errorMessage, isNull);
    });

    test('ingest stores question and resulting draft in success state',
        () async {
      final container = ProviderContainer(
        overrides: [
          knowledgeIngestionServiceProvider.overrideWith(
            (ref) async => _FakeKnowledgeIngestionService(
              draft: _draft(
                question: 'What changed?',
                action: NoteDraftAction.createNewNote,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(knowledgeIngestionProvider.notifier)
          .ingest('What changed?');

      final state = container.read(knowledgeIngestionProvider);
      expect(state.status, KnowledgeIngestionStatus.success);
      expect(state.question, 'What changed?');
      expect(state.noteDraft, isNotNull);
      expect(state.noteDraft!.action, NoteDraftAction.createNewNote);
    });

    test('duplicate-only results remain in success state and mark doNotSave',
        () async {
      final container = ProviderContainer(
        overrides: [
          knowledgeIngestionServiceProvider.overrideWith(
            (ref) async => _FakeKnowledgeIngestionService(
              draft: _draft(
                question: 'Already known',
                action: NoteDraftAction.doNotSave,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(knowledgeIngestionProvider.notifier)
          .ingest('Already known');

      final state = container.read(knowledgeIngestionProvider);
      expect(state.status, KnowledgeIngestionStatus.success);
      expect(state.isDoNotSave, isTrue);
      expect(state.noteDraft!.action, NoteDraftAction.doNotSave);
    });

    test('captures errors in state without throwing', () async {
      final container = ProviderContainer(
        overrides: [
          knowledgeIngestionServiceProvider.overrideWith(
            (ref) async =>
                _FakeKnowledgeIngestionService(error: Exception('boom')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(knowledgeIngestionProvider.notifier).ingest('Fail');

      final state = container.read(knowledgeIngestionProvider);
      expect(state.status, KnowledgeIngestionStatus.error);
      expect(state.question, 'Fail');
      expect(state.noteDraft, isNull);
      expect(state.errorMessage, contains('boom'));
    });

    test('ignores stale older completion when a newer ingest finishes first',
        () async {
      final service = _PendingKnowledgeIngestionService();
      final container = ProviderContainer(
        overrides: [
          knowledgeIngestionServiceProvider.overrideWith((ref) async => service),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(knowledgeIngestionProvider.notifier);
      final firstFuture = notifier.ingest('First question');
      final secondFuture = notifier.ingest('Second question');

      service.completerFor('Second question').complete(
            _draft(
              question: 'Second question',
              action: NoteDraftAction.createNewNote,
            ),
          );
      await secondFuture;

      service.completerFor('First question').complete(
            _draft(
              question: 'First question',
              action: NoteDraftAction.doNotSave,
            ),
          );
      await firstFuture;

      final state = container.read(knowledgeIngestionProvider);
      expect(state.status, KnowledgeIngestionStatus.success);
      expect(state.question, 'Second question');
      expect(state.noteDraft!.question, 'Second question');
      expect(state.noteDraft!.action, NoteDraftAction.createNewNote);
    });

    test('reset invalidates a pending ingest result', () async {
      final service = _PendingKnowledgeIngestionService();
      final container = ProviderContainer(
        overrides: [
          knowledgeIngestionServiceProvider.overrideWith((ref) async => service),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(knowledgeIngestionProvider.notifier);
      final pendingFuture = notifier.ingest('Pending question');

      notifier.reset();
      service.completerFor('Pending question').complete(
            _draft(
              question: 'Pending question',
              action: NoteDraftAction.createNewNote,
            ),
          );
      await pendingFuture;

      final state = container.read(knowledgeIngestionProvider);
      expect(state.status, KnowledgeIngestionStatus.idle);
      expect(state.question, isEmpty);
      expect(state.noteDraft, isNull);
      expect(state.errorMessage, isNull);
    });
  });
}
