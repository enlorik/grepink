# Grepink agent rules

Grepink is a notes-first memory app. Keep changes small, safe, and reviewable.

## PR discipline

- Every PR must be a sensible whole.
- Prefer small PRs over broad rewrites.
- Do not mix unrelated features in one PR.
- Use atomic commits: each commit should represent one logical change.
- Do not knowingly leave `flutter analyze` or `flutter test` failing.
- Before marking a PR ready, run:
  - `flutter pub get`
  - `flutter analyze`
  - `flutter test`
- If CI fails, fix the same PR branch. Do not create a separate cleanup PR for tiny analyzer or test failures.

## Scope control

- Do not add features not requested in the task.
- Do not redesign UI unless explicitly requested.
- Do not add sync, Railway, Google, Brave AI Answers, auth, or database migrations unless explicitly requested.

## Secrets and provider safety

- Never store API keys or secrets in SharedPreferences, source code, test fixtures, logs, screenshots, or PR descriptions.
- API keys must use secure storage abstractions.
- Prefer interfaces and factories for external providers.
- Keep tests network-free.
- Use injected fake clients and services in tests.

## Product behavior

- Grepink is notes-first, not chat-first.
- Questions should produce durable note drafts, not chat history.
- Do not auto-save generated notes unless explicitly requested.
- Web-derived claims must preserve source URLs.

## PR descriptions

Every PR description must include:

- Summary
- Changed files
- Tests run
- Risks / follow-up
- What was intentionally not changed
