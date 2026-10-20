import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/claim_review_item.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/widgets/claim_review_groups_panel.dart';
import 'package:grepink/theme/app_colors.dart';

ClaimReviewItem claim(String id, String text, int order,
        {bool saveable = true}) =>
    ClaimReviewItem(
        id: id,
        text: text,
        sourceOrder: order,
        classification: saveable
            ? ClaimNoveltyClassification.newClaim
            : ClaimNoveltyClassification.alreadyKnown,
        citationUrls: ['https://example.com/$id'],
        citationTitles: const [],
        selectedByDefault: saveable,
        reason: '',
        matchedLocalEvidenceIds: [],
        canBeSaved: saveable);

Finder get paragraph => find.descendant(
    of: find.byKey(const Key('continuous-claims-text')),
    matching: find.byType(RichText));

Offset wordPosition(WidgetTester tester, String word) {
  final element = paragraph.evaluate().singleWhere((element) =>
      (element.widget as RichText).text.toPlainText().contains(word));
  final render = element.renderObject! as RenderParagraph;
  final start = render.text.toPlainText().indexOf(word);
  expect(start, greaterThanOrEqualTo(0));
  // Click inside a glyph; the midpoint of an even-length word can lie
  // exactly between glyph hit regions.
  final boxes = render.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + 1));
  return render.localToGlobal(boxes.first.toRect().center);
}

