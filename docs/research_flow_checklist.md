# Document and evidence flow

Diagnosis: inline citation labels cluttered prose, the notebook consumed a fixed
260 px, separate note/answer inspectors competed for space, and generated drafts
used the literal question as their title and inserted a report inside the note.

- [x] Replace the fixed library with a bounded note dropdown; protect unsaved edits.
- [x] Hide citation labels while preserving original URLs and meaningful linked prose.
- [x] Share one evidence inspector between saved text, reviewed claims and draft previews.
- [x] Keep evidence visible while typing questions, with no answer-covering overlay.
- [x] Route wheel gestures over sourced text to quotes and successive sources.
- [x] Offer contextual Add below controls and preserve explicit Save.
- [x] Use topic titles and insert prose without repeated question/report headings.
- [ ] Verify pointer, focus, insertion, citation preservation and responsive layouts.
- [ ] Inspect rendered fixtures and publish tested preview downloads.

Design references and decisions:
- Craft, Apple's Mac App of the Year 2021: keep writing and organising in one document.
  https://apps.apple.com/us/story/id1591089619
- Craft Assistant: review and insert results into the document in context.
  https://www.craft.do/blog/how-to-use-craft-ai-assistant
- Apple Design Awards: direct, platform-appropriate interaction and clear information.
  https://developer.apple.com/design/awards/2021/

The evidence rail is our adaptation, not a claim that these products use this
exact layout. Matching source text remains a relevance heuristic. The narrow
layout uses a bounded evidence tray rather than a floating overlay. No generated
prose is saved automatically or rewritten as verified fact.
