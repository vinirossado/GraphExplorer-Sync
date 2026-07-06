import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(User.schema)
            .id()
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "email")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema).delete()
    }
}

struct CreateUserToken: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(UserToken.schema)
            .id()
            .field("value", .string, .required)
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .unique(on: "value")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(UserToken.schema).delete()
    }
}

struct CreateProject: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Project.schema)
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("endpoint", .string, .required)
            .field("created_at_ms", .int64, .required)
            .field("last_opened_at_ms", .int64, .required)
            .field("updated_at_ms", .int64, .required)
            .field("deleted", .bool, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Project.schema).delete()
    }
}

struct CreateSavedQueryRecord: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(SavedQueryRecord.schema)
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("project_id", .string, .required)
            .field("name", .string, .required)
            .field("query", .string, .required)
            .field("folder", .string)
            .field("updated_at_ms", .int64, .required)
            .field("deleted", .bool, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(SavedQueryRecord.schema).delete()
    }
}

struct CreateShare: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Share.schema)
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("title", .string)
            .field("query", .string, .required)
            .field("endpoint", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Share.schema).delete()
    }
}
