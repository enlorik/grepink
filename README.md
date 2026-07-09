# grepink

## Claim review (ask -> review -> draft -> save)

Grepink can answer a question with a grounded answer, then break that answer
into individual claims you can review against your own notes before anything
is saved.

The flow, in order:

1. **Ask a question** in the search screen.
2. **Review grouped claims** — results are grouped into New claims, Better
   sources, Possible contradictions to review, Uncertain, and Already in your
   notes.
3. **Select/deselect claims** — new claims and better-source claims are
   selected by default; contradictions, uncertain claims, and already-known
   claims are not.
4. **Generate a draft** — builds a markdown preview from only the claims you
   selected.
5. **Save as a new note**, or **append to an existing note**.
6. **Discard** at any point to clear the review session without touching any
   saved notes.

### Safety rules

- Nothing is saved automatically. Saving/appending always requires an
  explicit tap.
- Only the claims you selected go into the generated draft — unselected and
  already-known claims never appear in it.
- The raw grounded answer text is never saved, only the per-claim markdown
  built from your selection.
- Already-known claims are shown for context but cannot be selected or
  saved.
- There is no fake/simulated Brave AI Answers response anywhere in the app —
  if a grounded answer provider isn't configured, the UI shows a
  setup-required state instead of making anything up.
- API keys and provider credentials are never rendered in the UI or written
  into generated notes.

### Manually testing the flow

See [`docs/claim_review_smoke_test.md`](docs/claim_review_smoke_test.md) for
a step-by-step manual checklist, or run the automated coverage:

```
flutter test test/search_screen_claim_review_e2e_test.dart
```
