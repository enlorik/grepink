import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/notes_list_screen.dart';
import 'screens/note_editor_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'providers/sync_provider.dart';

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

class _GrepinkAppState extends ConsumerState<GrepinkApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Eagerly construct the notifier so _init() (silent sign-in + first sync)
    // fires even when the lifecycle is already resumed at observer registration.
    ref.read(syncProvider.notifier);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncProvider.notifier).sync();
    }
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
