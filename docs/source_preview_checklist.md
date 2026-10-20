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

## Continuous reading view

- [x] Default to one flowing passage, preserving original answer order.
- [x] Keep inline bold, emphasis and code formatting.
- [x] Click/tap a claim to toggle ignored strikethrough and draft inclusion.
- [x] Preserve existing eligibility and contradiction selection rules.
- [x] Hover a claim to show its source popup; keep it open while entering it.
- [x] Scroll over the passage to scroll the open source popup, not the page.
- [x] Reset source scrolling when moving to a different claim.
- [x] Provide previous/next, include/ignore and sources controls for touch/keyboard.
- [x] Retain a Detailed list switch for full classification explanations.
- [ ] Verify the new reading interactions on Windows and a touch device.

A long answer can still exceed a screen; the reading view removes card spacing,
per-claim controls and repeated source lists rather than shrinking the text.
The popup continues to show provider excerpts, not a live website.

## Article typography repair

Diagnosis: the first reading view flattened Markdown blocks into inline spans,
stripped their trailing breaks, used the whole window for text, and treated an
HTML-escaped AST as display text. This glued headings/lists together, exposed
`&amp;` and produced long, brightly highlighted lines.

- [x] Keep an article rather than returning to individual claim cards.
- [x] Preserve headings, paragraph breaks, nested/numbered lists and tables.
- [x] Use hanging list indentation and horizontally scrollable code/tables.
- [x] Limit reading width to 740 logical pixels with consistent type and spacing.
- [x] Render literal ampersands and Rust references using a text AST.
- [x] Replace solid pink highlighting with a subtle blush hover tint.
- [x] Retain ignore/restore, original order, hover sources and popup scrolling.
- [ ] Check the new typography visually on the Windows beta.

Long runs of sentence claims receive paragraph breaks at claim boundaries; the
original saved claim text is unchanged. Missing upstream Markdown cannot be
reconstructed reliably, so this repair preserves structure present in the claims.


## Reading workspace UX repair

The Windows screenshot showed a large internal gap because the article had a
740-pixel cap while the preview was positioned against the viewport edge.
The page had no shared grid tying those two regions together.

Research and choice:
- [Material supporting-pane guidance](https://developer.android.com/develop/ui/compose/layouts/adaptive/canonical-layouts#supporting_pane) places related secondary content beside the primary document on wide screens and adapts it on compact screens.
- [Flutter anchored overlay layout](https://api.flutter.dev/flutter/widgets/OverlayPortal/OverlayPortal.overlayChildLayoutBuilder.html) supplies layout-time position/size information so the preview follows the workspace while scrolling and resizing.
- Choose a centered reading workspace with an adjacent supporting source pane; stretching prose across the whole window would recreate the previous long-line problem, while a viewport-edge popup would retain the gap.

Delivery checklist:
- [x] Center the workspace with a maximum width of 1136 logical pixels.
- [x] Keep article width at most 740, source width 340, and their gutter 24.
- [x] Align the source pane to the reading body and clamp it inside the viewport during scrolling.
- [x] Show a quiet Sources prompt before a sentence is hovered.
- [x] Use an outlined companion pane instead of a heavy floating shadow on desktop.
- [x] Keep the compact popup when content width is below 960 or text scaling is above 1.5.
- [x] Preserve hover matching, pin/close, ignore/restore, source wheel scrolling and citation URLs.
- [x] Test pane geometry, scroll clamping, open-pane window resizing and narrow fallback.
- [ ] Inspect the rendered CI layout preview before publishing the beta.
- [ ] Verify the new beta on the actual Windows device and a touch device.

The CI-only preview uses the real review widgets with a representative Rust
fixture and locally loaded Inter/monospace fonts; font preparation happens before
network-free tests. It is a layout QA image, not a screenshot of the user's
running Windows application. No production provider request, note, setting or
sync behavior changes. The declared Flutter floor matches the existing lockfile.
