import '../models/evidence_item.dart';
import '../models/knowledge_delta.dart';
import '../models/note_draft.dart';
import 'llm_provider.dart';
import 'summary_writer.dart';

class StructuredSummaryWriter implements SummaryWriter {
  final LlmProvider _llmProvider;
  final int _maxTokens;
  final double _temperature;

  StructuredSummaryWriter({
    required LlmProvider llmProvider,
    int maxTokens = 900,
    double temperature = 0.2,
  })  : _llmProvider = llmProvider,
        _maxTokens = maxTokens,
        _temperature = temperature;

  @override
  Future<NoteDraft> write({
    required String question,
    required List<EvidenceItem> localEvidence,
    required List<EvidenceItem> webEvidence,
    required List<KnowledgeDelta> deltas,
  }) async {
    final action = chooseNoteDraftAction(
      webEvidence: webEvidence,
      deltas: deltas,
    );

    if (action == NoteDraftAction.doNotSave) {
      return NoteDraft(
        question: question,
        markdownContent: _buildNoSaveMarkdown(question, deltas),
        action: action,
        deltas: deltas,
        localEvidence: localEvidence,
        webEvidence: webEvidence,
      );
    }

    final request = LlmRequest(
      systemPrompt: _systemPrompt,
      userPrompt: _buildUserPrompt(
        question: question,
        localEvidence: localEvidence,
        webEvidence: webEvidence,
        deltas: deltas,
        action: action,
      ),
      maxTokens: _maxTokens,
      temperature: _temperature,
    );

    final response = await _llmProvider.complete(request);
    final markdown = response.text.trim().isEmpty
        ? _buildFallbackMarkdown(
            question: question,
            localEvidence: localEvidence,
            webEvidence: webEvidence,
            deltas: deltas,
            action: action,
          )
        : response.text.trim();

    return NoteDraft(
      question: question,
      markdownContent: markdown,
      action: action,
      deltas: deltas,
      localEvidence: localEvidence,
      webEvidence: webEvidence,
    );
  }

  static const String _systemPrompt =
      'You write durable Grepink note drafts. '
      'Grepink is notes-first, not chat-first. '
      'Save only durable knowledge that should be kept in notes. '
      'Do not repeat duplicate information already present in existing notes. '
      'Preserve source URLs for web-derived claims. '
      'Clearly separate: what existing notes already said, what new knowledge was found, better sources/citations, and the suggested markdown to save. '
      'If there is no new durable knowledge to save, return no-save content instead of a chat answer. '
      'Output note-ready markdown only.';

