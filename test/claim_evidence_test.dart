import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/models/grounded_claim_ingestion_result.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/services/claim_extraction_service.dart';
import 'package:grepink/services/claim_review_mapper.dart';
import 'package:grepink/services/selected_claims_draft_builder.dart';
import 'package:grepink/services/note_source_document.dart';
import 'package:grepink/widgets/claim_source_preview.dart';

void main() {
  test(
    'two claims citing one webpage retain their different exact excerpts through saving',
    () {
      const first = 'Tuples group fields.';
      const second = 'Arrays repeat a type.';
      const url = 'https://example.com/types_(guide)';
      expect(
        NoteSourceDocument.passageKey('C# and snake_case'),
        'c# and snake_case',
      );
      final citations = [
        const GroundedAnswerCitation(
          id: '1',
          title: 'Type guide',
          url: url,
          snippet: 'A tuple holds distinct fields.',
          startIndex: 0,
          endIndex: first.length,
        ),
        const GroundedAnswerCitation(
          id: '2',
          title: 'Type guide',
          url: url,
          snippet: 'An array repeats one element type.',
          startIndex: first.length + 1,
          endIndex: first.length + 1 + second.length,
        ),
      ];
      final answer = GroundedAnswer(
        question: 'Types',
        answerText: '$first $second',
        citations: citations,
        providerName: 'Test',
        generatedAt: DateTime(2026),
      );
      final extracted = const RuleBasedClaimExtractionService().extract(answer);
      expect(
        extracted[0].evidence.single.snippet,
        'A tuple holds distinct fields.',
      );
      expect(
        extracted[1].evidence.single.snippet,
        'An array repeats one element type.',
      );
      final ingestion = GroundedClaimIngestionResult(
        question: 'Types',
        answerText: answer.answerText,
        providerName: 'Test',
        knownClaims: [],
        betterSourceClaims: [],
        contradictionClaims: [],
        uncertainClaims: [],
        citations: citations,
        newClaims: [
          for (final claim in extracted)
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
      expect(
        claimSourcePreviews(items[1], citations).single.excerpt,
        citations[1].snippet,
      );
      final draft = const SelectedClaimsDraftBuilder().build(
        question: 'Types',
        selected: items,
        providerName: 'Test',
        citations: citations,
      );
      expect(draft.sourceCount, 1);
      expect(NoteSourceDocument.sources(draft.markdownContent), hasLength(2));
      final reopened = NoteSourceDocument.forPassage(
        draft.markdownContent,
        second,
        [url],
      );
      expect(reopened.single.snippet, citations[1].snippet);
      expect(
        NoteSourceDocument.forPassage(
          draft.markdownContent,
          'An edited different claim.',
          [url],
        ).single.snippet,
        isNull,
      );
    },
  );
  test(
    'legacy whole-page excerpts are not presented as claim-specific evidence',
    () {
      final stored = NoteSourceDocument.encode([
        const GroundedAnswerCitation(
          id: 'old',
          title: 'Page',
          url: 'https://example.com',
          snippet: 'Unmapped global snippet.',
        ),
      ]);
      expect(
        NoteSourceDocument.sources(stored).single.snippet,
        'Unmapped global snippet.',
      );
      expect(
        NoteSourceDocument.forPassage(stored, 'A separate fact.', [
          'https://example.com',
        ]).single.snippet,
        isNull,
      );
    },
  );
}
