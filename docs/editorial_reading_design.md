# Editorial reading and evidence

## Diagnosis

The user's Rust screenshot exposed a hierarchy problem rather than a need for a new cloud backend: oversized default Markdown headings, generous paragraph rhythm, repeated note/source titles, a raw URL displayed twice, and an excerpt repeated as article context. Article images disappeared when excerpt matching failed; responsive images and linked figure captions were missed by the parser. Existing Markdown images in notes rendered as alt text only.

## Research and decisions

- Craft was Apple's 2021 Mac App of the Year: https://apps.apple.com/us/story/id1591089619 — adopt coherent document hierarchy and useful visual blocks, not decorative cards around every sentence.
- Bear won an Apple Design Award in 2017: https://www.apple.com/newsroom/2017/06/apple-design-awards-celebrate-the-best-in-innovation-and-creativity/ — its typography controls distinguish line height, paragraph spacing and line width: https://bear.app/faq/typography-options/.
- Readwise documents a 1.4 default line spacing, bounded reading widths and collapsible side panels: https://docs.readwise.io/reader/docs/faqs/appearance — use compact evidence with optional article context, preserving a readable main document.
- Craft's formatting guide explicitly teaches headings, lists, toggles and callouts: https://www.craft.do/learn — express structure semantically instead of making all text equally large or bold.

Our adaptation uses 16px note text at 1.5 line height, 14px source text, restrained headings, aligned document title/body, smaller passage insertion controls, quiet pink quote rules, human-readable article titles and a small domain label with the full URL available on hover and through Copy source link. Long excerpts are expandable; article context is disclosed separately. Stored note text and exported citations are not rewritten.

## Content layer

This task changes the Flutter article parser and reader; Railway remains a note-sync transport. A new server endpoint cannot fix default Markdown styling. The parser now prefers article content over surrounding main-page material, retains article-header titles, chooses responsive raster candidates, finds nested figure captions, and preserves table structure. Image downloads keep the existing public-URL, byte, MIME, redirect and cache bounds. Existing Markdown note image URLs use that same raster loader. Figures remain available when an exact quote cannot be located, with an explicit illustration label; they never become proof of the selected claim. No stock imagery or invented excerpts are added.

## Checklist

- [x] Diagnose the screenshot and research primary design references.
- [x] Apply a shared type scale and tighter passage spacing.
- [x] Consolidate source identity, quote and optional article context.
- [x] Render declared Markdown note images through the bounded loader.
- [x] Improve article titles, responsive images, captions and tables.
- [x] Add network-free parser and widget regressions.
- [ ] Complete CI and inspect rendered desktop/narrow-window fixtures.
- [ ] Publish verified Windows and Android preview assets.
- [ ] Physical-device smoke test.

## Limits

This is a static reader, not an embedded browser: original website scripts, CSS, protected content, SVG diagrams and AVIF images are not rendered. Missing images are not fabricated. Finding cited words on a page confirms text presence, not logical support. Main note images are displayed when the Markdown already includes their URL; this change does not silently insert pictures into saved notes or summarize away existing text. The screenshot's question/content mismatch requires checking the generated answer itself; visual formatting cannot establish that it answered the question.
