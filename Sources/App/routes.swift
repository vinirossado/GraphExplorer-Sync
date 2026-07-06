import Vapor

func routes(_ app: Application) throws {
    app.get("healthz") { _ in "ok" }

    try app.register(collection: AuthController())
    try app.register(collection: SyncController())
    try app.register(collection: SharesController())
}
