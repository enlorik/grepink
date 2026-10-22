import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/services/note_source_document.dart';
import 'package:grepink/widgets/note_reading_view.dart';

void main() {
  testWidgets(
      'passage hover exposes every source and wheel scrolls the bounded inspector',
      (tester) async {
    final document =
        '**A fact** [One](https://one.example) [Two](https://two.example)\n\n${NoteSourceDocument.encode([
          GroundedAnswerCitation(
              id: '1',
              title: 'First source',
              url: 'https://one.example',
              snippet: List.filled(50, 'Evidence paragraph.').join('\n\n')),
          const GroundedAnswerCitation(
              id: '2',
              title: 'Second source',
              url: 'https://two.example',
              snippet: 'More evidence.'),
        ])}';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(children: [
      Expanded(child: NoteReadingView(content: document)),
      const SizedBox(width: 100, child: Text('Question answer'))
    ]))));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse
        .moveTo(tester.getCenter(find.byKey(const ValueKey('note-passage-0'))));
    await tester.pumpAndSettle();
    expect(find.text('Sources · 1 of 2'), findsOneWidget);
    final pane =
        tester.getRect(find.byKey(const Key('saved-note-source-preview')));
    final answer = tester.getRect(find.text('Question answer'));
    expect(pane.overlaps(answer), isFalse);
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const Key('saved-source-scroll')))
        .controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.sendEventToBinding(PointerScrollEvent(
        position:
            tester.getCenter(find.byKey(const ValueKey('note-passage-0'))),
        scrollDelta: const Offset(0, 120)));
    await tester.pump();
    expect(scroll.offset, greaterThan(0));
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(find.text('Second source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editing one rendered passage preserves its neighbors and source metadata',
      (tester) async {
    var document =
        '# Heading\n\nOriginal **passage**.\n\nOther paragraph.\n\n${NoteSourceDocument.encode([
          const GroundedAnswerCitation(
              id: '1', title: 'Source', url: 'https://example.com')
        ])}';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => NoteReadingView(
                    content: document,
                    editable: true,
                    onChanged: (value) => setState(() => document = value))))));
    await tester.tap(find.byKey(const ValueKey('note-passage-1')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Updated **passage**.');
    await tester.pump();
    expect(document,
        contains('# Heading\n\nUpdated **passage**.\n\nOther paragraph.'));
    expect(
        NoteSourceDocument.sources(document).single.url, 'https://example.com');
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Updated passage.', findRichText: true),
        findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
