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

## Deploy to Azure (once)

```bash
az group create -n graphexplorer -l westeurope
az acr create -n <acrname> -g graphexplorer --sku Basic
az postgres flexible-server create -g graphexplorer -n <dbname> \
  --sku-name Standard_B1ms --tier Burstable --version 17
az containerapp env create -n graphexplorer-env -g graphexplorer
az containerapp create -n graphexplorer-sync -g graphexplorer \
  --environment graphexplorer-env \
  --image <acrname>.azurecr.io/graphexplorer-sync:latest \
  --target-port 8080 --ingress external \
  --min-replicas 0 --max-replicas 2 \
  --secrets database-url="postgres://…sslmode=require" \
  --env-vars DATABASE_URL=secretref:database-url
```

Then enable the deploy steps in `.github/workflows/ci.yml`.

## Roadmap

- [ ] Client integration in Graph Explorer (Settings → Account, background sync)
- [ ] Sign in with Apple / GitHub OAuth (replace or complement email+password)
- [ ] Share deep-links (`graphexplorer://s/:slug`) + read-only web viewer
- [ ] Rate limiting & request size caps before public exposure
