import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'providers/notes_provider.dart';
import 'providers/sync_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        notesReloaderProvider.overrideWith(
          (ref) => () => ref.read(notesProvider.notifier).loadNotes(),
        ),
        embeddingReindexerProvider.overrideWith(
          (ref) => () => ref.read(notesProvider.notifier).reindexPendingNotes(),
        ),
      ],
      child: const GrepinkApp(),
    ),
  );
}
