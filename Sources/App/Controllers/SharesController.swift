import Fluent
import Vapor

/// Share a query by link: creating requires auth, reading is public.
struct SharesController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let protected = routes
            .grouped(TokenAuthenticator(), User.guardMiddleware())
        protected.post("shares", use: create)

        routes.get("shares", ":slug", use: read)
    }

    /// Maximum SPARQL text length accepted in a share.
    static let maxQueryLength = 20_000

    /// Publishes a query as a public link.
    ///
    /// - Returns: ``ShareDTO`` including the generated 8-character slug.
    /// - Throws: `400` for an empty query, `413` when query/title exceed the
    ///   size caps.
    @Sendable
    func create(req: Request) async throws -> ShareDTO {
        let userID = try req.auth.require(User.self).requireID()
        let body = try req.content.decode(CreateShareRequest.self)
        guard !body.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "Share query must not be empty.")
        }
        guard body.query.count <= Self.maxQueryLength else {
            throw Abort(.payloadTooLarge,
                        reason: "Query exceeds \(Self.maxQueryLength) characters.")
        }
        guard (body.title ?? "").count <= 200 else {
            throw Abort(.payloadTooLarge, reason: "Title exceeds 200 characters.")
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

    /// Reads a share. Browsers (Accept: text/html) get a small standalone page
    /// with the query ready to copy; API clients get JSON.
    @Sendable
    func read(req: Request) async throws -> Response {
        guard let slug = req.parameters.get("slug"),
              let share = try await Share.find(slug, on: req.db)
        else {
            throw Abort(.notFound)
        }
        let dto = ShareDTO(
            slug: share.id ?? "",
            title: share.title,
            query: share.query,
            endpoint: share.endpoint,
            createdAt: share.createdAt
        )
        if req.headers.accept.contains(where: { $0.mediaType == .html }) {
            let response = Response(status: .ok)
            response.headers.contentType = .html
            response.body = .init(string: Self.htmlPage(for: dto))
            return response
        }
        let response = Response(status: .ok)
        try response.content.encode(dto)
        return response
    }

    /// Minimal, dependency-free share page. All user-supplied fields are
    /// HTML-escaped — queries and titles are untrusted input.
    static func htmlPage(for share: ShareDTO) -> String {
        let title = escape(share.title ?? "Shared SPARQL query")
        let query = escape(share.query)
        let endpoint = escape(share.endpoint)
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title) · Graph Explorer</title>
        <style>
          body{margin:0;background:#0a0a0a;color:#e5e7eb;font:15px/1.6 ui-sans-serif,system-ui}
          main{max-width:720px;margin:0 auto;padding:48px 24px}
          h1{font-size:20px;color:#f5f5f5} .muted{color:#737373;font-size:13px}
          pre{background:#171717;border:1px solid #262626;border-radius:10px;
              padding:16px;overflow-x:auto;font:13px/1.5 ui-monospace,monospace;color:#7dd3fc}
          code{color:#a3a3a3} a{color:#38bdf8}
          .row{display:flex;gap:8px;align-items:center;margin:14px 0}
          button{background:#0ea5e9;border:0;border-radius:8px;color:#0a0a0a;
                 font-weight:600;padding:8px 14px;cursor:pointer}
        </style></head><body><main>
        <h1>\(title)</h1>
        <p class="muted">Shared from <strong>Graph Explorer</strong> — a
        local-first SPARQL/RDF exploration IDE.</p>
        <p class="muted">Endpoint: <code>\(endpoint)</code></p>
        <pre id="q">\(query)</pre>
        <div class="row">
          <button onclick="navigator.clipboard.writeText(document.getElementById('q').innerText)">
            Copy query</button>
          <span class="muted">Paste it into Graph Explorer pointed at the endpoint above.</span>
        </div>
        </main></body></html>
        """
    }

    /// Escapes the five HTML-significant characters.
    static func escape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let slugAlphabet =
        Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")

    static func randomSlug(length: Int = 8) -> String {
        String((0..<length).compactMap { _ in slugAlphabet.randomElement() })
    }
}
