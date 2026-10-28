import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/services/note_source_document.dart';
import 'package:grepink/services/note_addition.dart';
import 'package:grepink/widgets/evidence_workspace.dart';
import 'package:grepink/widgets/note_reading_view.dart';

void main() {
  test(
    'topic labels and additions remove question/report wrappers but preserve evidence and warnings',
    () {
      expect(noteTopicTitle('What is photosynthesis?', ''), 'Photosynthesis');
      expect(noteTopicTitle('Explain tuple layout', ''), 'Tuple layout');
      const draft =
          '# What are tuples?\n\n## New knowledge\n\nTuples group values. [Source](<https://example.com>)\n\n## Possible contradictions to review\n\nAn explicit warning.\n\n## Sources\n- Example — https://example.com';
      const code =
          '```md\n## New knowledge\n## Sources\n- Example — https://example.com\n```';
      expect(noteAdditionBody(code), code);
      final body = noteAdditionBody(draft);
      expect(body, startsWith('Tuples group values.'));
      expect(body, contains('[Source](<https://example.com>)'));
      expect(body, contains('## Possible contradictions to review'));
      expect(body, isNot(contains('## Sources')));
    },
  );

  testWidgets(
    'hidden citations publish evidence on hover, wheel changes sources and question focus keeps it visible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final evidence = EvidenceController();
      addTearDown(evidence.dispose);
      const sources = [
        GroundedAnswerCitation(
          id: '1',
          title: 'First source',
          url: 'https://example.com/one',
          snippet: 'First quoted evidence.',
        ),
        GroundedAnswerCitation(
          id: '2',
          title: 'Second source',
          url: 'https://example.com/two',
          snippet: 'Second quoted evidence.',
        ),
      ];
      final content =
          'A readable fact. [Source](https://example.com/one) [Source 2](https://example.com/two)\n\n${NoteSourceDocument.encode(sources)}';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: NoteReadingView(
                          content: content,
                          evidence: evidence,
                        ),
                      ),
                      const TextField(key: Key('question')),
                    ],
                  ),
                ),
                SizedBox(width: 300, child: EvidencePane(controller: evidence)),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Source'), findsNothing);
      expect(find.text('Source 2'), findsNothing);
      expect(content, contains('https://example.com/two'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final passage = find.byKey(const ValueKey('note-passage-0'));
      await mouse.moveTo(tester.getCenter(passage));
      await tester.pumpAndSettle();
      expect(find.text('First quoted evidence.'), findsOneWidget);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(passage),
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Second quoted evidence.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('question')),
        'A follow-up question',
      );
      await tester.pumpAndSettle();
      expect(find.text('Second quoted evidence.'), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const Key('workspace-evidence')))
            .overlaps(tester.getRect(find.byKey(const Key('question')))),
        isFalse,
      );
      await tester.tap(find.byTooltip('Pin this evidence'));
      evidence.inspect('Other fact', [sources.first]);
      await tester.pumpAndSettle();
      expect(evidence.value!.passage, contains('A readable fact.'));
      expect(evidence.index, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
