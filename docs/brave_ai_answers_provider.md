# Brave AI Answers provider design

## Goal

Use Grepink as a notes-first system:

1. the user asks a question
2. Grepink checks local notes first
3. Grepink uses grounded external evidence when needed
4. Grepink writes durable note drafts instead of acting like a chat transcript

The desired primary external source is the **Brave AI answer / grounded summary shown under the Brave search bar**, because it can provide a synthesized answer with cited links.

## Important constraint

This is **not implemented** in the current app.

Grepink must **not**:

- fake Brave AI Answers
- scrape the Brave browser UI
- claim this works without a real supported access path

If a supported Brave AI Answers API path is unavailable or unclear, Grepink must fail softly to `[]` and use the next provider in the chain.

## Intended provider order

The intended evidence order is:

1. **Local Grepink notes first**
2. **Brave AI Answer / grounded summary** if a real supported provider path exists
3. **Regular Brave Search results** as the fallback external evidence source
4. **LLM summary writer** only as a note writer / organizer, not the primary truth source

This preserves Grepink's product rule: **notes first, not chat first**.

## Proposed interface shape

Two safe options:

### Option A: implement `WebEvidenceProvider`

```dart
class BraveAiAnswerProvider implements WebEvidenceProvider {
  Future<List<EvidenceItem>> fetch(String question);
}
```

Use this when the Brave AI Answers API returns data that already fits Grepink's existing evidence flow.

### Option B: add a specialized grounded-answer interface

```dart
abstract class GroundedAnswerProvider {
  Future<List<EvidenceItem>> fetchGroundedAnswer(String question);
}
```

Use this when the response shape needs explicit handling for:

- answer text
- citation ordering
- answer confidence / provenance metadata

Either way, the provider should still end up returning `EvidenceItem` values so the rest of ingestion can stay consistent.

## Evidence shape expectations

If Brave AI Answers becomes available through a supported path, the provider should:

- preserve the answer text
- preserve cited source URLs
- map the answer into `EvidenceItem`
- use `EvidenceType.aiGroundedAnswer` when appropriate
- return `[]` on unavailable access, empty answers, or provider errors

Suggested mapping:

- `title`: short label such as `Brave AI Answer`
- `content`: grounded answer text
- `sourceUrl`: citation URL for each cited source item
- `type`: `EvidenceType.aiGroundedAnswer`

If the upstream API returns one answer with many citations, Grepink can either:

1. emit one answer-shaped `EvidenceItem` plus separate citation-backed items, or
2. emit one `EvidenceItem` per cited segment

The final choice should preserve citation URLs clearly for review and saved markdown.

## Failure behavior

The provider must fail softly:

- unsupported access path -> `[]`
- missing API key -> `[]`
- provider/network error -> `[]`
- malformed payload -> `[]`

Knowledge ingestion must not crash just because external grounded evidence is unavailable.

## Interaction with current Brave Search fallback

Regular Brave Search remains the practical fallback path when:

- Brave AI Answers is disabled
- Brave AI Answers is unsupported
- Brave AI Answers fails
- Brave AI Answers returns no usable grounded output

That keeps the current external evidence strategy safe:

- default: no external evidence
- configured fallback: regular Brave Search
- future preferred external path: Brave AI Answers, only if real and supported

## LLM role

The LLM should remain the **writer**, not the **source of truth**.

The ingestion pipeline should use the LLM to:

- summarize gathered evidence
- turn evidence into draft markdown
- organize claims for review

The LLM should not replace grounded citations from local notes or Brave sources.

## Implementation checklist for a future real integration

Before implementing Brave AI Answers for real:

1. confirm a supported API or SDK path exists
2. confirm citation URLs are returned in machine-readable form
3. store any required key in secure storage only
4. add provider-selection tests with no real network calls
5. add ingestion tests proving failure falls back safely
6. update review UI to distinguish grounded answer citations from regular web-search citations

Until those conditions are met, this document is the design source of truth and **not** proof of a completed integration.
