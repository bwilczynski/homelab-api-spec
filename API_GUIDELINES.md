# API Guidelines

Design conventions for the Homelab API. These are enforced by Spectral
rules in `.spectral.yaml` and must be followed when adding or modifying
the spec.

## Naming

- **JSON properties, enum values, operationIds, parameter names:** `camelCase`
- **URL path segments:** `kebab-case`, plural nouns for collections (e.g. `/network-clients`)
- **Scopes:** `<access>:<resource>` (e.g. `read:devices`, `write:services`)

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

## Collections and pagination

- **Collection root key:** `"items": [...]`
- **Pagination:** Cursor-based only. Query params: `cursor` + `limit`. Response includes a `next` link (no `previous`, no offset)

## Responses

- **Null fields:** Omit from response body; empty arrays: `[]`
- **Errors:** RFC 9457 Problem JSON (`application/problem+json`) on all 4xx/5xx. Machine-readable error code in the `type` URI
- **Rate limiting:** `429 Too Many Requests` with `Retry-After` header

## Authentication

- **Mechanism:** OAuth 2.0 bearer token (client credentials flow)
- **Scope format:** `<access>:<resource>` (e.g. `read:devices`)

## Spec-level invariants

These are lint-enforced constraints on the OpenAPI document itself:

- Every operation must have `operationId` and `description`
- Every parameter must have `description`
- Every operation must declare `401` and `500` responses
- All error responses use `application/problem+json`
- Response and request body schemas must use `$ref` to files under `components/schemas/` (no inline schemas)
