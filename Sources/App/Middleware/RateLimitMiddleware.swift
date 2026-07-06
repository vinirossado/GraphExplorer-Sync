import Vapor

/// A fixed-window, per-client request counter.
///
/// Each client key (normally an IP address) gets a counting window of the
/// configured length. The first request opens the window; once the request
/// budget is spent, further requests are denied until the window expires.
/// Expired windows are swept lazily so memory stays proportional to *active*
/// clients.
///
/// The actor guarantees the count/update is race-free under concurrent
/// requests without any locking in the middleware itself.
///
/// ```swift
/// let limiter = RateLimiter(maxRequests: 120, windowSeconds: 60)
/// let allowed = await limiter.allow("203.0.113.7")
/// ```
actor RateLimiter {
    private struct Window {
        var startedAt: Date
        var count: Int
    }

    private let maxRequests: Int
    private let windowSeconds: TimeInterval
    private var windows: [String: Window] = [:]
    private var lastSweep = Date()

    /// Creates a limiter.
    ///
    /// - Parameters:
    ///   - maxRequests: Requests allowed per window per client key.
    ///   - windowSeconds: Window length in seconds.
    init(maxRequests: Int, windowSeconds: TimeInterval) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
    }

    /// Registers one request for `key` and reports whether it is allowed.
    ///
    /// - Parameters:
    ///   - key: Client identity — typically the IP address.
    ///   - now: Injection point for tests; defaults to the current time.
    /// - Returns: `true` when the request fits the current window.
    func allow(_ key: String, now: Date = Date()) -> Bool {
        sweepIfNeeded(now: now)
        if var window = windows[key],
           now.timeIntervalSince(window.startedAt) < windowSeconds {
            guard window.count < maxRequests else { return false }
            window.count += 1
            windows[key] = window
            return true
        }
        windows[key] = Window(startedAt: now, count: 1)
        return true
    }

    /// Drops expired windows at most once per window length.
    private func sweepIfNeeded(now: Date) {
        guard now.timeIntervalSince(lastSweep) > windowSeconds else { return }
        lastSweep = now
        windows = windows.filter {
            now.timeIntervalSince($0.value.startedAt) < windowSeconds
        }
    }
}

/// Rejects requests over a per-IP budget with `429 Too Many Requests`.
///
/// Attach one instance globally with a generous budget, and a second, stricter
/// instance on sensitive route groups (login/registration) to blunt
/// credential-stuffing:
///
/// ```swift
/// app.middleware.use(RateLimitMiddleware(limiter: global))
/// let auth = routes.grouped(RateLimitMiddleware(limiter: strict))
/// ```
///
/// Client identity honours `X-Forwarded-For` (first hop) so limits keep
/// working behind Azure ingress / reverse proxies, falling back to the socket
/// peer address for direct connections.
struct RateLimitMiddleware: AsyncMiddleware {
    let limiter: RateLimiter

    func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        let key = Self.clientKey(for: request)
        guard await limiter.allow(key) else {
            throw Abort(.tooManyRequests, reason: "Rate limit exceeded. Try again shortly.")
        }
        return try await next.respond(to: request)
    }

    /// Best available client identity: proxy header first, then socket peer.
    static func clientKey(for request: Request) -> String {
        if let forwarded = request.headers.first(name: .xForwardedFor),
           let first = forwarded.split(separator: ",").first {
            return first.trimmingCharacters(in: .whitespaces)
        }
        return request.remoteAddress?.ipAddress ?? "unknown"
    }
}
