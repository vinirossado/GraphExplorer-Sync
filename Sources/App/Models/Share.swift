import Fluent
import Vapor

/// A publicly readable snapshot of one query + endpoint, addressed by slug.
/// This is the "share a query by link" feature — read requires no auth.
final class Share: Model, @unchecked Sendable {
    static let schema = "shares"

    /// URL slug, e.g. "aZ3kQ9xB".
    @ID(custom: .id, generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @OptionalField(key: "title")
    var title: String?

    @Field(key: "query")
    var query: String

    @Field(key: "endpoint")
    var endpoint: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}
}
