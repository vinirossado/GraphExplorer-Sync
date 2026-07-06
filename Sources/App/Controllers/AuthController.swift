import Fluent
import Vapor

/// Account lifecycle: registration, login, logout, identity.
///
/// Authentication uses **opaque bearer tokens** — random 256-bit values stored
/// server-side — rather than JWTs. A token is issued per login (i.e. per
/// device) and revoked individually, so "log out this device" is a row delete
/// and a stolen token can be killed without rotating keys.
///
/// `POST /auth/register` and `POST /auth/login` sit behind a strict per-IP
/// rate limit (see ``RateLimitMiddleware``) to blunt credential stuffing.
struct AuthController: RouteCollection {
    /// Strict limiter applied to the unauthenticated endpoints only.
    let rateLimit: RateLimitMiddleware

    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth").grouped(rateLimit)
        auth.post("register", use: register)
        auth.post("login", use: login)

        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.get("me", use: me)
        protected.delete("auth", "logout", use: logout)
    }

    /// Creates an account and returns a fresh token (auto-login).
    ///
    /// - Parameter req: Body must decode to ``Credentials``.
    /// - Returns: ``TokenResponse`` with the bearer token to store client-side.
    /// - Throws: `400` for invalid email/password shape, `409` when the email
    ///   is already registered.
    @Sendable
    func register(req: Request) async throws -> TokenResponse {
        let credentials = try req.content.decode(Credentials.self)
        let email = credentials.email.lowercased().trimmingCharacters(in: .whitespaces)
        guard email.contains("@"), (5...254).contains(email.count) else {
            throw Abort(.badRequest, reason: "Invalid email address.")
        }
        // Bcrypt silently truncates at 72 bytes — reject instead of pretending
        // longer passwords add entropy.
        guard (8...72).contains(credentials.password.count) else {
            throw Abort(.badRequest, reason: "Password must be 8–72 characters.")
        }
        let existing = try await User.query(on: req.db)
            .filter(\.$email == email)
            .first()
        guard existing == nil else {
            throw Abort(.conflict, reason: "An account with this email already exists.")
        }

        let user = User(
            email: email,
            passwordHash: try Bcrypt.hash(credentials.password)
        )
        try await user.save(on: req.db)
        return try await issueToken(for: user, on: req)
    }

    /// Exchanges email + password for a new bearer token.
    ///
    /// - Returns: ``TokenResponse`` for this device/session.
    /// - Throws: `401` on unknown email or wrong password — deliberately the
    ///   same error for both, so the endpoint doesn't leak which emails exist.
    @Sendable
    func login(req: Request) async throws -> TokenResponse {
        let credentials = try req.content.decode(Credentials.self)
        let email = credentials.email.lowercased().trimmingCharacters(in: .whitespaces)
        guard
            let user = try await User.query(on: req.db)
                .filter(\.$email == email)
                .first(),
            try Bcrypt.verify(credentials.password, created: user.passwordHash)
        else {
            throw Abort(.unauthorized, reason: "Invalid email or password.")
        }
        return try await issueToken(for: user, on: req)
    }

    /// Returns the authenticated account's identity.
    @Sendable
    func me(req: Request) async throws -> MeResponse {
        let user = try req.auth.require(User.self)
        return MeResponse(userId: try user.requireID().uuidString, email: user.email)
    }

    /// Revokes exactly the token used on this request (per-device logout).
    ///
    /// Other devices' tokens keep working — revoke them by logging out there.
    @Sendable
    func logout(req: Request) async throws -> HTTPStatus {
        guard let bearer = req.headers.bearerAuthorization else {
            throw Abort(.badRequest, reason: "Missing bearer token.")
        }
        try await UserToken.query(on: req.db)
            .filter(\.$value == bearer.token)
            .delete()
        return .noContent
    }

    private func issueToken(for user: User, on req: Request) async throws -> TokenResponse {
        let token = try UserToken.generate(for: user)
        try await token.save(on: req.db)
        return TokenResponse(
            token: token.value,
            userId: try user.requireID().uuidString,
            email: user.email
        )
    }
}
