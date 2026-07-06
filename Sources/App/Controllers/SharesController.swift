import Fluent
import Vapor

/// Share a query by link: creating requires auth, reading is public.
struct SharesController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.post("shares", use: create)

        routes.get("shares", ":slug", use: read)
    }

    @Sendable
    func create(req: Request) async throws -> ShareDTO {
        let userID = try req.auth.require(User.self).requireID()
        let body = try req.content.decode(CreateShareRequest.self)
        guard !body.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "Share query must not be empty.")
        }

        // Slug collisions are astronomically unlikely at 62^8, but retry anyway.
        for _ in 0..<3 {
            let share = Share()
            share.id = Self.randomSlug()
            share.$user.id = userID
            share.title = body.title
            share.query = body.query
            share.endpoint = body.endpoint
            do {
                try await share.create(on: req.db)
                return ShareDTO(
                    slug: share.id ?? "",
                    title: share.title,
                    query: share.query,
                    endpoint: share.endpoint,
                    createdAt: share.createdAt
                )
            } catch {
                continue // collision — roll a new slug
            }
        }
        throw Abort(.internalServerError, reason: "Could not allocate a share slug.")
    }

    @Sendable
    func read(req: Request) async throws -> ShareDTO {
        guard let slug = req.parameters.get("slug"),
              let share = try await Share.find(slug, on: req.db)
        else {
            throw Abort(.notFound)
        }
        return ShareDTO(
            slug: share.id ?? "",
            title: share.title,
            query: share.query,
            endpoint: share.endpoint,
            createdAt: share.createdAt
        )
    }

    private static let slugAlphabet =
        Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")

    static func randomSlug(length: Int = 8) -> String {
        String((0..<length).compactMap { _ in slugAlphabet.randomElement() })
    }
}
