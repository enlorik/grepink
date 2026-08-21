import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/notes_list_screen.dart';
import 'screens/note_editor_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'providers/railway_sync_provider.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const NotesListScreen(),
    ),
    GoRoute(
      path: '/note/new',
      builder: (context, state) => const NoteEditorScreen(),
    ),
    GoRoute(
      path: '/note/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return NoteEditorScreen(noteId: id);
      },
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

class GrepinkApp extends ConsumerStatefulWidget {
  const GrepinkApp({super.key});

  @override
  ConsumerState<GrepinkApp> createState() => _GrepinkAppState();
}

class _GrepinkAppState extends ConsumerState<GrepinkApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // Eagerly instantiate the coordinator so _init() runs at startup.
    ref.read(railwaySyncProvider.notifier);
    _lifecycleListener = AppLifecycleListener(
      onResume: () => ref.read(railwaySyncProvider.notifier).syncOnResume(),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Grepink',
      theme: AppTheme.lightTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
