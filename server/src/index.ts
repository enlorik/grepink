import express, { Request, Response, NextFunction } from 'express';
import { requireAuth } from './auth';
import { checkDbHealth, withTransaction } from './db';
import { SyncRequestSchema, MAX_PAYLOAD_BYTES } from './schema';
import { processSyncRequest } from './sync';

const PROTOCOL_VERSION = '1';

export function createApp(): express.Application {
  const app = express();

  app.use((req: Request, res: Response, next: NextFunction) => {
    const contentLength = parseInt(req.headers['content-length'] ?? '0', 10);
    if (contentLength > MAX_PAYLOAD_BYTES) {
      res.status(413).json({ error: 'Request body too large' });
      return;
    }
    next();
  });

  app.use(
    express.json({
      limit: MAX_PAYLOAD_BYTES,
      strict: true,
    }),
  );

  // Unauthenticated health check.
  app.get('/health', async (_req: Request, res: Response) => {
    const dbOk = await checkDbHealth();
    res.status(dbOk ? 200 : 503).json({ ok: dbOk });
  });

  // Authenticated routes.
  app.use('/v1', requireAuth);

  app.get('/v1/status', (_req: Request, res: Response) => {
    res.json({ ready: true, protocol: PROTOCOL_VERSION });
  });

  app.post('/v1/sync', async (req: Request, res: Response) => {
    const parsed = SyncRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: 'Invalid request', details: parsed.error.flatten() });
      return;
    }

    try {
      const result = await withTransaction((client) =>
        processSyncRequest(client, parsed.data.mutations),
      );
      res.json(result);
    } catch (err: unknown) {
      const status = (err as { status?: number }).status;
      if (status === 409) {
        res.status(409).json({ error: 'Mutation ID conflict' });
        return;
      }
      res.status(500).json({ error: 'Sync failed' });
    }
  });

  // Handle unknown routes.
  app.use((_req: Request, res: Response) => {
    res.status(404).json({ error: 'Not found' });
  });

  return app;
}

if (require.main === module) {
  const port = parseInt(process.env.PORT ?? '3000', 10);
  const app = createApp();
  app.listen(port, () => {
    console.log(`Grepink sync server listening on port ${port}`);
  });
}
