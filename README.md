# grepink

## Claim review

Grepink can answer a question with a grounded answer, then break that answer
into individual claims you can review against your own notes before anything
is saved.

### Architecture

1. **Ask a question** in the search screen.
2. A grounded answer is fetched only when a real provider is configured.
   In the default build, no provider is wired up — the UI shows
   `Grounded claim review is not available yet in this build.` and the
   pipeline does not run.
3. The answer is split into individual claims by an extraction step.
4. Each claim is classified against your local notes by a deduplication
   step.
5. Claims are grouped and shown so you can review them.
6. You select which claims to include.
7. **Generate draft** builds a markdown preview from only the selected
   saveable claims.
8. **Save as new note** or **Append to existing note** persist the draft.
   Nothing is saved automatically.
9. **Discard** clears the review session without touching any persisted
   notes.

### Claim classifications

| Classification | Selected by default | Saveable | Notes |
|---|---|---|---|
| New claims | Yes | Yes | |
| Better sources | Yes | Yes | Already in notes, but this source may improve the existing claim |
| Possible contradictions | No | Yes | Selectable, but not selected by default — review carefully |
| Uncertain | No | No | Cannot be added to a draft |
| Already in notes | No | No | Shown for context; may appear in a collapsible section |

### Generate draft rules

- **Generate draft** is enabled only when at least one saveable claim is
  selected.
- Selecting an unsaveable claim (uncertain or already-known) does not
  enable it.
- When saveable claims exist but none are selected, the UI shows:
  `Select at least one claim to generate a draft. Contradictions are not selected by default.`
- When the review contains no saveable claims at all, the UI shows:
  `No claims in this review can be added to a draft.`

### Persistence rules

- Nothing is saved automatically; every write requires an explicit tap.
- **Save** creates a new note from the draft markdown.
- **Append** adds the draft below a separator in the target note, preserving
  its existing content.
- The exact same generated draft content cannot be both saved and appended
  to a note — after a successful Save, Append is blocked for that content,
  and vice versa.
- Repeating Save or Append for the same content does not duplicate it.
- A different generated draft (different claim selection) may still use
  either path independently.

### Discard rules

- Discard clears only the current claim-review session.
- It does not delete or undo persisted notes.
- Discard is disabled while a save or append is in flight.

### Content and secret safety

- Only selected saveable claim text is included in the generated draft.
- Raw grounded-answer prose is never copied into a note.
- Provider names are display-only and are sanitized before rendering —
  values that are empty, contain control characters, exceed 64 characters,
  or match credential patterns are replaced with nothing.
- Provider names are never written into generated markdown.
- Exception text, credentials, API keys, and tokens must not appear in
  the UI or in generated notes.
- No fake grounded-answer response is generated when the provider is
  absent — the UI shows the provider-not-configured state instead.

### Testing

The automated end-to-end test exercises the complete configured flow using
deterministic fakes, with no network calls, real API keys, or external
provider availability:

```shell
flutter test test/search_screen_claim_review_e2e_test.dart
```

Focused unit and widget tests also cover concurrency, retries, safe error
messages, provider-label sanitization, selection rules, and
duplicate-persistence guards.

For manual verification steps, see
[`docs/claim_review_smoke_test.md`](docs/claim_review_smoke_test.md).
