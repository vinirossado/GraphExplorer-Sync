import Vapor

// Wire formats mirror the desktop client's Dexie records: camelCase keys and
// epoch-millisecond timestamps, exactly as `Date.now()` produces them in the
// Electron app. `deleted` is optional on input so plain upserts stay terse.

/// Email + password pair accepted by `POST /auth/register` and `/auth/login`.
struct Credentials: Content {
    /// Case-insensitive; stored lowercased.
    let email: String
    /// 8–72 characters (Bcrypt's effective input limit).
    let password: String
}

/// Successful authentication result.
///
/// Store `token` client-side and send it as `Authorization: Bearer <token>`.
/// Tokens are opaque and revocable — `DELETE /auth/logout` kills this one.
struct TokenResponse: Content {
    let token: String
    let userId: String
    let email: String
}

/// Identity of the authenticated account (`GET /me`).
struct MeResponse: Content {
    let userId: String
    let email: String
}

/// Sync representation of a Graph Explorer project.
///
/// - `id` is the CLIENT-generated identifier (including `"default"` for
///   migrated data) — the server never invents ids.
/// - `updatedAt` (epoch ms) is the last-write-wins conflict key.
/// - `deleted: true` is a tombstone: the project was removed on some device
///   and every other device should drop it too.
struct ProjectDTO: Content {
    let id: String
    let name: String
    let endpoint: String
    let createdAt: Int
    let lastOpenedAt: Int
    let updatedAt: Int
    let deleted: Bool?
}

/// Sync representation of a saved query. Same id/LWW/tombstone rules as
/// ``ProjectDTO``; `projectId` is treated as an opaque string.
struct SavedQueryDTO: Content {
    let id: String
    let projectId: String
    let name: String
    let query: String
    let folder: String?
    let updatedAt: Int
    let deleted: Bool?
}

/// Outcome of a batched last-write-wins upsert.
struct SyncResult: Content {
    /// Records created or overwritten.
    let applied: Int
    /// Records ignored because the stored copy had a newer `updatedAt`.
    let skippedStale: Int
}

/// Body of `POST /shares`.
struct CreateShareRequest: Content {
    /// Optional display title (≤ 200 characters).
    let title: String?
    /// The SPARQL text to publish (≤ 20 000 characters).
    let query: String
    /// The endpoint the query targets, so a reader can run it immediately.
    let endpoint: String
}

/// A published share, addressed publicly by ``slug``.
struct ShareDTO: Content {
    let slug: String
    let title: String?
    let query: String
    let endpoint: String
    let createdAt: Date?
}
