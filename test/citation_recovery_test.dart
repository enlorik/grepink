import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/services/claim_deduplication_service.dart';
import 'helpers/fake_text_similarity_provider.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/models/grounded_answer_provider_outcome.dart';
import 'package:grepink/models/grounded_claim_ingestion_result.dart';
import 'package:grepink/services/brave_answers_grounded_answer_provider.dart';
import 'package:grepink/services/claim_extraction_service.dart';
import 'package:grepink/services/claim_review_mapper.dart';
import 'package:grepink/services/note_source_document.dart';
import 'package:grepink/services/selected_claims_draft_builder.dart';
import 'package:grepink/services/source_page_loader.dart';
import 'package:grepink/widgets/claim_source_preview.dart';
import 'package:grepink/widgets/evidence_workspace.dart';
import 'package:grepink/widgets/note_reading_view.dart';

Future<GroundedAnswer> answerFromStream(List<String> deltas) async {
  final body = deltas
      .map(
        (text) =>
            'data: ${jsonEncode({
              "choices": [
                {
                  "delta": {"content": text},
                },
              ],
            })}\r\n\r\n',
      )
      .join();
  final result = await BraveAnswersGroundedAnswerProvider(
    apiKey: 'test-only',
    client: MockClient((_) async => http.Response(body, 200)),
  ).fetchGroundedAnswer('Types');
  return (result as GroundedAnswerSuccess).answer;
}

String cite(
  String url,
  String quote, [
  Map<String, dynamic> extra = const {},
]) =>
    '<citation>${jsonEncode({"url": url, "snippet": quote, ...extra})}</citation>';

String draftFor(GroundedAnswer answer) {
  final claims = const RuleBasedClaimExtractionService().extract(answer);
  final ingestion = GroundedClaimIngestionResult(
    question: 'Types',
    answerText: answer.answerText,
    providerName: 'Test',
    knownClaims: [],
    betterSourceClaims: [],
    contradictionClaims: [],
    uncertainClaims: [],
    citations: answer.citations,
    newClaims: [
      for (final claim in claims)
        ClaimDeduplicationResult(
          claim: claim,
          classification: ClaimNoveltyClassification.newClaim,
          matchedLocalEvidence: [],
          reason: '',
          citationUrls: claim.citationUrls,
        ),
    ],
  );
  final items = const ClaimReviewMapper().toGroups(ingestion).first.items;
  if (claims.first.citationUncertain) {
    expect(items.first.citationUncertain, isTrue);
    final preview = claimSourcePreviews(items.first, answer.citations).first;
    expect(preview.unassigned, isTrue);
    expect(preview.excerpt, isNull);
  }
  return const SelectedClaimsDraftBuilder()
      .build(
        question: 'Types',
        selected: items,
        providerName: 'Test',
        citations: answer.citations,
      )
      .markdownContent;
}

class _UnavailablePage implements SourcePageLoader {
  @override
  Future<SourcePage> load(String url) async =>
      throw const SourcePageException('Unavailable');
}

void main() {
  test(
    'inline citation positions recover distinct sentence sources without offsets',
    () async {
      final answer = await answerFromStream([
        'Tuples group fields.',
        cite('https://example.com/tuple', 'Distinct tuple fields.'),
        ' Arrays repeat a type.',
        cite('https://example.com/array', 'One array element type.'),
      ]);
      final claims = const RuleBasedClaimExtractionService().extract(answer);
      expect(claims[0].citationUrls, ['https://example.com/tuple']);
      expect(claims[1].citationUrls, ['https://example.com/array']);
      expect(claims.every((c) => !c.citationUncertain), isTrue);
      final draft = draftFor(answer);
      expect(
        NoteSourceDocument.forPassage(draft, 'Arrays repeat a type.', [
          'https://example.com/array',
        ]).single.snippet,
        'One array element type.',
      );
    },
  );

  test(
    'invalid ranges recover from inline placement and string offsets remain usable',
    () async {
      final answer = await answerFromStream([
        'Claim one.',
        cite('https://example.com/one', 'First source.', {
          'start_index': '0',
          'end_index': '10',
        }),
        ' Claim two.',
        cite('https://example.com/two', 'Second source.', {
          'start_index': 900,
          'end_index': 1000,
        }),
      ]);
      final claims = const RuleBasedClaimExtractionService().extract(answer);
      expect(claims[0].citationUrls, ['https://example.com/one']);
      expect(claims[1].citationUrls, ['https://example.com/two']);
      expect(answer.citations.first.startIndex, 0);
    },
  );

  test(
    'ambiguous end-of-answer citations retain links without assigning their quotes',
    () async {
      final answer = await answerFromStream([
        'Claim one. Claim two.',
        cite('https://example.com/a', 'Unassigned quote A.'),
        cite('https://example.com/b', 'Unassigned quote B.'),
      ]);
      final claims = const RuleBasedClaimExtractionService().extract(answer);
      expect(claims.every((c) => c.citationUncertain), isTrue);
      expect(claims.first.citationUrls, hasLength(2));
      expect(claims.first.evidence.every((c) => c.snippet == null), isTrue);
      final draft = draftFor(answer);
      expect(draft, contains('https://example.com/a'));
      expect(
        NoteSourceDocument.sources(
          draft,
        ).every((c) => c.snippet == null && c.passage == null),
        isTrue,
      );
    },
  );

  test(
    'unattributed answer links cannot promote a known claim as better sourced',
    () async {
      final answer = await answerFromStream([
        'Claim one. Claim two.',
        cite('https://example.com/a', 'Unassigned quote A.'),
        cite('https://example.com/b', 'Unassigned quote B.'),
      ]);
      final claims = const RuleBasedClaimExtractionService().extract(answer);
      final results =
          await TextSimilarityClaimDeduplicationService(
            const FakeTextSimilarityProvider(0.95),
          ).classify(claims, [
            const EvidenceItem(
              id: 'local',
              type: EvidenceType.localNote,
              title: 'Known',
              content: 'Claim one. Claim two.',
            ),
          ]);
      expect(
        results.every(
          (r) => r.classification == ClaimNoveltyClassification.alreadyKnown,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'saved link-only sentence still exposes its URL on hover after page failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final evidence = EvidenceController();
      addTearDown(evidence.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: NoteReadingView(
                    content: 'A fact. [Source](https://example.com/source)',
                    evidence: evidence,
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: EvidencePane(
                    controller: evidence,
                    loader: _UnavailablePage(),
                  ),
                ),
              ],
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
      expect(find.text('https://example.com/source'), findsOneWidget);
      expect(
        find.text('Source link · sentence attribution unavailable'),
        findsOneWidget,
      );
      expect(find.text('Copy source link'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
