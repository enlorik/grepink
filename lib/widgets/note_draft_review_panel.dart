import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/evidence_item.dart';
import '../models/knowledge_delta.dart';
import '../models/note_draft.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class NoteDraftReviewPanel extends StatelessWidget {
  final NoteDraft noteDraft;
  final VoidCallback? onSaveAsNewNote;
  final VoidCallback? onAppendToExistingNote;
  final VoidCallback? onDiscard;

  const NoteDraftReviewPanel({
    super.key,
    required this.noteDraft,
    this.onSaveAsNewNote,
    this.onAppendToExistingNote,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final groupedSources = _groupSources(noteDraft);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dividerBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Draft Review', style: AppTextStyles.titleLarge),
            const SizedBox(height: 12),
            Text('Question', style: AppTextStyles.titleMedium),
            const SizedBox(height: 4),
            Text(noteDraft.question, style: AppTextStyles.bodyLarge),
            const SizedBox(height: 16),
            _RecommendationCard(action: noteDraft.action),
            const SizedBox(height: 16),
            _DeltaCountsRow(deltas: noteDraft.deltas),
            const SizedBox(height: 16),
            Text('Suggested markdown', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.codeBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.codeBorder),
              ),
              child: MarkdownBody(
                data: noteDraft.markdownContent,
                selectable: true,
              ),
            ),
            if (groupedSources.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Sources', style: AppTextStyles.titleMedium),
              const SizedBox(height: 8),
              ...groupedSources.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SourceSection(title: entry.key, items: entry.value),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: onSaveAsNewNote,
                  child: const Text('Save as new note'),
                ),
                OutlinedButton(
                  onPressed: onAppendToExistingNote,
                  child: const Text('Append to existing note'),
                ),
                TextButton(
                  onPressed: onDiscard,
                  child: const Text('Discard'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<EvidenceItem>> _groupSources(NoteDraft draft) {
    final localNotes = draft.localEvidence;
    final webSources =
        draft.webEvidence.where((item) => item.type == EvidenceType.webSearch).toList();
    final groundedAnswers = draft.webEvidence
        .where((item) => item.type == EvidenceType.aiGroundedAnswer)
        .toList();

    return {
      if (localNotes.isNotEmpty) 'Local notes': localNotes,
      if (webSources.isNotEmpty) 'Web search results': webSources,
      if (groundedAnswers.isNotEmpty) 'Grounded AI answer sources': groundedAnswers,
    };
  }
}

class _RecommendationCard extends StatelessWidget {
  final NoteDraftAction action;

  const _RecommendationCard({required this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.aiResponseBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dividerBorder),
      ),
      child: Text(
        'Recommended action: ${_labelFor(action)}',
        style: AppTextStyles.bodyLarge,
      ),
    );
  }

  String _labelFor(NoteDraftAction action) {
    return switch (action) {
      NoteDraftAction.createNewNote => 'Save as new note',
      NoteDraftAction.appendToExistingNote => 'Append to existing note',
      NoteDraftAction.doNotSave => 'Discard',
    };
  }
}

class _DeltaCountsRow extends StatelessWidget {
  final List<KnowledgeDelta> deltas;

  const _DeltaCountsRow({required this.deltas});

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{
      'New claims': deltas
          .where((delta) => delta.deltaType == DeltaType.newClaim)
          .length,
      'Related but new': deltas
          .where((delta) => delta.deltaType == DeltaType.relatedButNew)
          .length,
      'Better sources': deltas
          .where((delta) => delta.deltaType == DeltaType.betterSource)
          .length,
      'Contradictions': deltas
          .where((delta) => delta.deltaType == DeltaType.contradiction)
          .length,
      'Duplicates ignored': deltas
          .where((delta) => delta.deltaType == DeltaType.duplicate)
          .length,
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: counts.entries
          .map(
            (entry) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.tagBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.tagBorder),
              ),
              child: Text(
                '${entry.key}: ${entry.value}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.deepAction,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SourceSection extends StatelessWidget {
  final String title;
  final List<EvidenceItem> items;

  const _SourceSection({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.bodyLarge),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              item.sourceUrl ?? item.title,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.deepAction,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
