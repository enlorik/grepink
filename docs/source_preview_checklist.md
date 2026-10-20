# Source preview checklist

## First delivery: quiet claim review

- [x] Replace repeated raw URL lists with one compact source-count button per claim.
- [x] Deduplicate visible sources by exact URL without changing saved URLs or save eligibility.
- [x] Reuse provider citation titles and show up to two sentences of its source excerpt.
- [x] Say explicitly when a provider supplies no excerpt; never present generated claim text as a source quotation.
- [x] Show a quick excerpt tooltip on mouse hover.
- [x] Add a modeless, pinned source pane that follows hovered or keyboard-focused claims.
- [x] Support tapping source buttons on mobile, with a close control and scrollable preview.
- [x] Copy the original webpage link, with a browser text fragment when a real excerpt is available.
- [x] Preserve source URLs in generated drafts, saved notes, backups, and sync.
- [ ] Pass Flutter analysis/tests and Android, Windows, and iOS CI builds.
- [ ] Test the released build on the actual Windows laptop and Samsung tablet.

## Follow-up: live webpage companion

- [ ] Choose and validate an embedded browser implementation for Windows, Android, and iOS before adding a native dependency.
- [ ] Open a live webpage in a separate modeless window or docked browser pane, switching only while follow mode is enabled.
- [ ] Locate an exact source excerpt in the loaded page, scroll to it, and highlight it; show a clear fallback when it is absent.
- [ ] Handle sites that block embedding, require authentication, or change their content.
- [ ] Keep navigation restricted to HTTP(S), prevent automatic downloads/popups, and avoid executing page-provided instructions.
- [ ] Add timeouts, cancellation, cache limits, and explicit user controls before introducing page fetching.
- [ ] Extend the same source-reading controls to saved-note reading and draft previews without changing their editable source Markdown.

The first delivery previews source metadata already returned by the provider, not a screenshot or full webpage. It does not fetch arbitrary URLs when the mouse moves. Browser text highlighting depends on browser support and an exact match in the page; a link is not evidence that a matching passage was found. Provider citation associations may cover the whole answer rather than a particular claim, so the pane must not assert that every listed source proves that claim. The original Markdown and source URLs remain available when editing or exporting notes.

## Readable formatting follow-up

- [x] Render claim Markdown (bold, emphasis, code, headings and lists).
- [x] Render source excerpts with the same Markdown renderer, including tables.
- [x] Preserve provider line breaks in structured excerpts; bound long previews.
- [x] Use visible words rather than Markdown markers in copied text-fragment links.
- [x] Keep checkbox selection working and prevent remote Markdown image requests.
- [ ] Verify formatting and popup sizing on the Windows build.
- [ ] Original website layout: deferred to the embedded-browser follow-up above.

Formatting changes only presentation; saved claims and citation URLs remain intact.
Plain prose retains the two-sentence preview; structured snippets can show up to
1,600 characters to retain list/table layout. The preview cannot recover formatting
that the provider already removed.
