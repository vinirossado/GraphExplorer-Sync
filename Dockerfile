# ── Build ─────────────────────────────────────────────────────────────────────
FROM swift:6.3-noble AS build

WORKDIR /build

# Resolve dependencies first so they cache independently of source changes.
COPY Package.swift Package.resolved* ./
RUN swift package resolve

COPY Sources ./Sources
COPY Tests ./Tests
RUN swift build -c release --product App --static-swift-stdlib

# ── Runtime ───────────────────────────────────────────────────────────────────
FROM ubuntu:noble

RUN apt-get -q update \
    && DEBIAN_FRONTEND=noninteractive apt-get -q install -y \
        ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --system --create-home --home-dir /app vapor
WORKDIR /app
COPY --from=build --chown=vapor:vapor /build/.build/release/App ./App
USER vapor

EXPOSE 8080
ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
