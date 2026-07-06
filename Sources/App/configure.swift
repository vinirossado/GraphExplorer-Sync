import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) async throws {
    // The desktop clients call from file:// / app origins; shares may be read
    // from browsers later. Permissive CORS is fine for an API that only ever
    // returns the caller's own data (bearer-token scoped) or public shares.
    app.middleware.use(CORSMiddleware(configuration: .init(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin]
    )))

    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else if let databaseURL = Environment.get("DATABASE_URL") {
        // Azure-style single connection string, e.g.
        // postgres://user:pass@host:5432/dbname?sslmode=require
        try app.databases.use(.postgres(url: databaseURL), as: .psql)
    } else {
        app.databases.use(.postgres(configuration: SQLPostgresConfiguration(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init)
                ?? SQLPostgresConfiguration.ianaPortNumber,
            username: Environment.get("DATABASE_USERNAME") ?? "vapor",
            password: Environment.get("DATABASE_PASSWORD") ?? "vapor",
            database: Environment.get("DATABASE_NAME") ?? "graphexplorer",
            tls: .prefer(try .init(configuration: .clientDefault))
        )), as: .psql)
    }

    app.migrations.add(CreateUser())
    app.migrations.add(CreateUserToken())
    app.migrations.add(CreateProject())
    app.migrations.add(CreateSavedQueryRecord())
    app.migrations.add(CreateShare())
    try await app.autoMigrate()

    try routes(app)
}
