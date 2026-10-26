import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/providers/note_draft_review_provider.dart';
import 'package:grepink/theme/app_text_styles.dart';
import 'package:grepink/theme/app_colors.dart';
import 'package:grepink/providers/notes_provider.dart';
import 'package:grepink/screens/notes_list_screen.dart';
import 'package:grepink/screens/note_editor_screen.dart';
import 'package:grepink/services/note_source_document.dart';
import 'package:grepink/widgets/note_reading_view.dart';

final _notes = [
  Note(
    id: 'one',
    title: 'Rust notebook',
    content:
        '# Types\n\n**Scalar** values represent one piece of information, such as a number or a boolean. [Source](https://example.com/types)\n\n## Compound values\n\nRust combines values without hiding how they are stored. A **tuple** can hold different types; an **array** contains values of the same type.\n\n- **Tuples** have a fixed number of elements.\n- **Arrays** have a known length and one element type.\n\n## Sized and unsized\n\n**Sized vs. Unsized:** a sized type has a size the compiler knows; slices describe a sequence whose length can vary.\n\n> Read the idea first, inspect its source, then add the missing piece to your note.\n\n${NoteSourceDocument.encode([const GroundedAnswerCitation(id: '1', title: 'Rust reference', url: 'https://example.com/types', snippet: '**Saved** explanation.')])}',
    tags: const [],
    keywords: const [],
    isPinned: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    embeddingPending: false,
  ),
  Note(
    id: 'two',
    title: 'Second note',
    content: 'Other knowledge',
    tags: const [],
    keywords: const [],
    isPinned: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    embeddingPending: false,
  ),
];

class _MemoryNotes extends NotesNotifier {
  _MemoryNotes(super.ref);
  @override
  Future<void> loadNotes() async {
    state = AsyncValue.data(_notes);
  }

  @override
  Future<void> updateNote(Note note) async {
    state = AsyncValue.data([note, _notes.last]);
  }
}

void main() {
  testWidgets('saved Markdown renders and source survives reopening', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NoteReadingView(content: _notes.first.content),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('# Types'), findsNothing);
    expect(find.text('Types'), findsOneWidget);
    await tester.tap(find.text('Source'));
    await tester.pump();
    expect(find.byKey(const Key('saved-note-source-preview')), findsOneWidget);
    expect(find.text('Rust reference'), findsOneWidget);
    expect(
      find.textContaining('explanation.', findRichText: true),
      findsWidgets,
    );
    await tester.tap(find.byTooltip('Close source'));
    await tester.pump();
    expect(find.byKey(const Key('saved-note-source-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'desktop shows rendered note and protects unsaved edits on selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [notesProvider.overrideWith((ref) => _MemoryNotes(ref))],
          child: const MaterialApp(home: NotesListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NoteReadingView), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-passage-0')));
      await tester.pump();
      final body = find.byKey(const Key('active-passage-editor'));
      await tester.enterText(body, '# Types\n\nMy unsaved addition ');
      await tester.pump();
      expect(find.byKey(const Key('active-passage-editor')), findsOneWidget);
      expect(
        tester.widget<TextField>(body).controller!.text,
        endsWith('addition '),
      );
      await tester.pump();
      await tester.tap(find.text('Second note'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Unsaved changes'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('My unsaved addition', findRichText: true),
        findsWidgets,
      );
      await tester.tap(find.text('Second note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(NoteReadingView),
          matching: find.text('Other knowledge'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reopened appended source metadata is not an unsaved edit', (
    tester,
  ) async {
    final original = _notes.first;
    _notes[0] = original.copyWith(
      content: '${original.content}\n\n${original.content}',
    );
    addTearDown(() => _notes[0] = original);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [notesProvider.overrideWith((ref) => _MemoryNotes(ref))],
        child: const MaterialApp(
          home: NoteEditorScreen(noteId: 'one', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<NoteEditorScreenState>(
      find.byType(NoteEditorScreen),
    );
    final leaving = state.confirmLeave();
    await tester.pump();
    expect(find.text('Unsaved changes'), findsNothing);
    expect(await leaving, isTrue);
  });

  testWidgets(
    'research inserts into the unsaved note without leaving the reader',
    (tester) async {
      tester.view.physicalSize = const Size(1520, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final output = Platform.environment['GREPINK_LAYOUT_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final inter = ByteData.sublistView(
            await File(
              Platform.environment['GREPINK_PREVIEW_FONT']!,
            ).readAsBytes(),
          );
          for (final family in {
            'Inter',
            AppTextStyles.displayMedium.fontFamily!,
            AppTextStyles.titleLarge.fontFamily!,
            AppTextStyles.titleMedium.fontFamily!,
            AppTextStyles.bodyLarge.fontFamily!,
            AppTextStyles.bodyMedium.fontFamily!,
            AppTextStyles.bodySmall.fontFamily!,
            AppTextStyles.excerptSource.fontFamily!,
          }) {
            await (FontLoader(family)..addFont(Future.value(inter))).load();
          }
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      final capture = GlobalKey();
      final container = ProviderContainer(
        overrides: [notesProvider.overrideWith((ref) => _MemoryNotes(ref))],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'Inter',
                scaffoldBackgroundColor: AppColors.backgroundStart,
                dividerTheme: const DividerThemeData(
                  color: AppColors.dividerBorder,
                ),
                colorScheme: const ColorScheme.light(
                  primary: AppColors.primaryAction,
                  primaryContainer: AppColors.primaryAccent,
                  surface: AppColors.surface,
                  onSurface: AppColors.bodyText,
                ),
              ),
              home: const NotesListScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      container
          .read(noteDraftReviewProvider.notifier)
          .startReview(
            const NoteDraft(
              question: 'What is a tuple?',
              markdownContent:
                  '## Tuples\n\nA **tuple** groups values of different types.',
              action: NoteDraftAction.appendToExistingNote,
              deltas: [],
              localEvidence: [],
              webEvidence: [],
            ),
          );
      await tester.pumpAndSettle();
      expect(find.byType(NoteReadingView), findsOneWidget);
      if (output != null) {
        Future<void> capturePreview(String filename) async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('${File(output).parent.path}/$filename');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capturePreview('notebook-workspace.png');
        await tester.tap(
          find.descendant(
            of: find.byType(NoteReadingView),
            matching: find.text('Source'),
          ),
        );
        await tester.pumpAndSettle();
        await capturePreview('notebook-sources-workspace.png');
        await tester.tap(find.byTooltip('Close source'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('note-passage-1')));
        await tester.pumpAndSettle();
        await capturePreview('notebook-editing-workspace.png');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      final insert = find.widgetWithText(FilledButton, 'Insert into this note');
      await tester.ensureVisible(insert);
      await tester.tap(insert);
      await tester.pumpAndSettle();
      final reader = tester.widget<NoteReadingView>(
        find.byType(NoteReadingView),
      );
      expect(reader.content, contains('## Tuples'));
      expect(reader.content, contains('[Source](https://example.com/types)'));
      expect(
        NoteSourceDocument.sources(reader.content).single.snippet,
        '**Saved** explanation.',
      );
      expect(
        container.read(notesProvider).value!.first.content,
        isNot(contains('## Tuples')),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final saved = container.read(notesProvider).value!.first;
      expect(saved.content, contains('## Tuples'));
      expect(
        NoteSourceDocument.sources(saved.content).single.snippet,
        '**Saved** explanation.',
      );
      final editor = tester.state<NoteEditorScreenState>(
        find.byType(NoteEditorScreen),
      );
      expect(await editor.confirmLeave(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
