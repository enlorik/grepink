import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import '../models/claim_review_session_state.dart';
import '../models/knowledge_ingestion_state.dart';
import '../models/note.dart';
import '../models/note_draft_review_state.dart';
import '../models/search_state.dart';
import '../providers/claim_review_provider.dart';
import '../providers/knowledge_ingestion_provider.dart';
import '../providers/note_draft_review_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/search_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/grepink_search_bar.dart';
import '../widgets/excerpt_quote_card.dart';
import '../widgets/note_card.dart';
import '../widgets/memory_pulse_indicator.dart';
import '../widgets/grepink_bottom_nav.dart';
import '../widgets/note_draft_review_panel.dart';
import '../widgets/claim_review_groups_panel.dart';
import '../widgets/claim_draft_preview_panel.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _askController = TextEditingController();
  final FocusNode _askFocusNode = FocusNode();
  int _askSequence = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _askController.dispose();
    _askFocusNode.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) {
      ref.read(searchProvider.notifier).clearSearch();
    } else {
      ref.read(searchProvider.notifier).search(query.trim());
    }
  }

  Future<void> _onAsk() async {
    final question = _askController.text.trim();
    ref.read(noteDraftReviewProvider.notifier).clear();

    if (question.isEmpty) {
      ++_askSequence;
      ref.read(knowledgeIngestionProvider.notifier).reset();
      ref.read(claimReviewProvider.notifier).reset();
      return;
    }

    final askId = ++_askSequence;
    ref.read(claimReviewProvider.notifier).reset();

    await ref.read(knowledgeIngestionProvider.notifier).ingest(question);
    if (!mounted || askId != _askSequence) return;

    final knowledgeState = ref.read(knowledgeIngestionProvider);
    if (knowledgeState.isSuccess && knowledgeState.noteDraft != null) {
      ref.read(noteDraftReviewProvider.notifier).startReview(
            knowledgeState.noteDraft!,
          );
    }

    await ref.read(claimReviewProvider.notifier).runReview(question);
  }

  void _toggleClaim(String claimId) {
    ref.read(claimReviewProvider.notifier).toggle(claimId);
  }

  void _generateClaimDraft() {
    ref.read(claimReviewProvider.notifier).generateDraft();
  }

  Future<void> _saveClaimDraftAsNewNote() async {
    await ref.read(claimReviewProvider.notifier).saveAsNewNote();
    if (ref.read(claimReviewProvider).saveStatus != ClaimDraftSaveStatus.saved) {
      return;
    }

    await ref.read(refreshNotesProvider)();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Claim draft saved as a new note.')),
    );
  }

  void _selectClaimDraftTargetNote(String? noteId) {
    ref.read(claimReviewProvider.notifier).selectTargetNote(noteId);
  }

  Future<void> _appendClaimDraftToExistingNote() async {
    await ref.read(claimReviewProvider.notifier).appendToExistingNote();
    if (ref.read(claimReviewProvider).appendStatus !=
        ClaimDraftAppendStatus.appended) {
      return;
    }

    await ref.read(refreshNotesProvider)();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Claim draft appended to the note.')),
    );
  }

  Future<void> _saveAsNewNote() async {
    final note = await ref.read(noteDraftReviewProvider.notifier).saveAsNewNote();
    if (note == null) return;

    await ref.read(refreshNotesProvider)();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Draft saved successfully.')),
    );
  }

  Future<void> _appendToExistingNote() async {
    final reviewState = ref.read(noteDraftReviewProvider);
    if (reviewState.targetNoteId == null || reviewState.targetNoteId!.isEmpty) {
      ref
          .read(noteDraftReviewProvider.notifier)
          .setError('Select a target note before appending.');
      return;
    }

    final note =
        await ref.read(noteDraftReviewProvider.notifier).appendToExistingNote();
    if (note == null) return;

    await ref.read(refreshNotesProvider)();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Update appended successfully.')),
    );
  }

  void _discardClaimReview() {
    ref.read(claimReviewProvider.notifier).reset();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review discarded. Nothing was saved.')),
    );
  }

  void _discardDraft() {
    ref.read(noteDraftReviewProvider.notifier).discard();
    ref.read(knowledgeIngestionProvider.notifier).reset();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Draft discarded. Nothing was saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final allNotes = ref.watch(allNotesProvider);
    final recentNotes = ref.watch(recentNotesProvider);
    final knowledgeState = ref.watch(knowledgeIngestionProvider);
    final reviewState = ref.watch(noteDraftReviewProvider);
    final claimReviewState = ref.watch(claimReviewProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAskSection(
                        knowledgeState: knowledgeState,
                        reviewState: reviewState,
                        availableNotes: allNotes,
                        claimReviewState: claimReviewState,
                      ),
                      const SizedBox(height: 24),
                      if (searchState.isEmpty)
                        _buildEmptyState(
                          reviewState.noteDraft == null ? recentNotes : const <Note>[],
                        )
                      else
                        _buildResults(searchState),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: GrepinkBottomNav(
        currentIndex: 1,
        onTap: (i) {
          if (i == 0) context.go('/');
          if (i == 2) context.push('/settings');
        },
      ),
    );
  }

  Widget _buildAskSection({
    required KnowledgeIngestionState knowledgeState,
    required NoteDraftReviewState reviewState,
    required List<Note> availableNotes,
    required ClaimReviewSessionState claimReviewState,
  }) {
    final askDisabled = knowledgeState.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.dividerBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAccent.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grow your notes', style: AppTextStyles.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Ask a question and review the draft before you save, append, or discard it.',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('ask-question-field'),
                controller: _askController,
                focusNode: _askFocusNode,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _onAsk(),
                decoration: InputDecoration(
                  hintText: 'What should Grepink turn into durable notes?',
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
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    key: const Key('ask-question-button'),
                    onPressed: askDisabled || _askController.text.trim().isEmpty
                        ? null
                        : _onAsk,
                    icon: knowledgeState.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      knowledgeState.isLoading ? 'Generating draft...' : 'Ask Grepink',
                    ),
                  ),
                  if (knowledgeState.isLoading) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Building a note draft from your existing knowledge.',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (knowledgeState.isError && knowledgeState.errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildStatusCard(
            message: knowledgeState.errorMessage!,
            borderColor: AppColors.pinHighlight.withValues(alpha: 0.45),
          ),
        ],
        if (knowledgeState.isSuccess && knowledgeState.isDoNotSave) ...[
          const SizedBox(height: 12),
          _buildStatusCard(
            message:
                'No new knowledge was detected, so Grepink recommends not saving this draft unless you want it anyway.',
          ),
        ],
        if (reviewState.errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildStatusCard(
            message: reviewState.errorMessage!,
            borderColor: AppColors.pinHighlight.withValues(alpha: 0.45),
          ),
        ],
        if (reviewState.status == NoteDraftReviewStatus.discarded) ...[
          const SizedBox(height: 12),
          _buildStatusCard(message: 'Draft discarded. Nothing was saved.'),
        ],
        if (reviewState.noteDraft != null) ...[
          const SizedBox(height: 12),
          _buildAppendTargetSelector(
            availableNotes: availableNotes,
            selectedTargetNoteId: reviewState.targetNoteId,
            onTargetSelected: (noteId) {
              ref.read(noteDraftReviewProvider.notifier).selectTargetNote(noteId);
            },
          ),
          const SizedBox(height: 16),
          NoteDraftReviewPanel(
            noteDraft: reviewState.noteDraft!,
            onSaveAsNewNote: _saveAsNewNote,
            onAppendToExistingNote: _appendToExistingNote,
            onDiscard: _discardDraft,
            availableNotes: availableNotes,
            selectedTargetNoteId: reviewState.targetNoteId,
            onTargetNoteSelected: (noteId) {
              ref.read(noteDraftReviewProvider.notifier).selectTargetNote(noteId);
            },
            status: reviewState.status,
            selectedDecision: reviewState.selectedDecision,
            errorMessage: reviewState.errorMessage,
          ),
        ],
        if (claimReviewState.isError && claimReviewState.errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildStatusCard(
            message: 'Could not review claims for this question.',
            borderColor: AppColors.pinHighlight.withValues(alpha: 0.45),
          ),
        ],
        if (claimReviewState.hasReviewItems && claimReviewState.selection != null) ...[
          const SizedBox(height: 16),
          ClaimReviewGroupsPanel(
            groups: claimReviewState.groups,
            selectedIds: claimReviewState.selection!.selectedIds,
            onToggle: _toggleClaim,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('generate-claim-draft-button'),
            onPressed: _generateClaimDraft,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Generate draft'),
          ),
        ],
        if (claimReviewState.draft != null) ...[
          const SizedBox(height: 16),
          ClaimDraftPreviewPanel(
            draft: claimReviewState.draft!,
            saveStatus: claimReviewState.saveStatus,
            saveErrorMessage: claimReviewState.saveErrorMessage,
            onSaveAsNewNote: claimReviewState.draft!.shouldSave &&
                    claimReviewState.saveStatus != ClaimDraftSaveStatus.saving &&
                    !claimReviewState.isDraftAlreadySaved
                ? _saveClaimDraftAsNewNote
                : null,
            availableNotes: availableNotes,
            selectedTargetNoteId: claimReviewState.targetNoteId,
            onTargetNoteSelected: _selectClaimDraftTargetNote,
            appendStatus: claimReviewState.appendStatus,
            appendErrorMessage: claimReviewState.appendErrorMessage,
            onAppendToExistingNote: claimReviewState.draft!.shouldSave &&
                    claimReviewState.appendStatus !=
                        ClaimDraftAppendStatus.appending &&
                    !claimReviewState.isDraftAlreadyAppended
                ? _appendClaimDraftToExistingNote
                : null,
          ),
        ],
        if (claimReviewState.hasReviewItems || claimReviewState.draft != null) ...[
          const SizedBox(height: 12),
          TextButton(
            key: const Key('discard-claim-review-button'),
            onPressed: claimReviewState.isSaveInFlight || claimReviewState.isAppendInFlight
                ? null
                : _discardClaimReview,
            child: const Text('Discard'),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.deepAction),
            onPressed: () {
              ref.read(searchProvider.notifier).clearSearch();
              context.pop();
            },
          ),
          Expanded(
            child: GrepinkSearchBar(
              controller: _searchController,
              focusNode: _focusNode,
              onChanged: (v) {
                if (v.isEmpty) ref.read(searchProvider.notifier).clearSearch();
              },
              onSubmitted: _onSearch,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(List<Note> recentNotes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              const SizedBox(height: 16),
              const MemoryPulseIndicator(),
              const SizedBox(height: 16),
              Text(
                'Ask me what you\'ve learned...',
                style: AppTextStyles.aiResponse,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        if (recentNotes.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text('RECENT NOTES', style: AppTextStyles.excerptSource),
          const SizedBox(height: 12),
          ...recentNotes.take(5).toList().asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NoteCard(note: e.value, index: e.key),
              )),
        ],
      ],
    );
  }

  Widget _buildResults(SearchState searchState) {
    final memoryResults = searchState.memoryResults;
    final noteResults = searchState.noteResults;
    final isSearching = searchState.isSearching;
    final isAiLoading = searchState.isAiLoading;
    final aiResponse = searchState.aiResponse;

    if (isSearching) {
      return const Padding(
        padding: EdgeInsets.only(top: 32),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryAction),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          if (memoryResults.isNotEmpty) ...[
            _buildSectionHeader('🧠 MEMORY', AppColors.pinHighlight),
            const SizedBox(height: 12),
            ...memoryResults.asMap().entries.map((e) {
              final delay = e.key * 30;
              return _AnimatedResultItem(
                delay: delay,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ExcerptQuoteCard(
                    result: e.value,
                    onTap: () => context.push('/note/${e.value.note.id}'),
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
          ],
          if (noteResults.isNotEmpty) ...[
            _buildSectionHeader('YOUR NOTES', AppColors.primaryAccent),
            const SizedBox(height: 12),
            ...noteResults.asMap().entries.map((e) {
              final delay = (memoryResults.length + e.key) * 30;
              return _AnimatedResultItem(
                delay: delay,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NoteCard(
                    note: e.value,
                    index: memoryResults.length + e.key,
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
          ],
          if (memoryResults.isNotEmpty || noteResults.isNotEmpty || isAiLoading || aiResponse != null) ...[
            _buildSectionHeader('AI RESPONSE', AppColors.primaryAccent),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.aiResponseBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.dividerBorder),
              ),
              child: isAiLoading && aiResponse == null
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MemoryPulseIndicator(),
                        SizedBox(width: 12),
                        AiLoadingDots(),
                      ],
                    )
                  : aiResponse != null
                      ? MarkdownBody(
                          data: aiResponse,
                          styleSheet: MarkdownStyleSheet(
                            p: AppTextStyles.aiResponse,
                            code: AppTextStyles.codeBlock,
                          ),
                        )
                      : Text(
                          'Set your API key in Settings to enable AI responses.',
                          style: AppTextStyles.bodyMedium,
                        ),
            ),
          ],
          if (memoryResults.isEmpty && noteResults.isEmpty && !isSearching) ...[
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  const Icon(Icons.search_off, size: 48, color: AppColors.placeholderText),
                  const SizedBox(height: 12),
                  Text('No results found', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Try different keywords or add more notes',
                    style: AppTextStyles.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  Widget _buildAppendTargetSelector({
    required List<Note> availableNotes,
    required String? selectedTargetNoteId,
    required ValueChanged<String?> onTargetSelected,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.aiResponseBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dividerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Append target', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('append-target-dropdown'),
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
            onChanged: onTargetSelected,
          ),
          if (selectedTargetNoteId == null || selectedTargetNoteId.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Select a target note before append is enabled.',
              style: AppTextStyles.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String message,
    Color borderColor = AppColors.dividerBorder,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.aiResponseBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Text(message, style: AppTextStyles.bodyMedium),
    );
  }

  Widget _buildSectionHeader(String title, Color dotColor) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(title, style: AppTextStyles.excerptSource),
      ],
    );
  }
}

class _AnimatedResultItem extends StatefulWidget {
  final Widget child;
  final int delay;

  const _AnimatedResultItem({required this.child, required this.delay});

  @override
  State<_AnimatedResultItem> createState() => _AnimatedResultItemState();
}

class _AnimatedResultItemState extends State<_AnimatedResultItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        final reduce = MediaQuery.of(context).disableAnimations;
        if (reduce) {
          _controller.value = 1.0;
        } else {
          _controller.forward();
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}
