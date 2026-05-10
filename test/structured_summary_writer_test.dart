import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/services/mock_llm_provider.dart';
import 'package:grepink/services/structured_summary_writer.dart';

EvidenceItem _webItem(
  String id,
  String content, {
  String? sourceUrl,
}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.webSearch,
      title: 'Web $id',
      content: content,
      sourceUrl: sourceUrl,
      relevanceScore: 0.9,
    );

EvidenceItem _localItem(
  String id,
  String content, {
  String? sourceUrl,
}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: 'Local $id',
      content: content,
      sourceNoteId: id,
      sourceUrl: sourceUrl,
      relevanceScore: 0.8,
    );

KnowledgeDelta _delta(
  EvidenceItem item,
  DeltaType type, {
  String? existingNoteId,
  String reason = 'test reason',
}) =>
    KnowledgeDelta(
      evidence: item,
      deltaType: type,
      existingNoteId: existingNoteId,
      reason: reason,
      bestSimilarityScore: 0.76,
    );

void main() {
  group('StructuredSummaryWriter', () {
    test('calls LlmProvider with local evidence, web evidence, and deltas',
        () async {
      final provider = MockLlmProvider(responseText: '# Markdown draft');
      final writer = StructuredSummaryWriter(llmProvider: provider);
      final local = [_localItem('n1', 'Existing local note')];
      final web = [
        _webItem(
          'w1',
          'New web evidence',
          sourceUrl: 'https://example.com/new',
        ),
      ];
      final deltas = [_delta(web.first, DeltaType.newClaim)];

      await writer.write(
        question: 'What changed?',
        localEvidence: local,
        webEvidence: web,
        deltas: deltas,
      );

      expect(provider.requests, hasLength(1));
      final request = provider.requests.single;
      expect(request.systemPrompt, contains('notes-first'));
      expect(request.userPrompt, contains('What changed?'));
      expect(request.userPrompt, contains('Existing local note'));
      expect(request.userPrompt, contains('New web evidence'));
      expect(request.userPrompt, contains('newClaim'));
    });

    test('newClaim produces createNewNote', () async {
      final provider = MockLlmProvider(responseText: '# Draft');
      final writer = StructuredSummaryWriter(llmProvider: provider);
      final web = [_webItem('w1', 'Fresh claim')];
      final deltas = [_delta(web.first, DeltaType.newClaim)];

      final draft = await writer.write(
        question: 'Question',
        localEvidence: const [],
        webEvidence: web,
        deltas: deltas,
      );

      expect(draft.action, NoteDraftAction.createNewNote);
      expect(draft.markdownContent, '# Draft');
    });

    test('relatedButNew produces createNewNote', () async {
      final provider = MockLlmProvider(responseText: '# Related draft');
      final writer = StructuredSummaryWriter(llmProvider: provider);
      final web = [_webItem('w1', 'Related new idea')];
      final deltas = [_delta(web.first, DeltaType.relatedButNew)];

      final draft = await writer.write(
        question: 'Question',
        localEvidence: const [],
        webEvidence: web,
        deltas: deltas,
      );

      expect(draft.action, NoteDraftAction.createNewNote);
    });

    test('all duplicates produces doNotSave without an LLM call', () async {
      final provider = MockLlmProvider(responseText: '# Should not be used');
      final writer = StructuredSummaryWriter(llmProvider: provider);
      final web = [_webItem('w1', 'Already known claim')];
      final deltas = [_delta(web.first, DeltaType.duplicate)];

      final draft = await writer.write(
        question: 'Question',
        localEvidence: const [],
        webEvidence: web,
        deltas: deltas,
      );

      expect(draft.action, NoteDraftAction.doNotSave);
      expect(provider.requests, isEmpty);
      expect(draft.markdownContent, contains('No New Knowledge Found'));
    });

    test('only betterSource produces appendToExistingNote', () async {
      final provider = MockLlmProvider(responseText: '# Better source draft');
      final writer = StructuredSummaryWriter(llmProvider: provider);
      final web = [
        _webItem(
          'w1',
          'Known claim with better citation',
          sourceUrl: 'https://example.com/better-source',
        ),
      ];
      final deltas = [
        _delta(
          web.first,
          DeltaType.betterSource,
          existingNoteId: 'n1',
        ),
      ];

      final draft = await writer.write(
        question: 'Question',
        localEvidence: [_localItem('n1', 'Existing claim')],
        webEvidence: web,
        deltas: deltas,
      );

      expect(draft.action, NoteDraftAction.appendToExistingNote);
      expect(provider.requests, hasLength(1));
    });

    test('source URLs appear in generated prompt or fallback markdown', () async {
      final provider = MockLlmProvider(responseText: '');
      final writer = StructuredSummaryWriter(llmProvider: provider);
      final web = [
        _webItem(
          'w1',
          'Durable sourced claim',
          sourceUrl: 'https://example.com/source',
        ),
      ];
      final deltas = [_delta(web.first, DeltaType.newClaim)];

      final draft = await writer.write(
        question: 'Question',
        localEvidence: const [],
        webEvidence: web,
        deltas: deltas,
      );

      expect(provider.requests.single.userPrompt, contains('https://example.com/source'));
      expect(draft.markdownContent, contains('https://example.com/source'));
    });
  });
}
