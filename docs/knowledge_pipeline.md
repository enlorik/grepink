# Grepink knowledge pipeline

## Overview

Grepink is a notes-first app. When a user asks a question, the goal is to produce a durable note draft grounded in evidence — not to simulate a chat session.

## Pipeline steps

```
question
  │
  ▼
local evidence retrieval   ← local Grepink notes, always first
  │
  ▼
external evidence fetch    ← web provider (optional, configurable)
  │
  ▼
delta detection            ← what does web evidence add beyond local notes?
  │
  ▼
summary writer (LLM)       ← writer/organizer, not source of truth
  │
  ▼
note draft (markdown)
  │
  ▼
review panel               ← user reads draft and sources
  │
  ├─ save as new note
  ├─ append to existing note
  └─ discard
```

No step auto-saves. The user must make an explicit decision.

## Evidence priority order

1. **Local Grepink notes** — always gathered first.
2. **Brave AI Answers** — design intent; not currently implemented. Must not be faked or scraped. Falls back to `[]` if a real supported access path is unavailable.
3. **Brave regular search** — practical external fallback when Brave AI Answers is disabled, unsupported, or returns nothing.

If external evidence is empty or fails, ingestion continues safely with local evidence only.

## LLM role

The LLM receives gathered evidence and writes a draft. It does not invent facts. Source URLs from local notes and web results must survive into the draft and the saved note.

## Delta detection

The delta detector compares local and web evidence to flag what is genuinely new. Deltas are surfaced in the review panel so the user can judge which external claims to keep.

## Review actions

| Action | Result |
|---|---|
| Save as new note | Creates a new note from the draft markdown |
| Append to existing note | Appends draft content to the selected note |
| Discard | Drops the draft; no persistence |

## What this pipeline does not do

- No auto-save of generated notes.
- No Brave AI Answers without a real supported API path.
- No browser scraping.
- No API keys in source, tests, logs, or docs.
- No LLM hallucination substituting for grounded sources.
