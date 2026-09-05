import { Request, Response, NextFunction } from 'express';
import { timingSafeEqual, createHash } from 'crypto';

function getExpectedToken(): Buffer {
  const raw = process.env.SYNC_TOKEN;
  if (!raw) throw new Error('SYNC_TOKEN environment variable is required');
  return Buffer.from(raw, 'utf8');
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers['authorization'] ?? '';
  const match = /^Bearer (.+)$/.exec(header);
  if (!match) {
    res.status(401).json({ error: 'Missing or malformed Authorization header' });
    return;
  }

  let expected: Buffer;
  try {
    expected = getExpectedToken();
  } catch {
    res.status(500).json({ error: 'Server configuration error' });
    return;
  }

  const provided = Buffer.from(match[1], 'utf8');

  // Pad to equal length before constant-time compare to avoid length leaks.
  const maxLen = Math.max(provided.length, expected.length);
  const paddedProvided = Buffer.alloc(maxLen);
  const paddedExpected = Buffer.alloc(maxLen);
  provided.copy(paddedProvided);
  expected.copy(paddedExpected);

  if (
    provided.length !== expected.length ||
    !timingSafeEqual(paddedProvided, paddedExpected)
  ) {
    res.status(401).json({ error: 'Invalid token' });
    return;
  }

  next();
}

export function hashPayload(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}
