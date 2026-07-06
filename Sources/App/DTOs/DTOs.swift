import Vapor

// Wire formats mirror the desktop client's Dexie records (camelCase, epoch-ms
// timestamps). `deleted` is optional on input so plain upserts stay terse.

struct Credentials: Content {
    let email: String
    let password: String
}

struct TokenResponse: Content {
    let token: String
    let userId: String
    let email: String
}

struct MeResponse: Content {
    let userId: String
    let email: String
}

struct ProjectDTO: Content {
    let id: String
    let name: String
    let endpoint: String
    let createdAt: Int
    let lastOpenedAt: Int
    let updatedAt: Int
    let deleted: Bool?
}

struct SavedQueryDTO: Content {
    let id: String
    let projectId: String
    let name: String
    let query: String
    let folder: String?
    let updatedAt: Int
    let deleted: Bool?
}

/// Result of a batched last-write-wins upsert.
struct SyncResult: Content {
    let applied: Int
    let skippedStale: Int
}

struct CreateShareRequest: Content {
    let title: String?
    let query: String
    let endpoint: String
}

struct ShareDTO: Content {
    let slug: String
    let title: String?
    let query: String
    let endpoint: String
    let createdAt: Date?
}
