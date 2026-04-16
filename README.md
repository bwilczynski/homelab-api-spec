# homelab-api-spec

Contract-first OpenAPI spec for the Homelab API — a unified surface
over heterogeneous homelab backends (UniFi, Synology, Docker, Immich,
Hue, Sonos, UPS) designed for AI agents and tooling.

This repo is the **contract only**. The implementation lives in a
separate `homelab-api` repo and is generated or validated against the
bundled spec produced here. See the project idea doc for the full
architecture, phased plan, and rationale.

## Layout

```
openapi/
├── openapi.yaml                  # Root document; refs everything else
├── paths/                        # One file per resource
│   └── system-health.yaml
└── components/
    ├── schemas/                  # Reusable schemas (Problem, Health, …)
    ├── parameters/               # Shared params (Cursor, Limit)
    ├── responses/                # Shared error responses
    └── securitySchemes/          # BearerAuth (OAuth2 clientCredentials)
.spectral.yaml                    # Lint rules (primary)
redocly.yaml                      # Redocly config (bundling + docs)
Dockerfile                        # Serves bundled docs via nginx
Makefile                          # lint / bundle / build / preview / breaking
.github/workflows/
├── lint.yaml                     # PR gate: spectral + redocly + oasdiff
└── docs.yaml                     # On merge: build and push docs image
```

## Prerequisites

- Node 20+ (tools run via `npx`, nothing is installed globally)
- Docker (only for `make docs-image` and `make breaking`)

## Common commands

```sh
make lint          # Spectral (source + bundled) + Redocly lint
make bundle        # Emit dist/openapi.bundled.{yaml,json}
make build         # Build static Redoc site → dist/index.html
make preview       # Live-reload docs preview on http://localhost:8080
make docs-image    # Build the docs container image
make breaking BASE=origin/main   # oasdiff breaking-change check vs BASE
```

## Conventions

All design conventions and lint-enforced invariants are documented in
[API_GUIDELINES.md](API_GUIDELINES.md). Spectral rules in
`.spectral.yaml` encode these conventions automatically.

## Workflow

1. Open a PR modifying `openapi/**`.
2. CI runs `make lint` (spectral + redocly) plus an `oasdiff`
   breaking-change check against the PR base. A Redocly docs preview
   can be spun up locally with `make preview`.
3. On merge to `main`, the docs image is built and pushed to GHCR.
4. The implementation repo (`homelab-api`) pulls the merged spec and
   regenerates server stubs / contract tests.

## OpenAPI version

The spec targets **OpenAPI 3.0.3** for now. Upgrading to 3.1 is a
one-line change once the tooling chain (Spectral, oapi-codegen,
oasdiff, Redocly) has stable 3.1 support for features this project
actually needs.

## Status

Skeleton. Currently only `GET /system/health` is defined — enough to
validate the full pipeline (spec → lint → bundle → docs → deploy) end
to end. See the project idea doc for the planned API surface and
phased roadmap (HTTP API → CLI → MCP server).
