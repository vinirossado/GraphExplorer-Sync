import Vapor

/// Registers every route collection.
///
/// `POST /auth/*` gets its own, much stricter per-IP budget on top of the
/// global one so password guessing burns out quickly.
func routes(_ app: Application) throws {
    app.get("healthz") { _ in "ok" }

    let authLimit = Environment.get("AUTH_RATE_LIMIT").flatMap(Int.init) ?? 10
    let authRateLimit = RateLimitMiddleware(
        limiter: RateLimiter(maxRequests: authLimit, windowSeconds: 60)
    )

    try app.register(collection: AuthController(rateLimit: authRateLimit))
    try app.register(collection: SyncController())
    try app.register(collection: SharesController())
}
