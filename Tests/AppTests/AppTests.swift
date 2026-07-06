@testable import App
import Testing
import VaporTesting

@Suite("GraphExplorer-Sync API")
struct AppTests {
    /// Boot a fresh app (in-memory SQLite) per test and guarantee shutdown.
    private func withApp(_ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func registerAndToken(
        _ app: Application,
        email: String = "vini@example.com",
        password: String = "password123"
    ) async throws -> String {
        var token = ""
        try await app.testing().test(.POST, "auth/register", beforeRequest: { req in
            try req.content.encode(Credentials(email: email, password: password))
        }, afterResponse: { res in
            #expect(res.status == .ok)
            token = try res.content.decode(TokenResponse.self).token
        })
        return token
    }

    @Test("healthz responds ok")
    func healthz() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "healthz") { res in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("register, me, wrong password, duplicate email")
    func authFlow() async throws {
        try await withApp { app in
            let token = try await registerAndToken(app)

            try await app.testing().test(.GET, "me", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res in
                #expect(res.status == .ok)
                let me = try res.content.decode(MeResponse.self)
                #expect(me.email == "vini@example.com")
            })

            try await app.testing().test(.POST, "auth/login", beforeRequest: { req in
                try req.content.encode(
                    Credentials(email: "vini@example.com", password: "wrong-password"))
            }, afterResponse: { res in
                #expect(res.status == .unauthorized)
            })

            try await app.testing().test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(
                    Credentials(email: "vini@example.com", password: "password123"))
            }, afterResponse: { res in
                #expect(res.status == .conflict)
            })
        }
    }

    @Test("project sync applies last-write-wins")
    func projectSyncLww() async throws {
        try await withApp { app in
            let token = try await registerAndToken(app)
            let bearer = BearerAuthorization(token: token)

            let v1 = ProjectDTO(
                id: "default", name: "MTG", endpoint: "http://localhost:3030/mtg/sparql",
                createdAt: 1_000, lastOpenedAt: 1_000, updatedAt: 2_000, deleted: false)
            try await app.testing().test(.PUT, "projects", beforeRequest: { req in
                req.headers.bearerAuthorization = bearer
                try req.content.encode([v1])
            }, afterResponse: { res in
                let result = try res.content.decode(SyncResult.self)
                #expect(result.applied == 1)
            })

            // Stale update (older updatedAt) is skipped…
            let stale = ProjectDTO(
                id: "default", name: "STALE", endpoint: "http://old",
                createdAt: 1_000, lastOpenedAt: 900, updatedAt: 1_500, deleted: false)
            try await app.testing().test(.PUT, "projects", beforeRequest: { req in
                req.headers.bearerAuthorization = bearer
                try req.content.encode([stale])
            }, afterResponse: { res in
                let result = try res.content.decode(SyncResult.self)
                #expect(result.skippedStale == 1)
            })

            // …a newer one wins.
            let v2 = ProjectDTO(
                id: "default", name: "MTG renamed",
                endpoint: "http://localhost:3030/mtg/sparql",
                createdAt: 1_000, lastOpenedAt: 3_000, updatedAt: 3_000, deleted: false)
            try await app.testing().test(.PUT, "projects", beforeRequest: { req in
                req.headers.bearerAuthorization = bearer
                try req.content.encode([v2])
            }, afterResponse: { res in
                let result = try res.content.decode(SyncResult.self)
                #expect(result.applied == 1)
            })

            try await app.testing().test(.GET, "projects", beforeRequest: { req in
                req.headers.bearerAuthorization = bearer
            }, afterResponse: { res in
                let projects = try res.content.decode([ProjectDTO].self)
                #expect(projects.count == 1)
                #expect(projects.first?.name == "MTG renamed")
            })

            // Incremental pull: nothing changed after updatedAt=3000.
            try await app.testing().test(.GET, "projects?since=3000", beforeRequest: { req in
                req.headers.bearerAuthorization = bearer
            }, afterResponse: { res in
                let projects = try res.content.decode([ProjectDTO].self)
                #expect(projects.isEmpty)
            })
        }
    }

    @Test("saved queries are isolated per user; anonymous is rejected")
    func queriesIsolation() async throws {
        try await withApp { app in
            let tokenA = try await registerAndToken(app, email: "a@example.com")
            let tokenB = try await registerAndToken(app, email: "b@example.com")

            let query = SavedQueryDTO(
                id: "starter-default-0", projectId: "default", name: "Peek",
                query: "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 50",
                folder: "Starter", updatedAt: 1_000, deleted: false)
            try await app.testing().test(.PUT, "queries", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: tokenA)
                try req.content.encode([query])
            }, afterResponse: { res in
                let result = try res.content.decode(SyncResult.self)
                #expect(result.applied == 1)
            })

            try await app.testing().test(.GET, "queries", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: tokenB)
            }, afterResponse: { res in
                let queries = try res.content.decode([SavedQueryDTO].self)
                #expect(queries.isEmpty)
            })

            try await app.testing().test(.GET, "queries") { res in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("shares are publicly readable by slug")
    func shares() async throws {
        try await withApp { app in
            let token = try await registerAndToken(app)
            var slug = ""
            try await app.testing().test(.POST, "shares", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(CreateShareRequest(
                    title: "Xyris decks",
                    query: "SELECT ?deck WHERE { ?deck ?p ?o } LIMIT 10",
                    endpoint: "http://localhost:3030/mtg/sparql"))
            }, afterResponse: { res in
                #expect(res.status == .ok)
                slug = try res.content.decode(ShareDTO.self).slug
                #expect(slug.count == 8)
            })

            // No auth header — still readable.
            try await app.testing().test(.GET, "shares/\(slug)") { res in
                #expect(res.status == .ok)
                let share = try res.content.decode(ShareDTO.self)
                #expect(share.title == "Xyris decks")
            }

            try await app.testing().test(.GET, "shares/doesnotex") { res in
                #expect(res.status == .notFound)
            }
        }
    }
}