Future<void> pumpReview(
  WidgetTester tester,
  List<ClaimReviewItem> claims, {
  List<GroundedAnswerCitation> citations = const [],
  ScrollController? pageScroll,
  ValueChanged<Set<String>>? onSelection,
  GlobalKey? captureKey,
  ThemeData? theme,
}) async {
  var selected = claims.where((c) => c.canBeSaved).map((c) => c.id).toSet();
  await tester.pumpWidget(RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
          theme: theme,
          home: Scaffold(
              body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              controller: pageScroll,
              child: Column(children: [
                ClaimReviewGroupsPanel(
                  groups: [
                    ClaimReviewGroup(
                        label: 'New claims',
                        classification: ClaimNoveltyClassification.newClaim,
                        items: claims.where((c) => c.canBeSaved).toList()),
                    ClaimReviewGroup(
                        label: 'Already in notes',
                        classification: ClaimNoveltyClassification.alreadyKnown,
                        items: claims.where((c) => !c.canBeSaved).toList()),
                  ],
                  selectedIds: selected,
                  citations: citations,
                  onToggle: (id) => setState(() {
                    selected = {...selected};
                    if (!selected.remove(id)) selected.add(id);
                    onSelection?.call(selected);
                  }),
                ),
                const SizedBox(height: 1500)
              ]),
            ),
          )))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'default reading view flows in original order and toggles one formatted claim twice',
      (tester) async {
    Set<String>? selection;
    await pumpReview(
        tester,
        [
          claim('second', 'Second sentence.', 2),
          claim('first', '**First** sentence with `code`.', 0),
          claim('known', 'Known sentence.', 1, saveable: false)
        ],
        onSelection: (ids) => selection = ids);
    expect(find.byType(CheckboxListTile), findsNothing);
    final rich = tester.widget<RichText>(paragraph);
    expect(rich.text.toPlainText(),
        'First sentence with code. Known sentence. Second sentence. ');
    final first = wordPosition(tester, 'First');
    await tester.tapAt(first);
    await tester.pumpAndSettle();
    expect(selection, {'second'});
    final leaves = <TextSpan>[];
    tester.widget<RichText>(paragraph).text.visitChildren((span) {
      if (span is TextSpan && span.text == 'First') leaves.add(span);
      return true;
    });
    expect(leaves, hasLength(1));
    expect(leaves.single.style!.decoration, TextDecoration.lineThrough);
    expect(leaves.single.style!.fontWeight, FontWeight.w600);
    await tester.tapAt(first);
    await tester.pumpAndSettle();
    expect(selection, {'first', 'second'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'article preserves headings, hanging lists and literal Rust symbols',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Set<String>? selection;
    await pumpReview(
        tester,
        [
          claim('intro', 'Rust has **primitive types** and `&str`.', 0),
          claim('heading', '## Primitive types', 1),
          claim(
              'list',
              '- **Integers**: signed and unsigned.\n- Floats\n  - Nested `&mut T`',
              2),
          claim('code', '```rust\nlet s: &str = "hello";\n```', 3),
        ],
        onSelection: (ids) => selection = ids);
    final texts = tester
        .widgetList<RichText>(paragraph)
        .map((w) => w.text.toPlainText())
        .join(' ');
    expect(texts, contains('&str'));
    expect(texts, contains('&mut T'));
    expect(texts, isNot(contains('&amp;')));
    expect(find.text('•'), findsNWidgets(3));
    final heading = paragraph.evaluate().singleWhere(
        (e) => (e.widget as RichText).text.toPlainText() == 'Primitive types');
    final headingRender = heading.renderObject! as RenderParagraph;
    expect(headingRender.localToGlobal(Offset.zero).dy,
        greaterThan(wordPosition(tester, 'Rust').dy));
    expect(
        wordPosition(tester, 'Integers').dy,
        greaterThan(headingRender.localToGlobal(Offset.zero).dy +
            headingRender.size.height));
    expect(wordPosition(tester, 'Nested').dx,
        greaterThan(wordPosition(tester, 'Integers').dx));
    expect(
        tester.getSize(find.byKey(const Key('continuous-claims-text'))).width,
        lessThanOrEqualTo(740));
    await tester.tapAt(wordPosition(tester, 'Integers'));
    await tester.pumpAndSettle();
    expect(selection, isNotNull);
    expect(selection, isNot(contains('list')));
    expect(selection, containsAll(['intro', 'heading', 'code']));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow article renders numbered lists and tables without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpReview(tester, [
      claim('numbered', '3. Borrow a reference.\n4. Return it safely.', 0),
      claim('table',
          '| Type | Meaning |\n| --- | --- |\n| `&str` | borrowed text |', 1),
    ]);
    expect(find.text('3.'), findsOneWidget);
    expect(find.text('4.'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'wide workspace places sources beside text and survives resize and page scroll',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    final output = Platform.environment['GREPINK_LAYOUT_PREVIEW'];
    if (output != null) {
      await tester.runAsync(() async {
        for (final entry in {
          'Inter': 'GREPINK_PREVIEW_FONT',
          'monospace': 'GREPINK_PREVIEW_MONO'
        }.entries) {
          final bytes =
              await File(Platform.environment[entry.value]!).readAsBytes();
          await (FontLoader(entry.key)
                ..addFont(Future.value(ByteData.sublistView(bytes))))
              .load();
        }
      });
    }
    final page = ScrollController();
    addTearDown(page.dispose);
    await pumpReview(
        tester,
        [
          claim(
              'intro',
              'Rust is a **statically typed** language: every value has a type known at compile time.',
              0),
          claim(
              'scalars',
              '## Scalar types\n\n- **Integers**: signed and unsigned whole numbers.\n- **Floating-point**: decimal values, including `f32` and `f64`.\n- **Booleans**: `true` or `false`.\n- **Characters**: a single Unicode value.',
              1),
          claim(
              'compound',
              '## Compound types\n\nTuples group values with different types; arrays contain values of the same type.\n\n```rust\nlet name: &str = "Grepink";\nlet pair = (42, true);\n```',
              2),
        ],
        pageScroll: page,
        captureKey: capture,
        theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Inter',
            scaffoldBackgroundColor: AppColors.backgroundStart,
            colorScheme: const ColorScheme.light(
                primary: AppColors.primaryAction,
                surface: AppColors.surface,
                onSurface: AppColors.bodyText)),
        citations: const [
          GroundedAnswerCitation(
              id: 'intro',
              title: 'The Rust Programming Language',
              url: 'https://example.com/intro',
              snippet:
                  '## Data types\n\nRust is a statically typed language, which means that it must know the types of all variables at compile time.\n\n### Scalar types\n\nA scalar type represents a single value. Rust has four primary scalar types: integers, floating-point numbers, Booleans, and characters.')
        ]);
    final workspace =
        tester.getRect(find.byKey(const Key('claim-review-groups-panel')));
    expect(workspace.width, 1136);
    expect(workspace.center.dx, closeTo(800, 1));
    expect(
        find.byKey(const Key('source-workspace-placeholder')), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(wordPosition(tester, 'Rust'));
    await tester.pumpAndSettle();
    final article =
        tester.getRect(find.byKey(const Key('continuous-claims-text')));
    final source =
        tester.getRect(find.byKey(const Key('source-preview-scroll')));
    expect(source.left - article.right, closeTo(24, 1));
    expect(source.right, lessThanOrEqualTo(workspace.right));
    expect(source.top, lessThan(article.top + 1));
    expect(
        tester
            .widget<Material>(find.byKey(const Key('source-preview-pane')))
            .elevation,
        0);
    await tester.tap(find.byKey(const Key('pin-source-preview')));
    await tester.pumpAndSettle();
    if (output != null) {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(output);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    page.jumpTo(240);
    await tester.pumpAndSettle();
    final sticky =
        tester.getRect(find.byKey(const Key('source-preview-scroll')));
    expect(sticky.top, greaterThanOrEqualTo(96));
    expect(sticky.bottom, lessThanOrEqualTo(920));
    tester.view.physicalSize = const Size(600, 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('docked-source-preview')), findsNothing);
    expect(find.byKey(const Key('compact-source-preview')), findsOneWidget);
    expect(find.byKey(const Key('source-workspace-placeholder')), findsNothing);
    final compact =
        tester.getRect(find.byKey(const Key('source-preview-scroll')));
    expect(compact.left, greaterThanOrEqualTo(0));
    expect(compact.right, lessThanOrEqualTo(600));
    tester.view.physicalSize = const Size(1600, 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('docked-source-preview')), findsOneWidget);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('docked-source-preview')), findsNothing);
    expect(find.byKey(const Key('compact-source-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'hover opens matching sources and wheel over sentence scrolls only popup',
      (tester) async {
    final page = ScrollController();
    addTearDown(page.dispose);
    final snippet =
        '## Source\n\n${List.generate(35, (i) => '- Original source line $i.').join('\n')}';
    await pumpReview(
        tester,
        [
          claim('first', 'First sentence.', 0),
          claim('second', 'Second sentence.', 1)
        ],
        pageScroll: page,
        citations: [
          GroundedAnswerCitation(
              id: 'first',
              title: 'First page',
              url: 'https://example.com/first',
              snippet: snippet),
          const GroundedAnswerCitation(
              id: 'second',
              title: 'Second page',
              url: 'https://example.com/second',
              snippet: 'Second excerpt.')
        ]);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final first = wordPosition(tester, 'First');
    await mouse.moveTo(first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-preview-pane')), findsOneWidget);
    expect(find.text('First page'), findsOneWidget);
    final popup = tester
        .widget<SingleChildScrollView>(
            find.byKey(const Key('source-preview-scroll')))
        .controller!;
    expect(popup.position.maxScrollExtent, greaterThan(0));
    await tester.sendEventToBinding(
        PointerScrollEvent(position: first, scrollDelta: const Offset(0, 100)));
    await tester.pumpAndSettle();
    expect(popup.offset, greaterThan(0));
    expect(page.offset, 0);
    await mouse.moveTo(wordPosition(tester, 'Second'));
    await tester.pumpAndSettle();
    expect(find.text('Second page'), findsOneWidget);
    expect(popup.offset, 0);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('source-preview-pane')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'non-saveable claims stay ignored and keyboard controls expose selection and sources',
      (tester) async {
    Set<String>? selection;
    await pumpReview(
        tester,
        [
          claim('known', 'Known sentence.', 0, saveable: false),
          claim('new', 'New sentence.', 1)
        ],
        onSelection: (ids) => selection = ids);
    await tester.tapAt(wordPosition(tester, 'Known'));
    await tester.pumpAndSettle();
    expect(selection, isNull);
    expect(
        tester
            .widget<TextButton>(find.byKey(const Key('toggle-active-claim')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('next-inline-claim')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toggle-active-claim')));
    await tester.pumpAndSettle();
    expect(selection, isEmpty);
    await tester.tap(find.byKey(const Key('inline-claim-sources')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-preview-pane')), findsOneWidget);
    await tester.tap(find.byTooltip('Close source preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-preview-pane')), findsNothing);
  });
}
