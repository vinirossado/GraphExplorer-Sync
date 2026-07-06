import Fluent
import Vapor

/// Mirror of a Graph Explorer project. Ids are CLIENT-generated strings (the
/// desktop app owns identity — including the migrated id "default"), so the
/// server never invents project ids. Timestamps are epoch milliseconds as
/// produced by `Date.now()` in the client; `updatedAtMs` drives last-write-wins.
final class Project: Model, @unchecked Sendable {
    static let schema = "projects"

    @ID(custom: .id, generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "name")
    var name: String

    @Field(key: "endpoint")
    var endpoint: String

    @Field(key: "created_at_ms")
    var createdAtMs: Int

    @Field(key: "last_opened_at_ms")
    var lastOpenedAtMs: Int

    @Field(key: "updated_at_ms")
    var updatedAtMs: Int

    /// Tombstone — deletions must sync too.
    @Field(key: "deleted")
    var deleted: Bool

    init() {}
}
