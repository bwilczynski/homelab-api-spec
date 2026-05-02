# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Contract-first OpenAPI spec for a homelab API. This repo holds **only the spec** — no implementation code. The implementation lives in a separate `homelab-api` repo (Go, oapi-codegen) that pulls the bundled spec from here.

The spec is split into per-resource files under `openapi/` following the Redocly multi-file convention. `openapi/openapi.yaml` is the root document that references everything else via `$ref`.

## Commands

```sh
make lint          # Spectral (source + bundled) + Redocly lint — run this before committing
make bundle        # Produce dist/openapi.bundled.{yaml,json}
make build         # Build static Redoc docs site → dist/index.html
make preview       # Live-reload docs preview on http://localhost:8080
make breaking BASE=origin/main  # oasdiff breaking-change detection
```

All tools run via `npx` with pinned versions (no global installs needed). Docker is only needed for `make docs-image` and `make breaking`.

## Spec conventions

All API design conventions are in [`API_GUIDELINES.md`](API_GUIDELINES.md). Read it before adding or modifying the spec. The conventions are enforced by Spectral rules in `.spectral.yaml`.

## How to add a new endpoint

1. Create a path file in `openapi/paths/` (e.g. `devices.yaml`).
2. Create any new schemas in `openapi/components/schemas/`. Reuse existing shared schemas (e.g. `Problem.yaml` for errors).
3. Create any new shared responses in `openapi/components/responses/` or reuse existing ones (Unauthorized, Forbidden, TooManyRequests, InternalServerError).
4. Reference the path file from `openapi/openapi.yaml` under `paths:`.
5. Only add components (schemas, parameters, responses) that the new endpoint actually uses — no pre-registering unused components.
6. Path files reference component files via relative `$ref` paths (e.g. `$ref: "../components/responses/Unauthorized.yaml"`), not through `#/components/...` in the root doc.
7. Run `make lint` to verify.

## Unit schemas

Numeric quantity fields must reference an existing schema from `openapi/components/schemas/units/` via `allOf + $ref` rather than inlining `type: integer` with a description.

Current unit schemas:
- `units/Bytes.yaml` — `int64`, storage sizes
- `units/BytesPerSec.yaml` — `int64`, throughput
- `units/Megabytes.yaml` — `integer`, megabyte quantities

If the same raw numeric type+description would appear in two or more places and no matching unit schema exists, propose creating one before writing it inline.

## Lint pipeline

`make lint` runs Redocly on the source spec (validates structure and references), then Spectral on the bundled artifact (where all `$ref`s are resolved). This avoids false positives from cross-file references that Spectral can't follow in multi-file mode.

## OpenAPI version

The spec uses **3.0.3**. Spectral 6.x has issues with OAS 3.1 PathItem `$ref` resolution (`unevaluatedProperties` false positives). Upgrade when tooling stabilizes.
