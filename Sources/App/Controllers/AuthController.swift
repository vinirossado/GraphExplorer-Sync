import Fluent
import Vapor

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)

        let protected = routes
            .grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.get("me", use: me)
        protected.delete("auth", "logout", use: logout)
    }

    @Sendable
    func register(req: Request) async throws -> TokenResponse {
        let credentials = try req.content.decode(Credentials.self)
        let email = credentials.email.lowercased().trimmingCharacters(in: .whitespaces)
        guard email.contains("@"), email.count >= 5 else {
            throw Abort(.badRequest, reason: "Invalid email address.")
        }
        guard credentials.password.count >= 8 else {
            throw Abort(.badRequest, reason: "Password must be at least 8 characters.")
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

    @Sendable
    func me(req: Request) async throws -> MeResponse {
        let user = try req.auth.require(User.self)
        return MeResponse(userId: try user.requireID().uuidString, email: user.email)
    }

    /// Revokes the exact token used on this request (per-device logout).
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
