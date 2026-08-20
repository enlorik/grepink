import { PoolClient } from 'pg';
import { Mutation, NotePayload } from './schema';
import { hashPayload } from './auth';

export interface AcknowledgedMutation {
  mutationId: string;
  noteId: string;
  revision: number;
}

export interface ConflictResult {
  mutationId: string;
  noteId: string;
  operation: string;
  serverRevision: number;
  serverState: NotePayload | null;
}

export interface SnapshotRow {
  id: string;
  revision: number;
  deleted: boolean;
  title: string | null;
  content: string | null;
  tags: string[];
  keywords: string[];
  isPinned: boolean;
  createdAt: string | null;
  updatedAt: string | null;
}

export interface SyncResult {
  acknowledged: AcknowledgedMutation[];
  conflicts: ConflictResult[];
  snapshot: SnapshotRow[];
}

interface DbNote {
  id: string;
  title: string | null;
  content: string | null;
  tags: string;
  keywords: string;
  is_pinned: boolean;
  created_at: Date | null;
  updated_at: Date | null;
  deleted: boolean;
  revision: string; // pg returns bigint as string
  mutation_id: string;
}

function parseTags(raw: string): string[] {
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed as string[];
  } catch {
    // fall through
  }
  return [];
}

function noteToPayload(row: DbNote): NotePayload | null {
  if (row.deleted || !row.title || !row.content || !row.created_at || !row.updated_at) {
    return null;
  }
  return {
    title: row.title,
    content: row.content,
    tags: parseTags(row.tags),
    keywords: parseTags(row.keywords),
    isPinned: row.is_pinned,
    createdAt: row.created_at.toISOString(),
    updatedAt: row.updated_at.toISOString(),
  };
}

function noteToSnapshot(row: DbNote): SnapshotRow {
  const rev = parseInt(row.revision, 10);
  return {
    id: row.id,
    revision: rev,
    deleted: row.deleted,
    title: row.deleted ? null : row.title,
    content: row.deleted ? null : row.content,
    tags: parseTags(row.tags),
    keywords: parseTags(row.keywords),
    isPinned: row.is_pinned,
    createdAt: row.created_at ? row.created_at.toISOString() : null,
    updatedAt: row.updated_at ? row.updated_at.toISOString() : null,
  };
}

