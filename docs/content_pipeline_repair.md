# Content repair and warm reading theme

## Observed failures

The Kotlin specification contains three copies of a formula: semantic MathML, its TeX annotation and hidden visual KaTeX HTML. Concatenating DOM text exposed all three as garbled prose. The provider adapter also removed arbitrary paired angle-bracket content, so programming templates could be mistaken for provider metadata. Sentence splitting could separate italics, Markdown links or trailing numbered references from the passage they belonged to. Inline Markdown sources were ignored when the provider omitted structured citations.

## Approaches considered

1. Embed a full browser: original CSS and math could render, but this adds platform/runtime dependencies and still does not repair citation data before saving.
2. Rewrite answers or launch extra searches for every uncited passage: potentially richer evidence, but adds paid provider calls and cannot safely assume that retrieved text proves a claim.
3. Preserve the original answer, recover only explicit references, and normalize the source DOM before rendering: deterministic, testable without network calls and compatible with the current notes format; this is the selected approach.

## Implementation

- Strip only provider control blocks such as citation/usage/think metadata; retain template syntax and provider source titles.
- Preserve complete emphasis and code during sentence extraction.
- Attach trailing references to the preceding passage, including references directly after punctuation.
- Recover numeric references using matching provider IDs and recover explicit Markdown source links when structured citations are absent.
- Ignore reference-shaped text inside code; keep ambiguous answer-level clusters uncertain even after recovering a separate inline link.
- Keep one readable MathML representation per KaTeX formula, retaining powers, subscripts and fractions as plain notation; do not concatenate hidden HTML or TeX annotations.
- Show a mapped-source coverage count without claiming that links establish factual correctness.
- Use a blush-to-cream workspace, plum text, tinted evidence panels and compact reading rhythm inspired by the user's Discord screenshot; preserve the notebook dropdown, passage editing, explicit saving and shared evidence navigation.

## Primary references

- Brave citation response contract: https://api-dashboard.search.brave.com/documentation/services/grounding
- Reproduced page structure: https://kotlinlang.org/spec/type-system.html
- Discord theme surfaces: https://discord.com/blog/bring-your-vibe-to-discord-with-new-themes-in-nitro
- Discord consistency and spacing: https://discord.com/blog/improving-mobile-with-squircles-styles-and-spacing

## Verification and limits

Regression tests cover semantic formula extraction, template preservation, source positions, explicit numeric and Markdown references, code examples, intact emphasis and uncertain-source handling. Widget/layout checks cover the warm palette and existing hover, scroll, insertion and narrow keyboard workflows. CI and released previews are recorded in the PR description after validation.

Missing provider citations cannot be invented, and citations already lost in previously saved notes are not reconstructed automatically. Static formula notation is a readable fallback, not a full TeX typesetting engine. Source coverage counts association, not logical proof. No additional paid searches, cloud API changes, sync changes, migrations or automatic note rewriting are introduced.
