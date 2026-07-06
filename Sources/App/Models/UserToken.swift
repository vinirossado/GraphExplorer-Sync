import Fluent
import Vapor

/// Opaque, revocable bearer token. Simpler than JWT for an MVP and strictly
/// more controllable: logout / device revocation is a row delete.
final class UserToken: Model, @unchecked Sendable {
    static let schema = "user_tokens"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "value")
    var value: String

    @Parent(key: "user_id")
    var user: User

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, value: String, userID: User.IDValue) {
        self.id = id
        self.value = value
        self.$user.id = userID
    }

    static func generate(for user: User) throws -> UserToken {
        try UserToken(value: [UInt8].random(count: 32).base64, userID: user.requireID())
    }
}

extension UserToken: ModelTokenAuthenticatable {
    static var valueKey: KeyPath<UserToken, Field<String>> { \.$value }
    static var userKey: KeyPath<UserToken, Parent<User>> { \.$user }

    var isValid: Bool { true }
}
