# Grepink knowledge pipeline

This document describes the current **validated draft pipeline** for Grepink's notes-first knowledge flow. It reflects the active green PR stack that builds on `main`, rather than claiming every step is already merged.

## Product shape

Grepink is **notes-first, not chat-first**. A user asks a question so Grepink can turn that question into durable notes that the user explicitly reviews before anything is saved.

## Pipeline

1. **User question**
   - The user enters a question in the ask flow.
   - Grepink treats that question as a request to grow the note base, not to start a chat thread.

2. **Local evidence retrieval**
   - Existing notes are searched first.
   - Matching local notes become the primary evidence source for the draft.

3. **Web evidence provider**
   - The safe default is no external evidence (`EmptyWebEvidenceProvider`).
   - If Brave regular search is configured and enabled, Grepink can use Brave search results as an external evidence fallback.
   - Source URLs are preserved so the draft can show where claims came from.

4. **Delta detection**
   - Incoming evidence is compared against local knowledge.
   - Grepink distinguishes new claims, related-but-new information, better sources, and duplicates.
   - Duplicate handling remains part of the review story so users can see what was ignored.

5. **Summary writer**
   - The LLM writes and structures the candidate note draft.
   - The LLM is a **writer/summarizer**, not the primary truth source.
   - Evidence and citations should stay grounded in local notes first, then external evidence when available.

6. **NoteDraft review**
   - Grepink shows a draft preview before any persistence happens.
   - The review UI surfaces the generated markdown, recommendation, source groupings, and citation URLs.

7. **Save / append / discard**
   - Nothing is auto-saved.
   - The user must explicitly choose to save as a new note, append to an existing note, or discard the draft.
   - Append remains explicit and target-based rather than silently creating a new note.

8. **Source preservation**
   - Source URLs stay visible during review and remain preserved in saved or appended markdown.
   - Generated-note metadata can be carried in markdown comments so the result stays traceable without hidden app state.

## Provider order

The intended provider order for the green draft stack is:

1. local Grepink notes
2. Brave regular search fallback, if configured
3. future Brave AI Answers, **only if a real supported access path exists**
4. LLM as note writer, **not** primary truth source

## Intentionally not implemented

- no auto-save
- no chat history
- no Railway sync
- no auth
- no Google integration
- no fake Brave AI Answers
- no browser UI scraping

## Brave AI Answers status

Brave AI Answers is still a design/discovery topic, not a shipped provider path. Grepink should only use it if there is a real supported integration that preserves grounded answer text plus cited source URLs. Until then, Brave regular search remains the external fallback path.
