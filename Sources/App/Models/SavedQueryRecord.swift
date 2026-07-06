import Fluent
import Vapor

/// Mirror of a saved query. `projectId` is a plain string (not a FK): client
/// ids like "starter-<uuid>-3" are opaque here, and a query may arrive before
/// its project in a batched sync.
final class SavedQueryRecord: Model, @unchecked Sendable {
    static let schema = "saved_queries"

    @ID(custom: .id, generatedBy: .user)
    var id: String?

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
