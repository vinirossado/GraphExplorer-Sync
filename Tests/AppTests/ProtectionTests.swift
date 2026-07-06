@testable import App
import Foundation
import Testing
import VaporTesting

@Suite("Protections")
struct ProtectionTests {
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

    // ── RateLimiter unit behaviour ──────────────────────────────────────────

    @Test("limiter allows up to max then denies within the window")
    func limiterWindow() async {
        let limiter = RateLimiter(maxRequests: 3, windowSeconds: 60)
        let t0 = Date(timeIntervalSince1970: 1_000)
        #expect(await limiter.allow("ip", now: t0))
        #expect(await limiter.allow("ip", now: t0.addingTimeInterval(1)))
        #expect(await limiter.allow("ip", now: t0.addingTimeInterval(2)))
        #expect(await limiter.allow("ip", now: t0.addingTimeInterval(3)) == false)
        // A different client is unaffected.
        #expect(await limiter.allow("other-ip", now: t0.addingTimeInterval(3)))
        // A new window opens after expiry.
        #expect(await limiter.allow("ip", now: t0.addingTimeInterval(61)))
    }

    @Test("client key prefers X-Forwarded-For's first hop")
    func forwardedFor() async throws {
        try await withApp { app in
            let req = Request(application: app, on: app.eventLoopGroup.next())
            req.headers.replaceOrAdd(name: .xForwardedFor, value: "203.0.113.7, 10.0.0.1")
            #expect(RateLimitMiddleware.clientKey(for: req) == "203.0.113.7")
        }
    }

    // ── HTTP-level enforcement ──────────────────────────────────────────────

    @Test("auth endpoints answer 429 past the strict budget")
    func authRateLimit() async throws {
        try await withApp { app in
            // AUTH_RATE_LIMIT defaults to 10/min; the 11th attempt must be cut.
            var statuses: [HTTPStatus] = []
            for _ in 0..<11 {
                try await app.testing().test(.POST, "auth/login", beforeRequest: { req in
                    try req.content.encode(
                        Credentials(email: "nobody@example.com", password: "wrong-password"))
                }, afterResponse: { res in
                    statuses.append(res.status)
                })
            }
            #expect(statuses.dropLast().allSatisfy { $0 == .unauthorized })
            #expect(statuses.last == .tooManyRequests)
        }
    }

    @Test("oversized sync batches are rejected with 413")
    func batchCap() async throws {
        try await withApp { app in
            var token = ""
            try await app.testing().test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(
                    Credentials(email: "cap@example.com", password: "password123"))
            }, afterResponse: { res in
                token = try res.content.decode(TokenResponse.self).token
            })

            let tooMany = (0...SyncController.maxBatchSize).map { i in
                ProjectDTO(
                    id: "p\(i)", name: "P\(i)", endpoint: "http://x",
                    createdAt: 1, lastOpenedAt: 1, updatedAt: 1, deleted: false)
            }
            try await app.testing().test(.PUT, "projects", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(tooMany)
            }, afterResponse: { res in
                #expect(res.status == .payloadTooLarge)
            })
        }
    }

    @Test("bearer tokens are stored only as SHA-256 digests")
    func tokenAtRestHashing() async throws {
        try await withApp { app in
            var plaintext = ""
            try await app.testing().test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(
                    Credentials(email: "hash@example.com", password: "password123"))
            }, afterResponse: { res in
                plaintext = try res.content.decode(TokenResponse.self).token
            })

            let stored = try await UserToken.query(on: app.db).all()
            #expect(stored.count == 1)
            #expect(stored.first?.value != plaintext) // never the raw token
            #expect(stored.first?.value == UserToken.digest(of: plaintext))

            // The plaintext still authenticates (digest lookup).
            try await app.testing().test(.GET, "me", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: plaintext)
            }, afterResponse: { res in
                #expect(res.status == .ok)
            })

            // …and a tampered token does not.
            try await app.testing().test(.GET, "me", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: "\(plaintext)x")
            }, afterResponse: { res in
                #expect(res.status == .unauthorized)
            })
        }
    }

    @Test("passwords beyond bcrypt's 72-byte limit are rejected")
    func passwordCap() async throws {
        try await withApp { app in
            try await app.testing().test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(Credentials(
                    email: "long@example.com",
                    password: String(repeating: "x", count: 73)))
            }, afterResponse: { res in
                #expect(res.status == .badRequest)
            })
        }
    }
}
