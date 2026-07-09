import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/claim_review_session_state.dart';
import '../models/note.dart';
import '../services/selected_claims_draft_builder.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shows a preview of a [ClaimDraftResult] generated from selected claims,
/// and lets the user save it as a new note or append it to an existing one.
/// Never persists anything itself — that happens through [onSaveAsNewNote]
/// and [onAppendToExistingNote].
class ClaimDraftPreviewPanel extends StatelessWidget {
  final ClaimDraftResult draft;
  final ClaimDraftSaveStatus saveStatus;
  final String? saveErrorMessage;
  final VoidCallback? onSaveAsNewNote;
  final List<Note> availableNotes;
  final String? selectedTargetNoteId;
  final ValueChanged<String?>? onTargetNoteSelected;
  final ClaimDraftAppendStatus appendStatus;
  final String? appendErrorMessage;
  final VoidCallback? onAppendToExistingNote;

  const ClaimDraftPreviewPanel({
    super.key,
    required this.draft,
    this.saveStatus = ClaimDraftSaveStatus.idle,
    this.saveErrorMessage,
    this.onSaveAsNewNote,
    this.availableNotes = const [],
    this.selectedTargetNoteId,
    this.onTargetNoteSelected,
    this.appendStatus = ClaimDraftAppendStatus.idle,
    this.appendErrorMessage,
    this.onAppendToExistingNote,
  });

  @override
  Widget build(BuildContext context) {
    if (!draft.shouldSave) {
      return Container(
        key: const Key('claim-draft-empty-state'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.aiResponseBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.dividerBorder),
        ),
        child: Text(
          'Select at least one new claim or better source to generate a draft.',
          style: AppTextStyles.bodyMedium,
        ),
      );
    }

    return Container(
      key: const Key('claim-draft-preview-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dividerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Draft preview', style: AppTextStyles.titleLarge),
          const SizedBox(height: 4),
          Text(
            key: const Key('claim-draft-source-count'),
            draft.sourceCount == 1
                ? '1 source'
                : '${draft.sourceCount} sources',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.codeBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.codeBorder),
            ),
            child: MarkdownBody(
              data: draft.markdownContent,
              selectable: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('save-claim-draft-button'),
            onPressed: onSaveAsNewNote,
            child: Text(
              saveStatus == ClaimDraftSaveStatus.saving
                  ? 'Saving...'
                  : 'Save as new note',
            ),
          ),
          if (saveStatus == ClaimDraftSaveStatus.saved) ...[
            const SizedBox(height: 8),
            Text(
              key: const Key('claim-draft-saved-message'),
              'Saved as a new note.',
              style: AppTextStyles.bodySmall,
            ),
          ],
          if (saveStatus == ClaimDraftSaveStatus.error) ...[
            const SizedBox(height: 8),
            Text(
              key: const Key('claim-draft-save-error-message'),
              saveErrorMessage ?? 'Failed to save. Try again.',
              style: AppTextStyles.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Text('Append target', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('claim-draft-append-target-dropdown'),
            initialValue: selectedTargetNoteId,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            hint: const Text('Select a target note'),
            items: availableNotes
                .map(
                  (note) => DropdownMenuItem<String>(
                    value: note.id,
                    child: Text(note.title),
                  ),
                )
                .toList(),
            onChanged: onTargetNoteSelected,
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('append-claim-draft-button'),
            onPressed: onAppendToExistingNote,
            child: Text(
              appendStatus == ClaimDraftAppendStatus.appending
                  ? 'Appending...'
                  : 'Append to existing note',
            ),
          ),
          if (appendStatus == ClaimDraftAppendStatus.appended) ...[
            const SizedBox(height: 8),
            Text(
              key: const Key('claim-draft-appended-message'),
              'Appended to the selected note.',
              style: AppTextStyles.bodySmall,
            ),
          ],
          if (appendStatus == ClaimDraftAppendStatus.error) ...[
            const SizedBox(height: 8),
            Text(
              key: const Key('claim-draft-append-error-message'),
              appendErrorMessage ?? 'Failed to append. Try again.',
              style: AppTextStyles.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
