# GraphExplorer-Sync

Optional cloud backend for [Graph Explorer](https://github.com/vinirossado/GraphExplorer)
— the local-first SPARQL/RDF exploration IDE.

The desktop app works **fully offline with no account**. This API adds, for
users who opt in:

- **Sync** — projects and saved queries across machines (last-write-wins).
- **Sharing** — publish a query + endpoint as a public link (`/shares/:slug`).

It deliberately knows nothing about RDF: clients talk SPARQL directly to their
endpoints; this service only stores app metadata.

## Stack

| | |
|---|---|
| Language | Swift 6.3 |
| Framework | Vapor 4 |
| ORM | Fluent + PostgreSQL (SQLite in-memory for tests) |
| Auth | Opaque bearer tokens (revocable), Bcrypt password hashing |
| Hosting target | Azure Container Apps (Docker, scale-to-zero) |

## API

```
GET    /healthz                       liveness
POST   /auth/register  {email, password}         → {token, userId, email}
POST   /auth/login     {email, password}         → {token, userId, email}
DELETE /auth/logout    (Bearer)                  revokes this device's token
GET    /me             (Bearer)                  → {userId, email}

GET    /projects?since=<ms>           (Bearer)   changed projects, tombstones included
PUT    /projects       [ProjectDTO]   (Bearer)   batched LWW upsert
GET    /queries?since=<ms>&projectId= (Bearer)   changed saved queries
PUT    /queries        [SavedQueryDTO](Bearer)   batched LWW upsert

POST   /shares         {title?, query, endpoint} (Bearer) → {slug, …}
GET    /shares/:slug                  (public)   read a shared query
```

**Sync contract:** ids are client-generated strings; `updatedAt` (epoch ms from
the client) decides conflicts; deletions travel as `deleted: true` tombstones.

## Run locally

```bash
# API + Postgres
docker compose up

# or natively (needs a local Postgres):
swift run App serve
```

Tests (in-memory SQLite, no services needed):

```bash
swift test
```

## Deploy to Azure (Bicep — piggybacks on TravelAPI's infrastructure)

`infrastructure/main.bicep` deploys into the **existing** TravelAPI resource
group: a new container Web App on the same App Service Plan, a new
`graphexplorer` database on the same PostgreSQL flexible server, and the
connection string as a Key Vault secret resolved through the site's managed
identity. Incremental cost ≈ zero; TLS comes from App Service (`httpsOnly`).

```bash
# First deployment (writes the connection-string secret):
az deployment group create \
  --resource-group <travelapi-rg> \
  --template-file infrastructure/main.bicep \
  --parameters pgSqlPassword=<pg-admin-password>

# Redeploys (secret preserved):
az deployment group create \
  --resource-group <travelapi-rg> \
  --template-file infrastructure/main.bicep \
  --parameters dockerImage=ghcr.io/vinirossado/graphexplorer-sync:<sha>
```

CI publishes the image to GHCR on every `main` push; set the repo variable
`AZURE_DEPLOY_ENABLED=true` plus the `AZURE_CREDENTIALS` /
`AZURE_RESOURCE_GROUP` secrets to enable continuous deploys.

## Security model

- **Passwords**: Bcrypt (salted, adaptive) — never stored or logged raw.
- **Tokens**: 256-bit CSPRNG values; the database stores only their SHA-256
  digest, so a leaked database yields no usable sessions.
- **Transport**: HTTPS enforced by App Service; Postgres over TLS
  (`sslmode=require`).
- **Endpoint credentials never reach the server**: the desktop client strips
  `user:pass@` from endpoint URLs before syncing.
- Per-IP rate limits (global + strict on `/auth`), body/batch/length caps.

## Roadmap

- [ ] Client integration in Graph Explorer (Settings → Account, background sync)
- [ ] Sign in with Apple / GitHub OAuth (replace or complement email+password)
- [ ] Share deep-links (`graphexplorer://s/:slug`) + read-only web viewer
- [ ] Rate limiting & request size caps before public exposure
