import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/evidence_item.dart';
import '../models/knowledge_delta.dart';
import '../models/note.dart';
import '../models/note_draft.dart';
import '../models/note_draft_review_state.dart';
import '../services/evidence_source_quality.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class NoteDraftReviewPanel extends StatelessWidget {
  final NoteDraft noteDraft;
  final VoidCallback? onSaveAsNewNote;
  final VoidCallback? onAppendToExistingNote;
  final VoidCallback? onDiscard;
  final List<Note> availableNotes;
  final String? selectedTargetNoteId;
  final ValueChanged<String?>? onTargetNoteSelected;
  final NoteDraftReviewStatus status;
  final NoteDraftReviewDecision? selectedDecision;
  final String? errorMessage;

  const NoteDraftReviewPanel({
    super.key,
    required this.noteDraft,
    this.onSaveAsNewNote,
    this.onAppendToExistingNote,
    this.onDiscard,
    this.availableNotes = const [],
    this.selectedTargetNoteId,
    this.onTargetNoteSelected,
    this.status = NoteDraftReviewStatus.reviewing,
    this.selectedDecision,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final groupedSources = _groupSources(noteDraft);
    final duplicateEvidence = noteDraft.deltas
        .where((delta) => delta.deltaType == DeltaType.duplicate)
        .map((delta) => delta.evidence)
        .toList()
      ..sort(_compareEvidenceByQuality);
    final isSaving = status == NoteDraftReviewStatus.saving;
    final isActionBlocked = status == NoteDraftReviewStatus.saving ||
        status == NoteDraftReviewStatus.saved ||
        status == NoteDraftReviewStatus.discarded;
    final hasTarget =
        selectedTargetNoteId != null && selectedTargetNoteId!.trim().isNotEmpty;
    final selectedTarget = availableNotes.cast<Note?>().firstWhere(
          (note) => note?.id == selectedTargetNoteId,
          orElse: () => null,
        );
    final canAppend = !isActionBlocked && availableNotes.isNotEmpty && hasTarget;

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
            if (groupedSources.isNotEmpty || duplicateEvidence.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Sources', style: AppTextStyles.titleMedium),
              const SizedBox(height: 8),
              ...groupedSources.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SourceSection(
                    title: '${entry.key} (${entry.value.length})',
                    items: entry.value,
                  ),
                ),
              ),
              if (duplicateEvidence.isNotEmpty) ...[
                const SizedBox(height: 4),
                _SourceSection(
                  title: 'Ignored duplicates (${duplicateEvidence.length})',
                  items: duplicateEvidence,
                ),
              ],
            ],
            const SizedBox(height: 16),
            Text('Append target', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            _AppendTargetStatus(
              hasAvailableNotes: availableNotes.isNotEmpty,
              selectedTargetTitle: selectedTarget?.title,
              isSaving: isSaving,
              status: status,
              errorMessage: errorMessage,
            ),
            const SizedBox(height: 8),
            if (availableNotes.isEmpty)
              Text(
                'No existing notes are available to append yet.',
                style: AppTextStyles.bodyMedium,
              )
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey<String>('append-target-${selectedTargetNoteId ?? 'none'}'),
                isExpanded: true,
                initialValue: availableNotes.any((note) => note.id == selectedTargetNoteId)
                    ? selectedTargetNoteId
                    : null,
                onChanged: isActionBlocked ? null : onTargetNoteSelected,
                items: availableNotes
                    .map(
                      (note) => DropdownMenuItem<String>(
                        value: note.id,
                        child: Text(
                          note.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                decoration: InputDecoration(
                  hintText: 'Select a note to append to',
                  helperText: hasTarget
                      ? 'Append will update the selected note only.'
                      : 'Select a target note before append is enabled.',
                  filled: true,
                  fillColor: AppColors.aiResponseBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.dividerBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.dividerBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primaryAccent),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: isActionBlocked ? null : onSaveAsNewNote,
                  child: const Text('Save as new note'),
                ),
                OutlinedButton(
                  onPressed: canAppend ? onAppendToExistingNote : null,
                  child: const Text('Append to existing note'),
                ),
                TextButton(
                  onPressed: isActionBlocked ? null : onDiscard,
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
    final localNotes = _sortByQuality(draft.localEvidence);
    final webSources = _sortByQuality(
      draft.webEvidence.where((item) => item.type == EvidenceType.webSearch),
    );
    final groundedAnswers = _sortByQuality(
      draft.webEvidence.where((item) => item.type == EvidenceType.aiGroundedAnswer),
    );

    return {
      if (localNotes.isNotEmpty) 'Local notes': localNotes,
      if (webSources.isNotEmpty) 'Web search results': webSources,
      if (groundedAnswers.isNotEmpty) 'Grounded AI answer sources': groundedAnswers,
    };
  }

  List<EvidenceItem> _sortByQuality(Iterable<EvidenceItem> items) {
    final indexedItems = items.toList().asMap().entries.toList()
      ..sort((left, right) {
        final scoreComparison = EvidenceSourceQuality.score(right.value)
            .compareTo(EvidenceSourceQuality.score(left.value));
        if (scoreComparison != 0) {
          return scoreComparison;
        }

        return left.key.compareTo(right.key);
      });

    return indexedItems.map((entry) => entry.value).toList();
  }

  int _compareEvidenceByQuality(EvidenceItem left, EvidenceItem right) {
    return EvidenceSourceQuality.compare(left, right);
  }
}

class _AppendTargetStatus extends StatelessWidget {
  final bool hasAvailableNotes;
  final String? selectedTargetTitle;
  final bool isSaving;
  final NoteDraftReviewStatus status;
  final String? errorMessage;

  const _AppendTargetStatus({
    required this.hasAvailableNotes,
    required this.selectedTargetTitle,
    required this.isSaving,
    required this.status,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final message =
        switch ((hasAvailableNotes, selectedTargetTitle, isSaving, status)) {
      (false, _, _, _) => 'No valid append targets are available.',
      (true, null, _, _) =>
        'No target selected. Append stays blocked until you choose a note.',
      (true, String title, true, _) => 'Append in progress for "$title".',
      (true, String title, _, NoteDraftReviewStatus.saved) =>
        'Append success for "$title".',
      (true, String _, _, NoteDraftReviewStatus.error) =>
        errorMessage ?? 'Append error. Select a valid note and try again.',
      (true, String title, _, _) => 'Target selected: "$title".',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.aiResponseBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dividerBorder),
      ),
      child: Text(message, style: AppTextStyles.bodyMedium),
    );
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
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.aiResponseBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.dividerBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: AppTextStyles.bodyLarge),
                  if (item.content.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.content, style: AppTextStyles.bodyMedium),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    item.type == EvidenceType.localNote
                        ? 'Local note'
                        : (item.sourceUrl ?? 'Unsourced evidence'),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.deepAction,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
