# Inline reading fixes

- [x] Inspect the user's installed-app screenshot and trace the current code.
- [x] Load a linked public page automatically when a hovered line has no saved excerpt.
- [x] Show a relevant passage and formatted page text, with cache, loading/error states and retry.
- [x] Remove the global Read/Edit switch and edit only the clicked logical line in place.
- [x] Keep citation URLs outside the editable text and preserve neighboring lines exactly.
- [x] Preserve list indentation, repair duplicate ASCII/Unicode markers outside code, and support Tab / Shift+Tab.
- [x] Add network-free regression tests for real hover, line editing, source loading and nested lists.
- [ ] Inspect rendered fixtures, verify all CI jobs, and publish a Windows preview in Releases.

Existing saved notes are not silently rewritten by display repair; explicit Save
persists draft edits. Page fetching sends only the source URL, never note text,
provider keys or sync credentials. Unavailable sites show a clear fallback.

References:
- https://api.flutter.dev/flutter/material/TextField/onTapOutside.html
- https://docs.flutter.dev/cookbook/forms/focus
- https://spec.commonmark.org/spec
