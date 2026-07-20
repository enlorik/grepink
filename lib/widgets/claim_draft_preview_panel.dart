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

  // Null when selectedTargetNoteId is not present in availableNotes (e.g. the
  // note was deleted). Used as both the key fragment and initialValue so the
  // DropdownButtonFormField remounts — and its FormFieldState resets — when the
  // selected note disappears from the list.
  String? get _effectiveTarget => availableNotes.any((n) => n.id == selectedTargetNoteId)
      ? selectedTargetNoteId
      : null;

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
            draft.sourceCount == 1
                ? '1 source'
                : '${draft.sourceCount} sources',
            key: const Key('claim-draft-source-count'),
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
              'Saved as a new note.',
              key: const Key('claim-draft-saved-message'),
              style: AppTextStyles.bodySmall,
            ),
          ],
          if (saveStatus == ClaimDraftSaveStatus.error) ...[
            const SizedBox(height: 8),
            Text(
              saveErrorMessage ?? 'Failed to save. Try again.',
              key: const Key('claim-draft-save-error-message'),
              style: AppTextStyles.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Text('Append target', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            // Key is based on effectiveTarget (null when the selected note is
            // absent from availableNotes) so the widget remounts when a
            // previously selected note is deleted from the list, resetting
            // FormFieldState to null and preventing Flutter's "value not in
            // items" assertion on the stale internal value.
            key: ValueKey<String>(
              'claim-draft-append-target-${_effectiveTarget ?? 'none'}',
            ),
            initialValue: _effectiveTarget,
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
            onChanged: appendStatus == ClaimDraftAppendStatus.appending
                ? null
                : onTargetNoteSelected,
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
              'Appended to the selected note.',
              key: const Key('claim-draft-appended-message'),
              style: AppTextStyles.bodySmall,
            ),
          ],
          if (appendStatus == ClaimDraftAppendStatus.error) ...[
            const SizedBox(height: 8),
            Text(
              appendErrorMessage ?? 'Failed to append. Try again.',
              key: const Key('claim-draft-append-error-message'),
              style: AppTextStyles.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
