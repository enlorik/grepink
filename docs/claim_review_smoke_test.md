# Claim review smoke test

Manual checklist for verifying the claim-review flow in a running app.
Pair this with the automated coverage in
`test/search_screen_claim_review_e2e_test.dart`, which exercises the same
configured path with deterministic fakes and no network calls.

---

## A. Default-build smoke test

**Run this with the normal app (`flutter run`).** No provider configuration
is required or expected — the repository does not currently provide an
end-user setup path for grounded-answer providers.

1. Run the app.
2. Open Search.
3. Enter a non-empty question and submit it.
4. Verify the claim-review area shows:
   > Grounded claim review is not available yet in this build.
5. Verify no claim-review loading indicator remains.
6. Verify no claim groups appear.
7. Verify no provider attribution appears.
8. Verify no Retry button appears for this state (provider-not-configured
   is a permanent state in the default build, not a transient error).
9. Verify no credential, token, stack trace, or fabricated grounded answer
   is shown anywhere on screen.

This path verifies the provider-not-configured state. It does not exercise
claim classification, draft generation, or persistence.

---

## B. Configured development-build smoke test

**Run this only when a development build has a real configured provider.**
The repository does not currently provide an end-user setup path; this
section applies only to development harnesses that override the provider.

### 1. Ask

- Submit a non-empty question.
- Confirm a loading indicator appears briefly and then completes.
- If the provider supplies a non-empty, non-credential display name,
  confirm it is shown as attribution above the group list.
- Confirm no API key, token, or internal error text is visible.

### 2. Review groups

- Confirm group order: **New claims → Better sources → Possible
  contradictions → Uncertain → Already in notes** (empty groups may be
  hidden).
- Confirm **New claims** and **Better sources** start checked.
- Confirm **Possible contradictions** starts unchecked but its checkboxes
  are interactive.
- Confirm **Uncertain** and **Already in notes** items are visible but
  their checkboxes are disabled (cannot be toggled).
- If **Already in notes** contains more than three items, confirm it may
  start collapsed; expanding it should reveal matched local note context
  where available.

### 3. Generate button

Test the two disabled states:

- **Saveable claims exist, none selected**: uncheck all default-selected
  claims and confirm the Generate button is disabled and shows:
  > Select at least one claim to generate a draft. Contradictions are not
  > selected by default.
- **No saveable claims at all**: if the review contains only Uncertain or
  Already-in-notes items, confirm the button is disabled and shows:
  > No claims in this review can be added to a draft.

Then select at least one saveable claim and confirm the Generate button
becomes enabled and the helper text disappears.

### 4. Draft preview

After tapping Generate:

- Confirm selected saveable claims appear in the markdown preview.
- Confirm deselected claims do not appear.
- Confirm Uncertain and Already-in-notes claims do not appear even if
  somehow selected.
- Confirm raw grounded-answer prose does not appear.
- Confirm the provider name does not appear in the markdown content.
- Confirm source titles and URLs are present in the preview.
- Confirm the source count matches the number of distinct source URLs
  actually used by the included claims.

### 5. Save path

- Tap **Save as new note**.
- Confirm the button shows a saving transition and then a saved
  confirmation.
- Confirm exactly one new note was created with the previewed markdown
  content.
- Confirm tapping Save again does not create a duplicate note.
- Confirm **Append to existing note** is blocked for this exact draft
  content after it has been saved.

### 6. Append path

Use a genuinely different draft (different claim selection) or start a
fresh review.

- Select a target note from the picker.
- Tap **Append to existing note**.
- Confirm the target note's original content is preserved.
- Confirm the new markdown is appended below a visible separator (`---`).
- Confirm tapping Append again to the same target does not duplicate the
  content.
- Confirm **Save as new note** is blocked for this exact appended draft
  content.

### 7. Discard

- Wait until no save or append is in flight.
- Tap **Discard**.
- Confirm the review groups, selection, draft, error messages, and
  provider attribution all clear.
- Confirm the screen returns to a clean ask state.
- Confirm notes persisted earlier in this session remain unchanged.

---

## Error and empty states

Use the exact messages currently shown in the app:

| State | Expected UI message |
|---|---|
| Provider not configured | `Grounded claim review is not available yet in this build.` |
| No grounded answer found | `No grounded answer was found for this question.` |
| No claims extracted | `No claims could be extracted from the answer.` |
| All claims already known | `Everything in this answer is already in your notes.` |
| Review failure | Plain language error with Retry option; no stack trace or exception type |
| Draft-generation failure | Plain language error; no stack trace or raw exception text |
| Save failure | Plain language error; draft not marked saved; retry where supported; no repository details |
| Append failure | Plain language error; draft not marked appended; retry where supported; no repository details |

---

## Automated verification

`test/search_screen_claim_review_e2e_test.dart` exercises the full
configured flow end-to-end using deterministic fakes, with no network
calls, real API keys, or external provider availability. Run it with:

```shell
flutter test test/search_screen_claim_review_e2e_test.dart
```

Separate focused tests cover concurrency guards, retries, safe error
messages, provider-label sanitization, selection rules, and
duplicate-persistence guards. Run the full suite with:

```shell
flutter test
```
