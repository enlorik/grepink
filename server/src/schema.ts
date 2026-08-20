import { z } from 'zod';

const MAX_MUTATIONS = 500;
const MAX_PAYLOAD_BYTES = 10 * 1024 * 1024; // 10 MB

export const NotePayloadSchema = z.object({
  title: z.string().max(10_000),
  content: z.string().max(500_000),
  tags: z.array(z.string().max(200)).max(100),
  keywords: z.array(z.string().max(200)).max(200),
  isPinned: z.boolean(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});

export type NotePayload = z.infer<typeof NotePayloadSchema>;

export const MutationSchema = z.discriminatedUnion('operation', [
  z.object({
    mutationId: z.string().uuid(),
    noteId: z.string().uuid(),
    operation: z.literal('upsert'),
    baseRevision: z.number().int().nullable(),
    payload: NotePayloadSchema,
  }),
  z.object({
    mutationId: z.string().uuid(),
    noteId: z.string().uuid(),
    operation: z.literal('delete'),
    baseRevision: z.number().int(),
    payload: z.null().optional(),
  }),
]);

export type Mutation = z.infer<typeof MutationSchema>;

export const SyncRequestSchema = z.object({
  mutations: z.array(MutationSchema).max(MAX_MUTATIONS),
});

export type SyncRequest = z.infer<typeof SyncRequestSchema>;

export { MAX_PAYLOAD_BYTES };
