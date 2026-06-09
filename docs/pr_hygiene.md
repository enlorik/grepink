# PR hygiene

Short guide for safe, reviewable pull requests in this repo.

## Branching

Always branch from the latest `main`.

```sh
git checkout main
git pull origin main
git checkout -b feature/my-change
```

Never stack a branch on top of another unmerged branch. If your branch
contains commits that belong to a prior open PR, the diff will include
that prior work and confuse the reviewer. Close and recreate the PR
from `main` instead.

## Scope

Keep one PR to one small, coherent purpose. A reviewer should be able
to understand the change in a single sitting. If you are tempted to say
"while I was here I also…", that work belongs in a separate PR.

## What actually matters for review

The actual GitHub diff is authoritative, not the PR description. A
correct, well-scoped diff with a minimal description beats a detailed
description that does not match the diff. When you update a branch,
re-read the diff before marking the PR ready.

## Stale stacked history

If your branch was branched off a feature branch that was later merged
(or rebased), your PR will contain commits that no longer belong to it.
The fix is to close the PR, delete the branch, re-branch from the
updated `main`, cherry-pick or re-apply your changes, and open a new PR.
Do not amend or rebase on top of a live PR — force-pushing shared
branches confuses CI and reviewers.

## Expected PR description sections

Every PR description must include:

- **Summary** — what changed and why (one or two sentences is enough for small fixes)
- **Changed files** — a list of every file modified or created
- **Tests run** — at minimum `flutter analyze` and `flutter test` results
- **Risks / follow-up** — what could go wrong, and what was intentionally left out
- **Intentionally not changed** — explicitly state what is out of scope

## Secrets and API keys

Never put secrets or API keys in:

- source code
- test fixtures or test helpers
- docs or PR bodies
- log strings or comments
- screenshots or issue attachments

API keys must use a secure storage abstraction. If you find a leaked
key, rotate it immediately — do not rely on commit history scrubbing.

## CI must pass before merge

Do not merge a PR while `flutter analyze` or `flutter test` is failing.
If CI fails on your PR, fix it on the same branch. Do not open a new
cleanup PR for a one-line analyzer or test fix that belongs to the
original change.

## Merge order

When multiple PRs are ready to merge, merge the smallest-number (oldest)
clean PR first. This keeps the queue predictable and avoids unnecessary
merge conflicts.

## Draft PRs

Use draft PRs until you have:

- run `flutter pub get`, `flutter analyze`, and `flutter test` locally
- confirmed the diff matches your intent
- filled in all required description sections

Mark a PR ready only when it meets the acceptance bar you would apply
to someone else's code.
