import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_initializer_stub.dart'
    if (dart.library.io) 'database_initializer_io.dart';
import 'app.dart';
import 'providers/notes_provider.dart';
import 'providers/railway_sync_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDatabase();
  runApp(
    ProviderScope(
      overrides: [
        railwayNotesReloaderProvider.overrideWith(
          (ref) => () => ref.read(notesProvider.notifier).loadNotes(),
        ),
        railwayEmbeddingReindexerProvider.overrideWith(
          (ref) => () => ref.read(notesProvider.notifier).reindexPendingNotes(),
        ),
      ],
      child: const GrepinkApp(),
    ),
  );
}
