import 'note_draft.dart';

enum KnowledgeIngestionStatus { idle, loading, success, error }

class KnowledgeIngestionState {
  final KnowledgeIngestionStatus status;
  final String question;
  final NoteDraft? noteDraft;
  final String? errorMessage;

  const KnowledgeIngestionState({
    this.status = KnowledgeIngestionStatus.idle,
    this.question = '',
    this.noteDraft,
    this.errorMessage,
  });

  KnowledgeIngestionState copyWith({
    KnowledgeIngestionStatus? status,
    String? question,
    NoteDraft? noteDraft,
    String? errorMessage,
    bool clearDraft = false,
    bool clearError = false,
  }) {
    return KnowledgeIngestionState(
      status: status ?? this.status,
      question: question ?? this.question,
      noteDraft: clearDraft ? null : (noteDraft ?? this.noteDraft),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  bool get isIdle => status == KnowledgeIngestionStatus.idle;
  bool get isLoading => status == KnowledgeIngestionStatus.loading;
  bool get isSuccess => status == KnowledgeIngestionStatus.success;
  bool get isError => status == KnowledgeIngestionStatus.error;
  bool get isDoNotSave => noteDraft?.action == NoteDraftAction.doNotSave;
}