  String _buildUserPrompt({
    required String question,
    required List<EvidenceItem> localEvidence,
    required List<EvidenceItem> webEvidence,
    required List<KnowledgeDelta> deltas,
    required NoteDraftAction action,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Question: $question');
    buffer.writeln();
    buffer.writeln('Required action: ${action.name}');
    buffer.writeln(
        'Return durable markdown for Grepink. Do not return chat history, UI instructions, or auto-save instructions.');
    buffer.writeln();
    buffer.writeln('## Existing notes already said');
    if (localEvidence.isEmpty) {
      buffer.writeln('- No related local notes found.');
    } else {
      for (final item in localEvidence) {
        final sourceNoteId = item.sourceNoteId ?? 'none';
        final sourceUrl = item.sourceUrl ?? 'none';
        buffer.writeln(
            '- [${item.id}] ${item.title} | noteId: $sourceNoteId | url: $sourceUrl');
        buffer.writeln('  ${item.content}');
      }
    }
    buffer.writeln();
    buffer.writeln('## Web evidence');
    if (webEvidence.isEmpty) {
      buffer.writeln('- No web evidence found.');
    } else {
      for (final item in webEvidence) {
        buffer.writeln(
            '- [${item.id}] ${item.title} | url: ${item.sourceUrl ?? 'none'} | relevance: ${item.relevanceScore.toStringAsFixed(2)}');
        buffer.writeln('  ${item.content}');
      }
    }
    buffer.writeln();
    buffer.writeln('## Knowledge deltas');
    if (deltas.isEmpty) {
      buffer.writeln('- No deltas found.');
    } else {
      for (final delta in deltas) {
        buffer.writeln(
            '- ${delta.deltaType.name} | evidenceId: ${delta.evidence.id} | existingNoteId: ${delta.existingNoteId ?? 'none'} | reason: ${delta.reason}');
        if (delta.bestSimilarityScore != null) {
          buffer.writeln(
              '  similarity: ${delta.bestSimilarityScore!.toStringAsFixed(2)}');
        }
      }
    }
    buffer.writeln();
    buffer.writeln('## Output requirements');
    buffer.writeln('- Include a section for existing-note overlap.');
    buffer.writeln('- Include a section for new knowledge or state that there is none.');
    buffer.writeln('- Include a section for better sources/citations.');
    buffer.writeln('- Include a final "Suggested markdown to save" section.');
    buffer.writeln(
        '- preserve source URLs in the suggested markdown when claims come from web evidence.');
    return buffer.toString().trimRight();
  }

  String _buildNoSaveMarkdown(String question, List<KnowledgeDelta> deltas) {
    final buffer = StringBuffer();
    buffer.writeln('# No New Knowledge Found');
    buffer.writeln();
    buffer.writeln('**Question:** $question');
    buffer.writeln();
    buffer.writeln(
        'No durable new knowledge should be saved. Existing notes already cover the incoming evidence, or the incoming evidence was empty.');
    if (deltas.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## Delta summary');
      for (final delta in deltas) {
        buffer.writeln('- ${delta.deltaType.name}: ${delta.reason}');
      }
    }
    return buffer.toString().trimRight();
  }

  String _buildFallbackMarkdown({
    required String question,
    required List<EvidenceItem> localEvidence,
    required List<EvidenceItem> webEvidence,
    required List<KnowledgeDelta> deltas,
    required NoteDraftAction action,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# Note Draft');
    buffer.writeln();
    buffer.writeln('**Question:** $question');
    buffer.writeln('**Action:** ${action.name}');
    buffer.writeln();
    buffer.writeln('## Existing notes already said');
    if (localEvidence.isEmpty) {
      buffer.writeln('- No related local notes found.');
    } else {
      for (final item in localEvidence) {
        buffer.writeln('- **${item.title}**: ${item.content}');
      }
    }
    buffer.writeln();
    buffer.writeln('## New knowledge found');
    final newKnowledgeDeltas = deltas
        .where((delta) =>
            delta.deltaType == DeltaType.newClaim ||
            delta.deltaType == DeltaType.relatedButNew)
        .toList();
    if (newKnowledgeDeltas.isEmpty) {
      buffer.writeln('- No new durable knowledge found.');
    } else {
      for (final delta in newKnowledgeDeltas) {
        final sourceUrl = delta.evidence.sourceUrl == null
            ? ''
            : ' (${delta.evidence.sourceUrl})';
        buffer.writeln('- ${delta.evidence.content}$sourceUrl');
      }
    }
    buffer.writeln();
    buffer.writeln('## Better sources/citations');
    final betterSources = deltas
        .where((delta) => delta.deltaType == DeltaType.betterSource)
        .toList();
    if (betterSources.isEmpty) {
      buffer.writeln('- No better sources identified.');
    } else {
      for (final delta in betterSources) {
        buffer.writeln(
            '- ${delta.evidence.title}: ${delta.evidence.sourceUrl ?? 'unsourced'}');
      }
    }
    buffer.writeln();
    buffer.writeln('## Suggested markdown to save');
    for (final item in webEvidence) {
      final sourceUrl =
          item.sourceUrl == null ? ' _(unsourced)_' : ' (${item.sourceUrl})';
      buffer.writeln('- **${item.title}**: ${item.content}$sourceUrl');
    }
    return buffer.toString().trimRight();
  }
}
