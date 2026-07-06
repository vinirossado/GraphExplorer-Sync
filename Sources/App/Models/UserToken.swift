import Crypto
import Fluent
import Vapor

/// Opaque, revocable bearer token. Simpler than JWT for an MVP and strictly
/// more controllable: logout / device revocation is a row delete.
///
/// **At-rest protection:** the database stores only the SHA-256 digest of the
/// token — the plaintext exists exactly once, in the login/register response.
/// A leaked database therefore yields no usable sessions. SHA-256 (not Bcrypt)
/// is correct here: token input is 256 bits of CSPRNG output, so brute-force
/// is already infeasible and lookups must be O(1) exact-match.
final class UserToken: Model, @unchecked Sendable {
    static let schema = "user_tokens"

    @ID(key: .id)
    var id: UUID?

    /// SHA-256 digest (hex) of the bearer token — never the token itself.
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

    /// Creates a fresh token, returning the PLAINTEXT to hand to the client
    /// alongside the model (which carries only the digest) to persist.
    static func generate(for user: User) throws -> (plaintext: String, model: UserToken) {
        let plaintext = [UInt8].random(count: 32).base64
        let model = try UserToken(value: Self.digest(of: plaintext), userID: user.requireID())
        return (plaintext, model)
    }

    /// Hex SHA-256 of a presented bearer value.
    static func digest(of token: String) -> String {
        SHA256.hash(data: Data(token.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Authenticates `Authorization: Bearer` headers by digest lookup.
///
/// Replaces Fluent's `ModelTokenAuthenticatable` (which compares the raw
/// value) so the table can store hashes instead of live credentials.
struct TokenAuthenticator: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        let token = try await UserToken.query(on: request.db)
            .filter(\.$value == UserToken.digest(of: bearer.token))
            .first()
        guard let token else { return }
        request.auth.login(try await token.$user.get(on: request.db))
    }
}