export async function processSyncRequest(
  client: PoolClient,
  mutations: Mutation[],
): Promise<SyncResult> {
  // Acquire advisory lock — single-owner service, correctness > concurrency.
  await client.query('SELECT pg_advisory_xact_lock(1)');

  const acknowledged: AcknowledgedMutation[] = [];
  const conflicts: ConflictResult[] = [];

  // Sort mutations deterministically before processing.
  const sorted = [...mutations].sort((a, b) =>
    a.mutationId < b.mutationId ? -1 : 1,
  );

  for (const mutation of sorted) {
    const payloadJson = JSON.stringify(mutation);
    const payloadHash = hashPayload(payloadJson);

    // Check idempotency.
    const idempRes = await client.query<{
      payload_hash: string;
      outcome: { acknowledged?: AcknowledgedMutation; conflict?: ConflictResult };
    }>(
      'SELECT payload_hash, outcome FROM processed_mutations WHERE mutation_id = $1',
      [mutation.mutationId],
    );

    if (idempRes.rows.length > 0) {
      const prev = idempRes.rows[0];
      if (prev.payload_hash !== payloadHash) {
        throw Object.assign(
          new Error('Mutation ID reused with different payload'),
          { status: 409 },
        );
      }
      // Return cached outcome.
      const cached = prev.outcome;
      if (cached.acknowledged) acknowledged.push(cached.acknowledged);
      if (cached.conflict) conflicts.push(cached.conflict);
      continue;
    }

    // Fetch current row.
    const rowRes = await client.query<DbNote>(
      'SELECT * FROM notes WHERE id = $1',
      [mutation.noteId],
    );
    const current = rowRes.rows[0] ?? null;

    let outcome: { acknowledged?: AcknowledgedMutation; conflict?: ConflictResult };

    if (mutation.operation === 'upsert') {
      const base = mutation.baseRevision;
      const currentRev = current ? parseInt(current.revision, 10) : null;

      const canApply =
        (current === null && base === null) ||
        (currentRev !== null && currentRev === base) ||
        // Applying over an existing tombstone when base matches.
        (current !== null && current.deleted && currentRev === base);

      if (canApply) {
        const { title, content, tags, keywords, isPinned, createdAt, updatedAt } =
          mutation.payload;
        const revRes = await client.query<{ nextval: string }>(
          'SELECT nextval($1)',
          ['revision_seq'],
        );
        const newRev = parseInt(revRes.rows[0].nextval, 10);

        await client.query(
          `INSERT INTO notes (id, title, content, tags, keywords, is_pinned, created_at, updated_at, deleted, revision, mutation_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, FALSE, $9, $10)
           ON CONFLICT (id) DO UPDATE SET
             title = $2, content = $3, tags = $4, keywords = $5, is_pinned = $6,
             created_at = $7, updated_at = $8, deleted = FALSE, revision = $9, mutation_id = $10`,
          [
            mutation.noteId,
            title,
            content,
            JSON.stringify(tags),
            JSON.stringify(keywords),
            isPinned,
            createdAt,
            updatedAt,
            newRev,
            mutation.mutationId,
          ],
        );

        const ack: AcknowledgedMutation = {
          mutationId: mutation.mutationId,
          noteId: mutation.noteId,
          revision: newRev,
        };
        acknowledged.push(ack);
        outcome = { acknowledged: ack };
      } else {
        const serverRevision = currentRev!;
        const serverState = current ? noteToPayload(current) : null;
        const conflict: ConflictResult = {
          mutationId: mutation.mutationId,
          noteId: mutation.noteId,
          operation: 'upsert',
          serverRevision,
          serverState,
        };
        conflicts.push(conflict);
        outcome = { conflict };
      }
    } else {
      // delete
      const base = mutation.baseRevision;
      const currentRev = current ? parseInt(current.revision, 10) : null;

      if (current === null || current.deleted) {
        // Both sides have a tombstone — acknowledge.
        const existingRev = currentRev ?? 0;
        const ack: AcknowledgedMutation = {
          mutationId: mutation.mutationId,
          noteId: mutation.noteId,
          revision: existingRev,
        };
        acknowledged.push(ack);
        outcome = { acknowledged: ack };
      } else if (currentRev === base) {
        const revRes = await client.query<{ nextval: string }>(
          'SELECT nextval($1)',
          ['revision_seq'],
        );
        const newRev = parseInt(revRes.rows[0].nextval, 10);

        // Tombstone: clear title and content, retain id and revision.
        await client.query(
          `UPDATE notes SET title = NULL, content = NULL, tags = '[]', keywords = '[]',
           is_pinned = FALSE, created_at = NULL, updated_at = NULL,
           deleted = TRUE, revision = $1, mutation_id = $2
           WHERE id = $3`,
          [newRev, mutation.mutationId, mutation.noteId],
        );

        const ack: AcknowledgedMutation = {
          mutationId: mutation.mutationId,
          noteId: mutation.noteId,
          revision: newRev,
        };
        acknowledged.push(ack);
        outcome = { acknowledged: ack };
      } else {
        // Stale delete.
        const serverRevision = currentRev!;
        const serverState = noteToPayload(current);
        const conflict: ConflictResult = {
          mutationId: mutation.mutationId,
          noteId: mutation.noteId,
          operation: 'delete',
          serverRevision,
          serverState,
        };
        conflicts.push(conflict);
        outcome = { conflict };
      }
    }

    // Record idempotency entry.
    await client.query(
      `INSERT INTO processed_mutations (mutation_id, payload_hash, outcome)
       VALUES ($1, $2, $3)
       ON CONFLICT (mutation_id) DO NOTHING`,
      [mutation.mutationId, payloadHash, JSON.stringify(outcome)],
    );
  }

  // Build complete snapshot.
  const snapRes = await client.query<DbNote>('SELECT * FROM notes ORDER BY revision ASC');
  const snapshot: SnapshotRow[] = snapRes.rows.map(noteToSnapshot);

  return { acknowledged, conflicts, snapshot };
}
