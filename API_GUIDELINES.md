# API Guidelines

Design conventions for the Homelab API. These are enforced by Spectral
rules in `.spectral.yaml` and must be followed when adding or modifying
the spec.

## URL structure

All paths follow a two-level hierarchy:

```
/{group}/{resource}
/{group}/{resource}/{id}
/{group}/{resource}/{id}:action
```

- **Groups** are singular and fixed: `system`, `docker`, `storage`, `network`
- **Resources** within a group are plural nouns in `kebab-case` (e.g. `containers`, `backups`, `volumes`, `devices`, `clients`)

Examples: `/docker/containers`, `/storage/backups`, `/network/devices`

## Naming

- **JSON properties, enum values, operationIds, parameter names:** `camelCase`
- **URL path segments:** `kebab-case` (see URL structure above)
- **Scopes:** `<access>:<group>` where group matches the URL group segment (e.g. `read:docker`, `write:storage`, `read:system`, `read:network`)

**Enum value exception:** When an enum value encodes a numeric quantity (`<unit><value>`), a single underscore is allowed *between two digits* to encode a decimal point — e.g. `gbe2_5` for 2.5 Gbps. The `_` is permitted only between two digits; everywhere else, the value must remain camelCase. This is enforced by the `enum-value-camelcase` Spectral rule.

## File layout

Schema files live in domain subdirectories mirroring the URL groups:
`openapi/components/schemas/{meta,system,docker,storage,network}/`.
Cross-domain schemas (e.g. `Problem`) go in `common/`; unit schemas in
`units/`. Schema file basenames must stay unique across all
subdirectories — Redocly names bundled components by basename, so a
collision would merge two schemas.

## Resources and operations

- **Composite IDs:** `{device}.{name}` — dot-separated, URL-safe, no encoding required (e.g. `nas-1.homeassistant`)
- **Custom actions:** `POST /resources/{id}:action` (colon style, Azure/Google convention)
- **Partial updates:** `PATCH` with JSON Merge Patch (`application/merge-patch+json`)
- **Idempotency:** Mutating operations accept an `Idempotency-Key` header

## List vs Detail schemas

Every resource that has both a collection (`GET /resources`) and a single-item
(`GET /resources/{id}`) endpoint uses two schemas:

- **`Resource`** (list) — the compact representation returned inside `items`.
  Keep only the fields needed to identify, label, and show status at a glance.
- **`ResourceDetail`** (detail) — extends the list schema via `allOf` and adds
  fields that are only useful when inspecting a single resource (e.g. config,
  firmware, scheduling, nested sub-resources).

This keeps list payloads lean and makes it clear which fields are available at
each level. When adding a new resource, decide the split up front — moving
fields from list to detail later is a breaking change.

## Polymorphism (type-specific variants)

When a resource has multiple variants distinguished by a shared field (e.g.
`type` or `connectionType`), use the `anyOf` + `discriminator` pattern:

- **Base schema** — defines all fields common to every variant. Variant
  schemas extend it via `allOf`.
- **Discriminator property** — a required enum field on the base schema that
  identifies the variant (e.g. `type: container`). Each variant pins the enum
  to a single value.
- **Polymorphic wrapper** — a schema that lists variants under `anyOf` and
  declares the `discriminator` with an explicit `mapping` to file paths.

```yaml
# SystemUpdateDetail.yaml (polymorphic wrapper)
anyOf:
  - $ref: "./ContainerSystemUpdateDetail.yaml"
discriminator:
  propertyName: type
  mapping:
    container: "./ContainerSystemUpdateDetail.yaml"
```

Apply polymorphism at the **detail** level only when variants share a common
list representation. The list schema can reference the base type directly,
keeping collection payloads uniform and simple.

To add a new variant: add the enum value, create the variant schema extending
the base via `allOf`, and register it in the wrapper's `anyOf`/`mapping`.

## Collections and pagination

- **Collection root key:** `"items": [...]`
- **Pagination:** Cursor-based only. Query params: `cursor` + `limit`. Response includes a `next` link (no `previous`, no offset)

## Responses

- **Null fields:** Omit from response body; empty arrays: `[]`
- **Errors:** RFC 9457 Problem JSON (`application/problem+json`) on all 4xx/5xx. Machine-readable error code in the `type` URI
- **Rate limiting:** `429 Too Many Requests` with `Retry-After` header

## Authentication

- **Mechanism:** OAuth 2.0 bearer token (client credentials flow)
- **Scope format:** `<access>:<group>` (e.g. `read:docker`, `write:storage`)

## Spec-level invariants

These are lint-enforced constraints on the OpenAPI document itself:

- Every operation must have `operationId` and `description`
- Every parameter must have `description`
- Every operation must declare `401` and `500` responses
- All error responses use `application/problem+json`
- Response and request body schemas must use `$ref` to files under `components/schemas/` (no inline schemas)

## Versioning

The spec version follows [Semantic Versioning](https://semver.org/) and is
managed by semantic-release. Use these commit prefixes when changing the spec:

| Change type | Commit prefix | Version bump |
|---|---|---|
| Description or example fix | `fix:` | patch |
| New endpoint or new optional field | `feat:` | minor |
| Removal or rename of a field, endpoint, or required parameter | `feat!:` or `BREAKING CHANGE` footer | major |

Commits using other prefixes (`chore:`, `docs:`, `ci:`, etc.) produce no release.

Use `BREAKING CHANGE` only for a true breaking change: removal or rename of a
field, endpoint, or required parameter, or restriction of a previously allowed
value. Endpoints annotated with `x-stability-level: draft` are exempt — only
changes to `stable` endpoints require the `BREAKING CHANGE` footer.

`info.version` in `openapi/openapi.yaml` is patched automatically by the
release workflow — do not edit it by hand.
