import supertest from 'supertest';
import { Pool } from 'pg';
import { createApp } from '../index';
import { getPool, closePool } from '../db';
import { randomUUID as uuidv4 } from 'crypto';

const TEST_TOKEN = 'test-token-abc123-' + Math.random().toString(36);
const DB_URL = process.env.DATABASE_URL ?? 'postgresql://postgres:postgres@localhost:5432/grepink_test';

let pool: Pool;
let app: ReturnType<typeof createApp>;

const MIGRATION_SQL = `
CREATE SEQUENCE IF NOT EXISTS revision_seq;
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,
  title TEXT,
  content TEXT,
  tags TEXT NOT NULL DEFAULT '[]',
  keywords TEXT NOT NULL DEFAULT '[]',
  is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  deleted BOOLEAN NOT NULL DEFAULT FALSE,
  revision BIGINT NOT NULL DEFAULT nextval('revision_seq'),
  mutation_id TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS processed_mutations (
  mutation_id TEXT PRIMARY KEY,
  payload_hash TEXT NOT NULL,
  outcome JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

beforeAll(async () => {
  process.env.DATABASE_URL = DB_URL;
  process.env.SYNC_TOKEN = TEST_TOKEN;
  pool = new Pool({ connectionString: DB_URL });
  await pool.query(MIGRATION_SQL);
  app = createApp();
});

beforeEach(async () => {
  await pool.query('TRUNCATE notes, processed_mutations RESTART IDENTITY');
});

afterAll(async () => {
  await pool.end();
  await closePool();
});

function auth(): Record<string, string> {
  return { Authorization: `Bearer ${TEST_TOKEN}` };
}

function makeNote(overrides: Record<string, unknown> = {}) {
  return {
    title: 'Test note',
    content: 'Some content',
    tags: [] as string[],
    keywords: [] as string[],
    isPinned: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

describe('GET /health', () => {
  it('returns 200 and ok=true when DB is reachable', async () => {
    const res = await supertest(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

describe('authentication', () => {
  it('returns 401 with no Authorization header', async () => {
    const res = await supertest(app).post('/v1/sync').send({ mutations: [] });
    expect(res.status).toBe(401);
  });

  it('returns 401 with wrong token', async () => {
    const res = await supertest(app)
      .post('/v1/sync')
      .set({ Authorization: 'Bearer wrong-token' })
      .send({ mutations: [] });
    expect(res.status).toBe(401);
  });

  it('returns 401 with malformed header (no Bearer prefix)', async () => {
    const res = await supertest(app)
      .post('/v1/sync')
      .set({ Authorization: TEST_TOKEN })
      .send({ mutations: [] });
    expect(res.status).toBe(401);
  });

  it('returns 200 with valid token', async () => {
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({ mutations: [] });
    expect(res.status).toBe(200);
  });

  it('GET /v1/status returns 200 with valid token', async () => {
    const res = await supertest(app).get('/v1/status').set(auth());
    expect(res.status).toBe(200);
    expect(res.body.ready).toBe(true);
  });

  it('GET /v1/status returns 401 without token', async () => {
    const res = await supertest(app).get('/v1/status');
    expect(res.status).toBe(401);
  });
});

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

describe('request validation', () => {
  it('returns 400 for malformed JSON', async () => {
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .set('Content-Type', 'application/json')
      .send('not-json{');
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid mutation fields', async () => {
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: 'not-a-uuid',
            noteId: uuidv4(),
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote(),
          },
        ],
      });
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid timestamp', async () => {
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId: uuidv4(),
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ createdAt: 'not-a-date' }),
          },
        ],
      });
    expect(res.status).toBe(400);
  });

  it('returns 400 for unknown operation', async () => {
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId: uuidv4(),
            operation: 'patch',
            baseRevision: null,
            payload: makeNote(),
          },
        ],
      });
    expect(res.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// Note creation
// ---------------------------------------------------------------------------

describe('note creation', () => {
  it('creates a note with baseRevision=null', async () => {
    const noteId = uuidv4();
    const mutationId = uuidv4();
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId,
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'Hello', content: 'World' }),
          },
        ],
      });

    expect(res.status).toBe(200);
    expect(res.body.acknowledged).toHaveLength(1);
    expect(res.body.acknowledged[0].noteId).toBe(noteId);
    expect(typeof res.body.acknowledged[0].revision).toBe('number');
    expect(res.body.conflicts).toHaveLength(0);
    expect(res.body.snapshot).toHaveLength(1);
    expect(res.body.snapshot[0].title).toBe('Hello');
  });

  it('snapshot contains new note on empty-mutation sync', async () => {
    const noteId = uuidv4();
    await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote(),
          },
        ],
      });

    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({ mutations: [] });

    expect(res.body.snapshot).toHaveLength(1);
    expect(res.body.snapshot[0].id).toBe(noteId);
  });
});

// ---------------------------------------------------------------------------
// Note update
// ---------------------------------------------------------------------------

describe('note update', () => {
  it('updates a note when baseRevision matches', async () => {
    const noteId = uuidv4();
    const create = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'Original' }),
          },
        ],
      });
    const revision = create.body.acknowledged[0].revision;

    const update = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: revision,
            payload: makeNote({ title: 'Updated' }),
          },
        ],
      });

    expect(update.body.acknowledged).toHaveLength(1);
    expect(update.body.conflicts).toHaveLength(0);
    expect(update.body.snapshot[0].title).toBe('Updated');
  });

  it('returns conflict when baseRevision is stale', async () => {
    const noteId = uuidv4();
    const create = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'V1' }),
          },
        ],
      });
    const rev1 = create.body.acknowledged[0].revision;

    // Another update bumps the revision.
    await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: rev1,
            payload: makeNote({ title: 'V2' }),
          },
        ],
      });

    // Stale update using the original rev1.
    const stale = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: rev1,
            payload: makeNote({ title: 'Stale edit' }),
          },
        ],
      });

    expect(stale.body.conflicts).toHaveLength(1);
    expect(stale.body.acknowledged).toHaveLength(0);
    expect(stale.body.conflicts[0].noteId).toBe(noteId);
  });
});

// ---------------------------------------------------------------------------
// Deletion and tombstones
// ---------------------------------------------------------------------------

describe('deletion', () => {
  it('creates a tombstone on delete', async () => {
    const noteId = uuidv4();
    const create = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote(),
          },
        ],
      });
    const rev = create.body.acknowledged[0].revision;

    const del = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'delete',
            baseRevision: rev,
          },
        ],
      });

    expect(del.body.acknowledged).toHaveLength(1);
    expect(del.body.snapshot[0].deleted).toBe(true);
    expect(del.body.snapshot[0].title).toBeNull();
    expect(del.body.snapshot[0].content).toBeNull();
  });

  it('acknowledges delete when server already has a tombstone', async () => {
    const noteId = uuidv4();
    const create = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote(),
          },
        ],
      });
    const rev = create.body.acknowledged[0].revision;

    await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'delete',
            baseRevision: rev,
          },
        ],
      });

    // Second delete of the same note — server already has a tombstone.
    const del2 = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'delete',
            baseRevision: rev,
          },
        ],
      });

    expect(del2.body.acknowledged).toHaveLength(1);
    expect(del2.body.conflicts).toHaveLength(0);
  });

  it('returns conflict for stale delete', async () => {
    const noteId = uuidv4();
    const create = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'V1' }),
          },
        ],
      });
    const rev1 = create.body.acknowledged[0].revision;

    // Update note (bumps revision).
    await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: rev1,
            payload: makeNote({ title: 'V2' }),
          },
        ],
      });

    // Stale delete using old revision.
    const stale = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'delete',
            baseRevision: rev1,
          },
        ],
      });

    expect(stale.body.conflicts).toHaveLength(1);
    expect(stale.body.conflicts[0].operation).toBe('delete');
    expect(stale.body.conflicts[0].serverState).not.toBeNull();
  });

  it('snapshot includes tombstones', async () => {
    const noteId = uuidv4();
    const create = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote(),
          },
        ],
      });
    const rev = create.body.acknowledged[0].revision;
    await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId,
            operation: 'delete',
            baseRevision: rev,
          },
        ],
      });

    const snap = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({ mutations: [] });
    expect(snap.body.snapshot[0].deleted).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Missing records never cause deletion
// ---------------------------------------------------------------------------

describe('missing records', () => {
  it('notes not in mutation list are not deleted', async () => {
    const noteA = uuidv4();
    const noteB = uuidv4();

    // Create two notes.
    await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId: noteA,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'A' }),
          },
          {
            mutationId: uuidv4(),
            noteId: noteB,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'B' }),
          },
        ],
      });

    // Sync only note B — A must still be in the snapshot.
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId: noteB,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'B updated' }),
          },
        ],
      });

    const ids = res.body.snapshot.map((s: { id: string }) => s.id);
    expect(ids).toContain(noteA);
    expect(ids).toContain(noteB);
  });
});

// ---------------------------------------------------------------------------
// Two devices creating different notes
// ---------------------------------------------------------------------------

describe('two-device convergence', () => {
  it('both notes survive when created independently', async () => {
    const noteX = uuidv4();
    const noteY = uuidv4();

    // Device 1 creates X.
    await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId: noteX,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'X' }),
          },
        ],
      });

    // Device 2 creates Y.
    await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId: noteY,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'Y' }),
          },
        ],
      });

    // Empty sync — both notes should be in snapshot.
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({ mutations: [] });

    const ids = res.body.snapshot.map((s: { id: string }) => s.id);
    expect(ids).toContain(noteX);
    expect(ids).toContain(noteY);
  });

  it('simultaneous sync of distinct notes both land', async () => {
    const noteA = uuidv4();
    const noteB = uuidv4();

    // Both devices send in the same request.
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId: noteA,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'A' }),
          },
          {
            mutationId: uuidv4(),
            noteId: noteB,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'B' }),
          },
        ],
      });

    expect(res.body.acknowledged).toHaveLength(2);
    expect(res.body.snapshot).toHaveLength(2);
  });
});

// ---------------------------------------------------------------------------
// Idempotency
// ---------------------------------------------------------------------------

describe('idempotency', () => {
  it('same mutation ID returns original result without duplicate change', async () => {
    const noteId = uuidv4();
    const mutationId = uuidv4();
    const payload = makeNote({ title: 'Idempotent' });

    const res1 = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId,
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload,
          },
        ],
      });
    const rev1 = res1.body.acknowledged[0].revision;

    // Retry with same mutation ID.
    const res2 = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId,
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload,
          },
        ],
      });
    const rev2 = res2.body.acknowledged[0].revision;

    // Same revision — no new row created.
    expect(rev2).toBe(rev1);
    expect(res2.body.snapshot).toHaveLength(1);
  });

  it('mutation ID reuse with different payload is rejected with 409', async () => {
    const noteId = uuidv4();
    const mutationId = uuidv4();

    await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId,
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'First' }),
          },
        ],
      });

    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({
        mutations: [
          {
            mutationId,
            noteId,
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ title: 'Different content entirely' }),
          },
        ],
      });

    expect(res.status).toBe(409);
  });
});

// ---------------------------------------------------------------------------
// Empty request
// ---------------------------------------------------------------------------

describe('empty requests', () => {
  it('empty database + empty mutations returns empty snapshot', async () => {
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .send({ mutations: [] });

    expect(res.status).toBe(200);
    expect(res.body.acknowledged).toHaveLength(0);
    expect(res.body.conflicts).toHaveLength(0);
    expect(res.body.snapshot).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// Oversized requests
// ---------------------------------------------------------------------------

describe('size limits', () => {
  it('returns 413 for body > 10MB', async () => {
    const bigContent = 'x'.repeat(11 * 1024 * 1024);
    const res = await supertest(app)
      .post('/v1/sync')
      .set(auth())
      .set('Content-Type', 'application/json')
      .send(JSON.stringify({
        mutations: [
          {
            mutationId: uuidv4(),
            noteId: uuidv4(),
            operation: 'upsert',
            baseRevision: null,
            payload: makeNote({ content: bigContent }),
          },
        ],
      }));
    expect([400, 413]).toContain(res.status);
  });
});
