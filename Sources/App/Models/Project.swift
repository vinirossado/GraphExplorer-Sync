import Fluent
import Vapor

/// Mirror of a Graph Explorer project.
///
/// The row key is a surrogate UUID; the CLIENT-generated identifier lives in
/// ``clientId`` and is unique **per user**, not globally — every migrated
/// client ships a project literally named `"default"`, so two accounts must be
/// able to hold the same client id. Timestamps are epoch milliseconds as
/// produced by `Date.now()` in the client; `updatedAtMs` drives last-write-wins.
final class Project: Model, @unchecked Sendable {
    static let schema = "projects"

    @ID(key: .id)
    var id: UUID?

    /// Client-generated identifier (e.g. `"default"`); unique per user.
    @Field(key: "client_id")
    var clientId: String

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
