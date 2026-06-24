# Spec Versioning Design

**Date:** 2026-06-24
**Status:** Approved

## Problem

`info.version` in `openapi.yaml` is static (`0.1.0`) and never bumped. The `homelab-api` server reads this value at build time via `make build` and exposes it as `apiVersion` on `GET /version`. The `homelab-cli` calls `GET /version` to display client, server, and spec versions together. Without automated versioning on the spec, `apiVersion` never changes and compatibility checks are meaningless.

## Decision

Add semantic-release to this repo. On every push to `main`, semantic-release analyzes conventional commits, determines the next SemVer, patches `info.version` in `openapi.yaml`, commits the change back, and creates a GitHub release with a git tag.

This matches the release automation already in place in `homelab-api` and `homelab-cli`.

## Release automation

### `.releaserc.json`

```json
{
  "branches": ["main"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    ["@semantic-release/exec", {
      "prepareCmd": "sed -i 's/^  version: .*/  version: ${nextRelease.version}/' openapi/openapi.yaml"
    }],
    ["@semantic-release/git", {
      "assets": ["openapi/openapi.yaml"],
      "message": "chore(release): ${nextRelease.version} [skip ci]"
    }],
    "@semantic-release/github"
  ]
}
```

### `.github/workflows/release.yaml`

Runs `npx semantic-release` on push to `main`. Requires `GITHUB_TOKEN` (provided automatically by Actions).

## Commit conventions

| Change type | Commit prefix | Version bump |
|---|---|---|
| Description or example fix | `fix:` | patch |
| New endpoint or new optional field | `feat:` | minor |
| Change oasdiff flags as breaking | `feat!:` or `BREAKING CHANGE` footer | major |

### `BREAKING CHANGE` rule

Use the `BREAKING CHANGE` footer (or `!` shorthand) **only when oasdiff reports a breaking change**. oasdiff already ignores endpoints annotated with `x-stability-level: draft`, so no manual filtering is needed. If oasdiff is silent, no breaking change footer.

## SemVer expectations

All current endpoints carry `x-stability-level: draft`. No breaking changes are expected in the near term, so the version will stay in `0.x.y`. When an endpoint graduates to `x-stability-level: stable`, breaking changes on it will trigger a major bump via the normal flow above.

## `info.version` management

`info.version` in `openapi/openapi.yaml` is managed exclusively by semantic-release. Do not edit it by hand.
