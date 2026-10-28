import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/services/source_page_loader.dart';
import 'package:grepink/services/note_source_document.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/widgets/note_reading_view.dart';

class _Pages implements SourcePageLoader {
  int calls = 0;
  Future<SourcePage> Function(String) answer;
  _Pages(this.answer);
  @override
  Future<SourcePage> load(String url) {
    calls++;
    return answer(url);
  }
}

final _page = parseSourcePage(
  '<title>Rust Reference</title><main><h1>Types</h1><p>Function pointers implement callable behavior.</p><p>Trait objects use dynamic dispatch.</p></main>',
);

void main() {
  testWidgets(
    'hovering ordinary line text loads the page and follows a different line on the same URL',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final output = Platform.environment['GREPINK_LAYOUT_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final bytes = ByteData.sublistView(
            await File(
              Platform.environment['GREPINK_PREVIEW_FONT']!,
            ).readAsBytes(),
          );
          await (FontLoader('Inter')..addFont(Future.value(bytes))).load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      final capture = GlobalKey();
      final loader = _Pages((_) async => _page);
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            theme: ThemeData(
              fontFamily: 'Inter',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xffbc6d88),
              ),
            ),
            home: Scaffold(
              body: NoteReadingView(
                sourceLoader: loader,
                content:
                    '- **Function pointers** [Source](https://example.com/types)\n- **Trait objects** [Source](https://example.com/types)',
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('note-passage-0'))),
      );
      await tester.pumpAndSettle();
      expect(loader.calls, 1);
      expect(find.byKey(const Key('source-page-quote')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('source-page-quote')),
          matching: find.text('Function pointers implement callable behavior.'),
        ),
        findsOneWidget,
      );
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('note-passage-1'))),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('source-page-quote')),
          matching: find.text('Trait objects use dynamic dispatch.'),
        ),
        findsOneWidget,
      );
      expect(loader.calls, 1);
      if (output != null) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '${File(output).parent.path}/inline-sources-workspace.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one clicked list line edits directly, protects its links and supports Tab and Shift+Tab',
    (tester) async {
      final meta = NoteSourceDocument.encode([
        const GroundedAnswerCitation(
          id: '1',
          title: 'Source',
          url: 'https://example.com',
          snippet: 'Saved evidence.',
        ),
      ]);
      var document =
          '- First line.\n  - • Second **line**. [Source](https://example.com)\n- Third line.\n\n$meta';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => NoteReadingView(
                content: document,
                editable: true,
                onChanged: (value) => update(() => document = value),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Edit'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('note-passage-1')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('active-passage-editor'));
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Second **line**.',
      );
      await tester.enterText(field, 'Changed line ');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'Changed line ');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        document,
        contains(
          '\n    - • Changed line  [Source](https://example.com)\n- Third',
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(
        document,
        contains(
          '\n  - • Changed line  [Source](https://example.com)\n- Third',
        ),
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('active-passage-editor')), findsNothing);
      expect(document, startsWith('- First line.\n'));
      expect(
        NoteSourceDocument.sources(document).single.snippet,
        'Saved evidence.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late page response cannot replace the source under the new hovered line',
    (tester) async {
      final a = Completer<SourcePage>(), b = Completer<SourcePage>();
      final loader = _Pages((url) => url.endsWith('/a') ? a.future : b.future);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteReadingView(
              sourceLoader: loader,
              content:
                  '- One [Source](https://example.com/a)\n- Two [Source](https://example.com/b)',
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('note-passage-0'))),
      );
      await tester.pump();
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('note-passage-1'))),
      );
      await tester.pump();
      b.complete(
        const SourcePage('Second page', [
          SourcePageSection('Second evidence', 'Second evidence'),
        ]),
      );
      await tester.pumpAndSettle();
      a.complete(
        const SourcePage('Old page', [
          SourcePageSection('Old evidence', 'Old evidence'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Second page'), findsOneWidget);
      expect(find.text('Old page'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'escape restores just the active line and switching lines keeps the preceding edit',
    (tester) async {
      var document = '- First\n- Second';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => NoteReadingView(
                content: document,
                editable: true,
                onChanged: (value) => update(() => document = value),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('note-passage-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Changed first');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-passage-1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Second',
      );
      await tester.enterText(find.byType(TextField), 'Unwanted');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(document, '- Changed first\n- Second');
      expect(find.byType(TextField), findsNothing);
    },
  );
}
