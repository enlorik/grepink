# Railway sync setup

This guide explains how to deploy the Grepink sync server on Railway so you can synchronise notes between Android, iOS, and Windows.

The sync server is a small TypeScript/Express API backed by a Railway-managed PostgreSQL database. It uses a single shared token for authentication. There are no user accounts.

---

## Prerequisites

- A [Railway](https://railway.app) account
- The `railway` CLI or access to the Railway dashboard
- `openssl` available locally (to generate a token)

---

## Step 1 — Create a Railway project

1. Go to [railway.app](https://railway.app) and create a new project.
2. Name the project (e.g. `grepink-sync`).

---

## Step 2 — Add a PostgreSQL database

Inside your project:

1. Click **+ New** → **Database** → **Add PostgreSQL**.
2. Railway provisions a managed PostgreSQL instance. Note the private `DATABASE_URL` reference variable shown in the plugin settings.

---

## Step 3 — Deploy the server

The server lives in the `server/` subdirectory of this repository.

1. Click **+ New** → **GitHub Repo**, then select the `grepink` repository.
2. In the service settings, set the **Root Directory** to `server`.
3. Railway will run `npm ci` and then the start command. Ensure the **Start Command** is set to:
   ```
   npm start
   ```
4. Set the **Pre-deploy Command** (under Service → Settings → Deploy) to run the database migration before each deploy:
   ```
   npm run migrate
   ```

---

## Step 4 — Set environment variables

In the Railway service settings, add the following environment variables.

### `DATABASE_URL`

Use Railway's private reference to the PostgreSQL plugin:

```
${{Postgres.DATABASE_URL}}
```

This connects the API service to the database over Railway's private network without exposing credentials publicly.

### `SYNC_TOKEN`

Generate a strong token locally:

```sh
openssl rand -hex 32
```

Copy the output and paste it as the value. Keep this token secret — it is the only authentication credential.

### `PORT`

Railway sets `PORT` automatically. You do not need to add this manually.

---

## Step 5 — Generate a public HTTPS domain

1. In the Railway service, go to **Settings** → **Networking**.
2. Click **Generate Domain** to create a public HTTPS URL (e.g. `https://grepink-sync-production.up.railway.app`).
3. Copy this URL — you will enter it in the Grepink app settings.

---

## Step 6 — Configure the health-check path

In the service settings, set the health-check path to:

```
/health
```

Railway uses this to confirm the service is running before routing traffic.

---

## Step 7 — Enable database backups

Before you rely on sync as part of your workflow:

1. Go to the PostgreSQL plugin settings.
2. Enable **Automated Backups**.
3. Verify a backup completes successfully.

---

## Step 8 — Configure the app

On each device:

1. Open Grepink → Settings → **RAILWAY SYNC**.
2. Enter the Railway API URL (the HTTPS domain from Step 5).
3. Paste the sync token generated in Step 4.
4. Tap **Test connection** to verify the server is reachable.
5. If successful, tap **Sync now** to start the first synchronisation.

---

## Token rotation

If you need to rotate the sync token:

1. Generate a new token: `openssl rand -hex 32`.
2. Update `SYNC_TOKEN` in the Railway service environment variables.
3. Redeploy the service (or Railway will restart automatically on env changes).
4. On each device, go to Settings → Railway Sync, enter the new token, and tap **Test connection**.

---

## Variable reference

| Variable       | Where it is set         | Description                                      |
|----------------|-------------------------|--------------------------------------------------|
| `DATABASE_URL` | Railway (private ref)   | PostgreSQL connection string                     |
| `SYNC_TOKEN`   | Railway (secret)        | Shared authentication token for all devices     |
| `PORT`         | Railway (automatic)     | HTTP port; Railway sets this automatically        |

---

## Notes and limitations

- **Single owner**: the server is designed for one person across multiple devices. Simultaneous writes from two devices that have not synced their outboxes will produce conflicts, which the app resolves by preserving both note contents.
- **Not end-to-end encrypted**: notes travel over HTTPS but are stored in plaintext in the Railway PostgreSQL database. You control the database; Railway staff can access it subject to their terms.
- **Tombstones**: deleted notes remain as tombstone rows in the database indefinitely in this version. This prevents accidental resurrection during initial sync.
- **No background sync**: sync is triggered on app startup, resume, and after local mutations. There is no continuous OS-level background sync.
