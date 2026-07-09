# Claim review smoke test

Manual checklist for verifying the ask -> review -> draft -> save/append flow
end to end in a running app. Pair this with the automated coverage in
`test/search_screen_claim_review_e2e_test.dart`, which exercises the same
path with fakes and no network calls.

## Setup

- Run the app (`flutter run`).
- Have at least one existing note in Grepink so the "append to existing
  note" step has a target.
- A grounded answer provider must be configured for the full flow. If none
  is configured, skip to [Setup-required state](#setup-required-state)
  below — that is expected, safe behavior, not a bug.

## Checklist

1. **Ask a question**
   - Open search, type a question, submit.
   - Expect a brief loading indicator, then either grouped claim review
     results or one of the empty/error states below.

2. **Review grouped claims**
   - Confirm the groups you'd expect are present: New claims, Better
     sources, Possible contradictions to review, Uncertain, Already in your
     notes.
   - Confirm New claims and Better sources are checked by default.
   - Confirm Possible contradictions, Uncertain, and Already-known claims
     are **not** checked by default.
   - Confirm already-known claims are visible (not hidden), just unselected.

3. **Toggle a claim**
   - Uncheck a default-selected claim, check a default-unselected one.
   - Confirm the selection visibly updates.

4. **Generate a draft**
   - With nothing saveable selected, confirm "Generate draft" is disabled
     and the helper text explains why.
   - Select at least one saveable claim, confirm the button becomes enabled.
   - Tap it. Confirm a markdown preview appears with a source count, and
     that unselected/already-known claims and the raw answer text do not
     appear in the preview.

5. **Save as a new note**
   - Tap "Save as new note".
   - Confirm a saving -> saved transition, and that a new note now exists
     with exactly the previewed markdown content.
   - Confirm the save button disables afterward (no duplicate note on a
     second tap).

6. **Append to an existing note**
   - Run the flow again (or discard and re-ask), generate a new draft.
   - Pick an existing note from the target picker and tap "Append to
     existing note".
   - Confirm the original note content is preserved, the new content is
     appended below a visible separator, and source links survived.

7. **Discard**
   - Start a review, generate a draft, then tap "Discard".
   - Confirm review results, selection, and the draft all clear, and the
     screen returns to a clean ask state.
   - Confirm any notes saved earlier in this session are untouched.

## Error / empty states

- **Empty answer**: ask something the provider can't answer; expect a plain
  "no grounded answer was found" message, not a stack trace.
- **No claims extracted**: expect a plain "no claims could be extracted"
  message.
- **All claims already known**: expect a "nothing new found" style message
  instead of an empty-looking group list.
- **Ingestion failure**: confirm the error message is plain language with a
  retry option, and contains no stack trace, exception type, or API key.
- **Save/append failure**: confirm a plain failure message and that the
  draft is not marked saved/appended.

## Setup-required state

- With no grounded answer provider configured, asking a question should
  show a clear setup-required message instead of attempting a request or
  fabricating an answer.
- Confirm no API key or provider credential is visible anywhere on screen.

## What "pass" looks like

- Every step above matches its expected behavior.
- No API keys, tokens, or stack traces are ever visible.
- No note is created or modified except through an explicit save/append tap.
