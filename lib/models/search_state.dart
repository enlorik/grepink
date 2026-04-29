import 'note.dart';
import 'excerpt_result.dart';

class SearchState {
  final String query;
  final List<ExcerptResult> memoryResults;
  final List<Note> noteResults;
  final String? aiResponse;
  final bool isSearching;
  final bool isAiLoading;

  const SearchState({
    this.query = '',
    this.memoryResults = const [],
    this.noteResults = const [],
    this.aiResponse,
    this.isSearching = false,
    this.isAiLoading = false,
  });

  SearchState copyWith({
    String? query,
    List<ExcerptResult>? memoryResults,
    List<Note>? noteResults,
    String? aiResponse,
    bool? isSearching,
    bool? isAiLoading,
    bool clearAiResponse = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      memoryResults: memoryResults ?? this.memoryResults,
      noteResults: noteResults ?? this.noteResults,
      aiResponse: clearAiResponse ? null : (aiResponse ?? this.aiResponse),
      isSearching: isSearching ?? this.isSearching,
      isAiLoading: isAiLoading ?? this.isAiLoading,
    );
  }

  bool get hasResults => memoryResults.isNotEmpty || noteResults.isNotEmpty;
  bool get isEmpty => query.isEmpty;
}
