import Fluent
import Vapor

/// Last-write-wins sync for projects and saved queries.
///
/// Contract with the desktop client:
/// - Records are keyed by CLIENT-generated string ids.
/// - `updatedAt` (epoch ms, written by the client) decides conflicts: an
///   incoming record only overwrites a stored one when its `updatedAt` is
///   greater or equal.
/// - Deletions travel as tombstones (`deleted: true`) so every device
///   converges; clients purge local rows on seeing a tombstone.
/// - `GET ...?since=<ms>` returns records changed after that mark, tombstones
///   included, for incremental pulls.
struct SyncController: RouteCollection {
    /// Upper bound per batched `PUT` — larger syncs must page.
    static let maxBatchSize = 500

    func boot(routes: any RoutesBuilder) throws {
        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.get("projects", use: listProjects)
        protected.put("projects", use: upsertProjects)
        protected.get("queries", use: listQueries)
        protected.put("queries", use: upsertQueries)
    }

    // ── Projects ────────────────────────────────────────────────────────────

    @Sendable
    func listProjects(req: Request) async throws -> [ProjectDTO] {
        let userID = try req.auth.require(User.self).requireID()
        let since = (try? req.query.get(Int.self, at: "since")) ?? 0
        let rows = try await Project.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$updatedAtMs > since)
            .all()
        return rows.map { p in
            ProjectDTO(
                id: p.id ?? "",
                name: p.name,
                endpoint: p.endpoint,
                createdAt: p.createdAtMs,
                lastOpenedAt: p.lastOpenedAtMs,
                updatedAt: p.updatedAtMs,
                deleted: p.deleted
            )
        }
    }

    /// Batched last-write-wins upsert of projects.
    ///
    /// - Returns: ``SyncResult`` — how many records were applied vs skipped
    ///   because the stored copy was newer.
    /// - Throws: `413` when the batch exceeds ``maxBatchSize``.
    @Sendable
    func upsertProjects(req: Request) async throws -> SyncResult {
        let userID = try req.auth.require(User.self).requireID()
        let incoming = try req.content.decode([ProjectDTO].self)
        guard incoming.count <= Self.maxBatchSize else {
            throw Abort(.payloadTooLarge,
                        reason: "At most \(Self.maxBatchSize) records per request.")
        }
        var applied = 0
        var skipped = 0
        for dto in incoming {
            guard !dto.id.isEmpty else { continue }
            let existing = try await Project.query(on: req.db)
                .filter(\.$user.$id == userID)
                .filter(\.$id == dto.id)
                .first()
            if let existing {
                guard dto.updatedAt >= existing.updatedAtMs else {
                    skipped += 1
                    continue
                }
                existing.name = dto.name
                existing.endpoint = dto.endpoint
                existing.createdAtMs = dto.createdAt
                existing.lastOpenedAtMs = dto.lastOpenedAt
                existing.updatedAtMs = dto.updatedAt
                existing.deleted = dto.deleted ?? false
                try await existing.save(on: req.db)
            } else {
                let project = Project()
                project.id = dto.id
                project.$user.id = userID
                project.name = dto.name
                project.endpoint = dto.endpoint
                project.createdAtMs = dto.createdAt
                project.lastOpenedAtMs = dto.lastOpenedAt
                project.updatedAtMs = dto.updatedAt
                project.deleted = dto.deleted ?? false
                try await project.create(on: req.db)
            }
            applied += 1
        }
        return SyncResult(applied: applied, skippedStale: skipped)
    }

    // ── Saved queries ───────────────────────────────────────────────────────

    @Sendable
    func listQueries(req: Request) async throws -> [SavedQueryDTO] {
        let userID = try req.auth.require(User.self).requireID()
        let since = (try? req.query.get(Int.self, at: "since")) ?? 0
        var query = SavedQueryRecord.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$updatedAtMs > since)
        if let projectId = try? req.query.get(String.self, at: "projectId") {
            query = query.filter(\SavedQueryRecord.$projectId == projectId)
        }
        let rows = try await query.all()
        return rows.map { q in
            SavedQueryDTO(
                id: q.id ?? "",
                projectId: q.projectId,
                name: q.name,
                query: q.query,
                folder: q.folder,
                updatedAt: q.updatedAtMs,
                deleted: q.deleted
            )
        }
    }

    /// Batched last-write-wins upsert of saved queries.
    ///
    /// - Returns: ``SyncResult`` — applied vs skipped-as-stale counts.
    /// - Throws: `413` when the batch exceeds ``maxBatchSize``.
    @Sendable
    func upsertQueries(req: Request) async throws -> SyncResult {
        let userID = try req.auth.require(User.self).requireID()
        let incoming = try req.content.decode([SavedQueryDTO].self)
        guard incoming.count <= Self.maxBatchSize else {
            throw Abort(.payloadTooLarge,
                        reason: "At most \(Self.maxBatchSize) records per request.")
        }
        var applied = 0
        var skipped = 0
        for dto in incoming {
            guard !dto.id.isEmpty else { continue }
            let existing = try await SavedQueryRecord.query(on: req.db)
                .filter(\.$user.$id == userID)
                .filter(\.$id == dto.id)
                .first()
            if let existing {
                guard dto.updatedAt >= existing.updatedAtMs else {
                    skipped += 1
                    continue
                }
                existing.projectId = dto.projectId
                existing.name = dto.name
                existing.query = dto.query
                existing.folder = dto.folder
                existing.updatedAtMs = dto.updatedAt
                existing.deleted = dto.deleted ?? false
                try await existing.save(on: req.db)
            } else {
                let record = SavedQueryRecord()
                record.id = dto.id
                record.$user.id = userID
                record.projectId = dto.projectId
                record.name = dto.name
                record.query = dto.query
                record.folder = dto.folder
                record.updatedAtMs = dto.updatedAt
                record.deleted = dto.deleted ?? false
                try await record.create(on: req.db)
            }
            applied += 1
        }
        return SyncResult(applied: applied, skippedStale: skipped)
    }
}
