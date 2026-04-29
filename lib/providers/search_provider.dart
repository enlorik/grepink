import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/search_state.dart';
import '../services/memory_engine.dart';
import 'settings_provider.dart';

class SearchNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  bool _disposed = false;
  int _searchId = 0;

  SearchNotifier(this._ref) : super(const SearchState());

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    final id = ++_searchId;

    state = state.copyWith(
      query: query,
      isSearching: true,
      memoryResults: [],
      noteResults: [],
      clearAiResponse: true,
      isAiLoading: false,
    );

    try {
      final settings = await _ref.read(settingsProvider.future);

      final result = await MemoryEngine.instance.search(
        query,
        settings.apiKey.isEmpty ? null : settings.apiKey,
        settings.similarityThreshold,
        aiEnabled: settings.aiEnabled,
        maxTokens: settings.maxTokens,
        onAiResponse: (aiResponse) {
          if (!_disposed && _searchId == id) {
            state = state.copyWith(
              aiResponse: aiResponse,
              isAiLoading: false,
            );
          }
        },
      );

      if (!_disposed && _searchId == id) {
        state = result.copyWith(
          isAiLoading: settings.aiEnabled && settings.apiKey.isNotEmpty,
        );
      }
    } catch (e) {
      if (!_disposed && _searchId == id) {
        state = state.copyWith(
          isSearching: false,
          isAiLoading: false,
        );
      }
    }
  }

  void clearSearch() {
    state = const SearchState();
  }

  void updateAiResponse(String response) {
    state = state.copyWith(aiResponse: response, isAiLoading: false);
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>(
  (ref) => SearchNotifier(ref),
);
