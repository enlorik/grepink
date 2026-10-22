# Notebook learning workspace

## Diagnosis
The note editor used a plain TextField for Markdown, while the home screen used a sparse card grid. Citation excerpts existed only in transient review state. Saving the answer therefore retained URLs but lost the educational source preview.

## Design decision
Use an adaptive list/detail notebook: compact navigation beside the selected rendered note on desktop, a note list opening the same reader on small screens, and an optional research pane beside the note (stacked on compact screens). Reading is the default. Editing exposes Markdown with a rendered preview. Reviewed answers enter the current unsaved draft at the end or after an explicitly chosen heading; saving remains deliberate.

References:
- https://developer.android.com/develop/adaptive-apps/guides/list-detail
- https://developer.android.com/develop/adaptive-apps/guides/build-a-supporting-pane-layout
- https://obsidian.md/help/edit-and-read

A permanent three-column layout was rejected because it makes prose too narrow on laptops. A chat-first home screen was rejected because notes are the durable product. A full rich-text editor conversion was rejected because it would risk existing Markdown and export compatibility.

## Delivery
- [x] Render saved notes as Markdown by default.
- [x] Replace the empty desktop card grid with compact notes and a reader.
- [x] Ask and review inside the notebook without navigating away.
- [x] Choose end-of-note or a heading boundary before inserting reviewed content.
- [x] Require explicit Save and guard switching notes with unsaved edits.
- [x] Retain bounded provider excerpts inside portable Markdown comments.
- [x] Keep source metadata outside the editable text field.
- [x] Inspect saved links on hover or tap without fetching live pages.
- [x] Preserve existing URLs and show an honest fallback for older notes without excerpts.
- [ ] Run CI analysis/tests and Android/iOS/Windows builds.
- [ ] Inspect a rendered widget fixture and publish a tested Windows beta.
- [ ] Actual Windows and touch-device smoke tests.

## Limits
Older saved notes retain URLs but cannot recover provider snippets which were never stored. The source card shows saved excerpts, not a live webpage. Editing remains Markdown with a reading preview, not a WYSIWYG editor. Questions reuse existing providers and local-note retrieval; opening the pane does not make a provider request. No automatic saving, server/schema changes or new credentials.
