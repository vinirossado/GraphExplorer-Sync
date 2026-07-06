import Fluent
import Vapor

/// Mirror of a saved query.
///
/// Same identity rules as ``Project``: surrogate UUID row key, client id
/// unique per user (migrated clients all carry `starter-0`-style ids).
/// `projectId` is a plain string (not a FK): client ids are opaque here, and a
/// query may arrive before its project in a batched sync.
final class SavedQueryRecord: Model, @unchecked Sendable {
    static let schema = "saved_queries"

    @ID(key: .id)
    var id: UUID?

    /// Client-generated identifier; unique per user.
    @Field(key: "client_id")
    var clientId: String

    @Parent(key: "user_id")
    var user: User

    @Field(key: "project_id")
    var projectId: String

    @Field(key: "name")
    var name: String

    @Field(key: "query")
    var query: String

    @OptionalField(key: "folder")
    var folder: String?

    @Field(key: "updated_at_ms")
    var updatedAtMs: Int

    @Field(key: "deleted")
    var deleted: Bool

    init() {}
}
