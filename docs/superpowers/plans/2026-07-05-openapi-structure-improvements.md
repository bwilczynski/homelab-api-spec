# OpenAPI Structure Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the multi-file OpenAPI spec by domain, deduplicate shared parameters, add missing examples, fix the contradictory 401-on-public-endpoints, and tighten Spectral rules — all without changing the API contract.

**Architecture:** The spec stays a Redocly multi-file layout rooted at `openapi/openapi.yaml`. Schemas move from a flat `openapi/components/schemas/` (~97 files) into domain subdirectories (`common/`, `meta/`, `system/`, `docker/`, `storage/`, `network/`; `units/` stays where it is). Redocly names bundled components by file **basename**, so moving files does not change the bundled contract — a before/after diff of `dist/openapi.bundled.yaml` proves it.

**Tech Stack:** YAML, Redocly CLI + Spectral (via `npx`, pinned in Makefile), Python 3 (stdlib only) for the one-shot `$ref` rewrite.

**Verification model:** This repo has no code tests. "Tests" are: `make lint` (Redocly on source + Spectral on bundle) and diffing `dist/openapi.bundled.yaml` against a pre-change baseline. Do **not** run `make breaking` / oasdiff (requires Docker; unreliable in agent environments).

**Commit conventions:** semantic-release runs on `main`. Use `refactor:`/`chore:` for no-release changes (file moves, lint rules), `fix:` for spec content fixes (examples, removing wrong 401s). All endpoints are `x-stability-level: draft`, so no `BREAKING CHANGE` footers are needed anywhere in this plan.

**Explicitly out of scope (user decision):**
- Stability promotion (`draft` → `stable`) — keeping everything `draft` for now.
- Removing `.vacuum-ruleset.yaml` / `vacuum.conf.yaml` — the user uses vacuum for linting inside neovim. Do not touch these files. (Note: `.vacuum-ruleset.yaml` extends `.spectral.yaml`, so rule renames in Phase 2 must keep vacuum working — Task 10 covers this.)
- Pagination *implementation* — Phase 3 only softens the guideline text.

---

## Phase 1 — Schema reorg, shared parameters, meta examples

### Task 1: Capture baseline bundle

**Files:** none created in-repo (baseline goes to `/tmp`).

- [ ] **Step 1: Confirm clean tree and bundle the current spec**

```bash
git status --short   # expect empty
make bundle
cp dist/openapi.bundled.yaml /tmp/openapi-baseline.yaml
```

Expected: `dist/openapi.bundled.yaml` and `/tmp/openapi-baseline.yaml` exist, no errors.

- [ ] **Step 2: Record the schema file count**

```bash
find openapi/components/schemas -name '*.yaml' | wc -l
```

Expected: `102` (97 domain schemas + 5 unit schemas). If different, list the directory and adjust the move lists in Task 2 before proceeding.

### Task 2: Move schema files into domain subdirectories

**Files:**
- Create directories: `openapi/components/schemas/{common,meta,system,docker,storage,network}/`
- Move (git mv): all 97 non-unit schema files per the lists below
- `openapi/components/schemas/units/` does **not** move

Domain assignment rule used: a schema lives with the tag/path group that references it; shared cross-domain schemas go to `common/`. `ContainerSystemUpdate*` belongs to **system** (it is a variant of `SystemUpdate*`, referenced only from the system-updates endpoints, despite the name). `VolumeMount`, `PortBinding`, `EnvVariable` belong to **docker** (referenced only by `ContainerDetail`). `DiskStatus` belongs to **storage** (referenced by `VolumeDisk`). `IpAddress`, `NetworkTraffic` belong to **network** (referenced by `WanDetail`, `VlanDetail`, `DhcpRange`, `SwitchPort`, `Wan`, `NetworkDeviceDetailBase`).

- [ ] **Step 1: Create the directories**

```bash
mkdir -p openapi/components/schemas/{common,meta,system,docker,storage,network}
```

- [ ] **Step 2: Move files per domain**

```bash
cd openapi/components/schemas

git mv Problem.yaml common/

git mv AuthDiscovery.yaml Version.yaml meta/

git mv ComponentHealth.yaml CpuUsage.yaml DiskIo.yaml Health.yaml \
  HealthStatus.yaml MemoryUsage.yaml NetworkInterfaceUsage.yaml \
  SystemInfo.yaml SystemInfoList.yaml SystemUpdate.yaml \
  SystemUpdateDetail.yaml SystemUpdateList.yaml SystemUpdateStatus.yaml \
  SystemUpdateType.yaml SystemUtilization.yaml SystemUtilizationList.yaml \
  ContainerSystemUpdate.yaml ContainerSystemUpdateDetail.yaml system/

git mv Container.yaml ContainerDetail.yaml ContainerList.yaml \
  ContainerNetwork.yaml ContainerResources.yaml ContainerStatus.yaml \
  DockerImage.yaml DockerImageDetail.yaml DockerImageList.yaml \
  DockerNetwork.yaml DockerNetworkDetail.yaml DockerNetworkList.yaml \
  EnvVariable.yaml PortBinding.yaml VolumeMount.yaml docker/

git mv BackupTask.yaml BackupTaskDetail.yaml BackupTaskList.yaml \
  BackupTaskResult.yaml BackupTaskStatus.yaml DiskStatus.yaml \
  Volume.yaml VolumeDetail.yaml VolumeDisk.yaml VolumeList.yaml \
  VolumeStatus.yaml storage/

git mv AccessPointClient.yaml AccessPointDetail.yaml DhcpMode.yaml \
  DhcpRange.yaml GatewayDetail.yaml IpAddress.yaml NetworkClient.yaml \
  NetworkClientConnectionType.yaml NetworkClientDetail.yaml \
  NetworkClientList.yaml NetworkClientRef.yaml NetworkClientStatus.yaml \
  NetworkConnection.yaml NetworkConnectionRef.yaml NetworkDevice.yaml \
  NetworkDeviceDetail.yaml NetworkDeviceDetailBase.yaml \
  NetworkDeviceList.yaml NetworkDeviceRef.yaml NetworkDeviceStatus.yaml \
  NetworkDeviceType.yaml NetworkLinkSpeed.yaml NetworkPortState.yaml \
  NetworkTopology.yaml NetworkTraffic.yaml Ssid.yaml SsidDetail.yaml \
  SsidList.yaml SwitchDetail.yaml SwitchPort.yaml SwitchPortPoeMode.yaml \
  TopologyClientNode.yaml TopologyDeviceNode.yaml TopologyEdge.yaml \
  TopologyNode.yaml TopologyWiredEdge.yaml TopologyWirelessEdge.yaml \
  UnknownDeviceDetail.yaml Vlan.yaml VlanDetail.yaml VlanList.yaml \
  Wan.yaml WanDetail.yaml WanList.yaml WanStatus.yaml WifiBand.yaml \
  WifiSecurityProtocol.yaml WiredNetworkClientDetail.yaml \
  WirelessConnection.yaml WirelessNetworkClientDetail.yaml network/

cd ../../..
```

- [ ] **Step 3: Verify nothing is left behind and nothing was lost**

```bash
ls openapi/components/schemas/*.yaml 2>/dev/null   # expect: no output (no stray files)
find openapi/components/schemas -name '*.yaml' | wc -l   # expect: 102
```

### Task 3: Rewrite all `$ref`s (and discriminator `mapping` values) to the new locations

**Files:**
- Create (temporary): `/tmp/fix_refs.py`
- Modify: every `.yaml` under `openapi/` whose refs point at a moved schema (path files, response files, schema files themselves, `openapi.yaml` does not reference schemas directly but the script covers it anyway)

The script rewrites any string of the form `<relative-path>/<Name>.yaml` where `<Name>` is a moved schema, recomputing the correct relative path from the referencing file. This catches both `$ref:` values **and** discriminator `mapping:` values (which are plain strings, e.g. in `system/SystemUpdateDetail.yaml` and the `NetworkDeviceDetail`/`NetworkClientDetail` wrappers).

- [ ] **Step 1: Write the rewrite script**

Create `/tmp/fix_refs.py`:

```python
import os, re, sys

ROOT = "openapi"
SCHEMAS = os.path.join(ROOT, "components", "schemas")

# name -> new absolute file path, built from the post-move tree
target = {}
for dirpath, _, files in os.walk(SCHEMAS):
    for f in files:
        if f.endswith(".yaml"):
            name = f[:-5]
            if name in target:
                sys.exit(f"duplicate schema basename: {name}")
            target[name] = os.path.join(dirpath, f)

REF = re.compile(r'(?P<prefix>["\']?)(?P<path>(?:\.\./|\./)[\w./-]*?(?P<name>[A-Za-z][\w-]*)\.yaml)')

changed = 0
for dirpath, _, files in os.walk(ROOT):
    for f in files:
        if not f.endswith(".yaml"):
            continue
        fp = os.path.join(dirpath, f)
        src = open(fp).read()

        def sub(m):
            name = m.group("name")
            if name not in target:
                return m.group(0)  # not a schema ref (e.g. responses/, parameters/)
            rel = os.path.relpath(target[name], dirpath).replace(os.sep, "/")
            if not rel.startswith("."):
                rel = "./" + rel
            return m.group("prefix") + rel

        out = REF.sub(sub, src)
        if out != src:
            open(fp, "w").write(out)
            changed += 1
            print("rewrote", fp)

print(f"{changed} files rewritten")
```

- [ ] **Step 2: Run it**

```bash
python3 /tmp/fix_refs.py
```

Expected: prints a list of rewritten files (path files, response files, schema files with cross-domain or intra-domain refs) and a final count, no errors. Note: refs to `responses/` and `parameters/` files are untouched because their basenames (e.g. `Unauthorized`) are not schema names — with one caveat: `NotFound`, `BadRequest` etc. are response basenames that don't collide with any schema basename, verified by the duplicate check in the script.

- [ ] **Step 3: Spot-check the tricky cases**

```bash
grep -n "yaml" openapi/components/schemas/system/SystemUpdateDetail.yaml
grep -n "yaml" openapi/components/schemas/docker/ContainerDetail.yaml
grep -n "yaml" openapi/components/responses/Unauthorized.yaml
grep -n "schemas/" openapi/paths/docker-containers.yaml
```

Expected:
- `SystemUpdateDetail.yaml`: `anyOf` ref **and** `mapping:` value both point to `./ContainerSystemUpdateDetail.yaml` (same dir).
- `ContainerDetail.yaml`: units ref is now `../units/Bytes.yaml`; sibling refs stay `./PortBinding.yaml` etc.
- `Unauthorized.yaml`: `../schemas/common/Problem.yaml`.
- `docker-containers.yaml`: `../components/schemas/docker/ContainerList.yaml`.

### Task 4: Verify the reorg is contract-neutral and commit

- [ ] **Step 1: Lint**

```bash
make lint
```

Expected: PASS (0 errors). If Redocly reports unresolved refs, the file it names has a ref the script missed — fix that ref by hand using the pattern from Task 3 Step 3 and re-run.

- [ ] **Step 2: Diff bundled output against baseline**

```bash
make bundle
diff /tmp/openapi-baseline.yaml dist/openapi.bundled.yaml
```

Expected: **no output** (byte-identical). Redocly names components by basename, so a pure move must not change the bundle. Any diff means a ref was rewritten to the wrong schema — investigate before committing.

- [ ] **Step 3: Commit**

```bash
git add -A openapi/
git commit -m "refactor: group component schemas into domain subdirectories"
```

(`refactor:` produces no release — correct, since the bundled contract is unchanged.)

### Task 5: Extract shared `ContainerId` and `IdempotencyKey` parameters

**Files:**
- Create: `openapi/components/parameters/ContainerId.yaml`
- Create: `openapi/components/parameters/IdempotencyKey.yaml`
- Modify: `openapi/paths/docker-containers-id.yaml`, `openapi/paths/docker-containers-id-start.yaml`, `openapi/paths/docker-containers-id-stop.yaml`, `openapi/paths/docker-containers-id-restart.yaml`, `openapi/paths/system-updates-check.yaml`

`containerId` is defined inline in 4 files, `Idempotency-Key` in 4 files (the three container actions + `system-updates-check`). Both go to `components/parameters/` alongside the existing `DeviceFilter.yaml`.

- [ ] **Step 1: Create the parameter files**

`openapi/components/parameters/ContainerId.yaml`:

```yaml
name: containerId
in: path
required: true
description: |
  Composite container identifier in the form `{deviceId}.{name}`
  (e.g. `nas-1.homeassistant`).
schema:
  type: string
example: "nas-1.homeassistant"
```

`openapi/components/parameters/IdempotencyKey.yaml`:

```yaml
name: Idempotency-Key
in: header
required: false
description: Client-generated key to ensure the request is processed at most once.
schema:
  type: string
example: "b4f3c2a1-7e8d-4f5a-9c0b-1d2e3f4a5b6c"
```

- [ ] **Step 2: Replace the inline definitions**

In each of the five path files, replace the inline parameter object(s) with refs. For the three container action files (`-start`, `-stop`, `-restart`) the `parameters:` block becomes:

```yaml
  parameters:
    - $ref: "../components/parameters/ContainerId.yaml"
    - $ref: "../components/parameters/IdempotencyKey.yaml"
```

In `docker-containers-id.yaml`, replace only the inline `containerId` parameter with `- $ref: "../components/parameters/ContainerId.yaml"` (keep any other parameters as-is). In `system-updates-check.yaml`, replace only the inline `Idempotency-Key` parameter with `- $ref: "../components/parameters/IdempotencyKey.yaml"`.

Before replacing, diff each inline definition against the shared file content. If an inline copy differs (e.g. a different description), keep the shared file's wording only if the difference is trivial phrasing; if a copy differs materially, stop and flag it instead of silently unifying.

- [ ] **Step 3: Lint and inspect the bundle diff**

```bash
make lint
make bundle
diff /tmp/openapi-baseline.yaml dist/openapi.bundled.yaml | head -60
```

Expected: lint PASSES. The bundle diff is **not** empty this time — Redocly hoists the shared files into `components.parameters.ContainerId` / `components.parameters.IdempotencyKey` and replaces inline definitions with `$ref: '#/components/parameters/...'`. Verify the diff shows *only* this hoisting (new component entries + `$ref` substitutions), no semantic changes to names, schemas, or requiredness.

- [ ] **Step 4: Commit**

```bash
git add openapi/components/parameters/ContainerId.yaml \
        openapi/components/parameters/IdempotencyKey.yaml \
        openapi/paths/docker-containers-id.yaml \
        openapi/paths/docker-containers-id-start.yaml \
        openapi/paths/docker-containers-id-stop.yaml \
        openapi/paths/docker-containers-id-restart.yaml \
        openapi/paths/system-updates-check.yaml
git commit -m "refactor: extract shared ContainerId and IdempotencyKey parameters"
git status --short   # expect clean
```

- [ ] **Step 5: Refresh the baseline** (later tasks diff against the new state)

```bash
cp dist/openapi.bundled.yaml /tmp/openapi-baseline.yaml
```

### Task 6: Add response examples to the meta endpoints

**Files:**
- Modify: `openapi/paths/meta-version.yaml`
- Modify: `openapi/paths/meta-auth.yaml`

These are the only two path files without response examples. Examples must satisfy the schemas: `Version` requires `apiVersion` + `serverVersion`; `AuthDiscovery` requires `enabled`, with `issuer` omitted when auth is disabled.

- [ ] **Step 1: Add example to `meta-version.yaml`**

Change the 200 response to:

```yaml
    "200":
      description: Version information.
      content:
        application/json:
          schema:
            $ref: "../components/schemas/meta/Version.yaml"
          examples:
            release:
              summary: Server running a tagged release.
              value:
                apiVersion: "1.1.0"
                serverVersion: "0.4.2"
```

- [ ] **Step 2: Add examples to `meta-auth.yaml`**

Change the 200 response to:

```yaml
    "200":
      description: Auth configuration.
      content:
        application/json:
          schema:
            $ref: "../components/schemas/meta/AuthDiscovery.yaml"
          examples:
            authEnabled:
              summary: Auth enforced against a homelab IdP.
              value:
                enabled: true
                issuer: "https://idp.homelab.local"
            authDisabled:
              summary: Auth disabled (trusted-network deployment). `issuer` omitted.
              value:
                enabled: false
```

- [ ] **Step 3: Lint and commit**

```bash
make lint
git add openapi/paths/meta-version.yaml openapi/paths/meta-auth.yaml
git commit -m "fix: add response examples to meta endpoints"
```

Expected: lint PASSES. (`fix:` → patch release, per the versioning table — examples are spec content.)

### Task 7: Update repo docs for the new layout

**Files:**
- Modify: `CLAUDE.md` (repo root)
- Modify: `API_GUIDELINES.md`

- [ ] **Step 1: Update `CLAUDE.md`**

In the "How to add a new endpoint" section, change step 2 from:

> 2. Create any new schemas in `openapi/components/schemas/`. Reuse existing shared schemas (e.g. `Problem.yaml` for errors).

to:

> 2. Create any new schemas in the matching domain subdirectory of `openapi/components/schemas/` (`meta/`, `system/`, `docker/`, `storage/`, `network/`; cross-domain schemas go in `common/`). Reuse existing shared schemas (e.g. `common/Problem.yaml` for errors).

- [ ] **Step 2: Update `API_GUIDELINES.md`**

Add a short subsection at the end of "Naming" (or as its own section after "URL structure"):

```markdown
## File layout

Schema files live in domain subdirectories mirroring the URL groups:
`openapi/components/schemas/{meta,system,docker,storage,network}/`.
Cross-domain schemas (e.g. `Problem`) go in `common/`; unit schemas in
`units/`. Schema file basenames must stay unique across all
subdirectories — Redocly names bundled components by basename, so a
collision would merge two schemas.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md API_GUIDELINES.md
git commit -m "docs: document domain-subdirectory schema layout"
```

---

## Phase 2 — Public-endpoint 401 fix + Spectral tightening

### Task 8: Scope error-response rules to protected operations; add 403/429 rules

**Files:**
- Modify: `.spectral.yaml`

Current problem: `operation-has-401` fires on every operation, which forced `meta-version.yaml` and `meta-auth.yaml` (both `security: []`, public) to declare a 401 they can never return. Also 403/429 are declared on (almost) every protected op by convention but not enforced.

The filter `?(@ && @.responses && (!@.security || @.security.length > 0))` selects operation objects (they have `responses`) that are protected: either they inherit the root-level `security` (no `security` key) or declare a non-empty one. `security: []` (public) is excluded. Spectral lints the **bundled** artifact where this structure is fully resolved.

- [ ] **Step 1: Add a `ProtectedOperation` alias**

In `.spectral.yaml`, add to the `aliases:` block:

```yaml
  ProtectedOperation:
    - "$.paths[*][?(@ && @.responses && (!@.security || @.security.length > 0))]"
```

- [ ] **Step 2: Replace `operation-has-401` and add 403/429 rules**

Replace the existing `operation-has-401` rule with:

```yaml
  operation-has-401:
    description: Protected operations must declare a 401 response. Public operations (security: []) must not need one.
    message: Protected operation is missing a 401 Unauthorized response.
    severity: error
    given: "#ProtectedOperation"
    then:
      field: responses.401
      function: truthy

  operation-has-403:
    description: Protected operations must declare a 403 response (insufficient scope).
    message: Protected operation is missing a 403 Forbidden response.
    severity: error
    given: "#ProtectedOperation"
    then:
      field: responses.403
      function: truthy

  operation-has-429:
    description: Protected operations must declare a 429 response with Retry-After.
    message: Protected operation is missing a 429 Too Many Requests response.
    severity: error
    given: "#ProtectedOperation"
    then:
      field: responses.429
      function: truthy
```

Keep `operation-has-500` unchanged (500 applies to public endpoints too).

- [ ] **Step 3: Run lint to surface violations**

```bash
make lint
```

Expected: **one known failure** — `getNetworkTopology` in `openapi/paths/network-topology.yaml` is protected but missing a 403 response. (The meta endpoints must NOT be flagged; if they are, the alias filter is wrong — fix the filter, don't add responses to public endpoints.)

- [ ] **Step 4: Fix `network-topology.yaml`**

In `openapi/paths/network-topology.yaml`, add to the `responses:` map (after `"401"`):

```yaml
    "403":
      $ref: "../components/responses/Forbidden.yaml"
```

- [ ] **Step 5: Re-run lint**

```bash
make lint
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add .spectral.yaml openapi/paths/network-topology.yaml
git commit -m "fix: enforce 401/403/429 on protected operations; add missing 403 to network topology"
```

### Task 9: Remove the contradictory 401s from public meta endpoints

**Files:**
- Modify: `openapi/paths/meta-version.yaml` (delete lines declaring the 401 response)
- Modify: `openapi/paths/meta-auth.yaml` (same)

- [ ] **Step 1: Delete the 401 response from both files**

In each file remove:

```yaml
    "401":
      $ref: "../components/responses/Unauthorized.yaml"
```

(`Unauthorized.yaml` stays — every protected endpoint still uses it.)

- [ ] **Step 2: Lint**

```bash
make lint
```

Expected: PASS (the new `ProtectedOperation` scoping means no rule demands the 401 back).

- [ ] **Step 3: Commit**

Both endpoints are `x-stability-level: draft`, so removing a response needs no `BREAKING CHANGE` footer.

```bash
git add openapi/paths/meta-version.yaml openapi/paths/meta-auth.yaml
git commit -m "fix: remove unreachable 401 responses from public meta endpoints"
```

### Task 10: Split parameter naming rules by location

**Files:**
- Modify: `.spectral.yaml`
- Check (do not break): `.vacuum-ruleset.yaml` — it extends `.spectral.yaml` and disables a rule by name; verify the names it references still exist after this change.

Current `parameter-name-camelcase` uses `^[a-zA-Z][a-zA-Z0-9-]*$`, which accepts PascalCase and kebab-case query params — it is loose only so `Idempotency-Key` (a header) passes. Split into location-specific rules.

- [ ] **Step 1: Replace the rule**

Remove `parameter-name-camelcase` and add:

```yaml
  query-path-parameter-camelcase:
    description: Query and path parameter names must be camelCase.
    message: "Parameter name '{{value}}' must be camelCase."
    severity: error
    given:
      - "$.paths[*][get,put,post,delete,patch,options,head,trace].parameters[?(@.in == 'query' || @.in == 'path')]"
      - "$.paths[*].parameters[?(@.in == 'query' || @.in == 'path')]"
      - "$.components.parameters[?(@.in == 'query' || @.in == 'path')]"
    then:
      field: name
      function: pattern
      functionOptions:
        match: "^[a-z][a-zA-Z0-9]*$"

  header-parameter-hyphenated-pascal:
    description: Header parameter names must be Hyphenated-Pascal-Case (e.g. Idempotency-Key).
    message: "Header parameter name '{{value}}' must be Hyphenated-Pascal-Case."
    severity: error
    given:
      - "$.paths[*][get,put,post,delete,patch,options,head,trace].parameters[?(@.in == 'header')]"
      - "$.paths[*].parameters[?(@.in == 'header')]"
      - "$.components.parameters[?(@.in == 'header')]"
    then:
      field: name
      function: pattern
      functionOptions:
        match: "^[A-Z][a-zA-Z0-9]*(-[A-Z][a-zA-Z0-9]*)*$"
```

Note: the old `ParameterObject` alias is still used by `parameter-description-required` — leave the alias in place.

- [ ] **Step 2: Check vacuum config compatibility**

```bash
cat .vacuum-ruleset.yaml
```

It disables `paths-kebab-case` only — not the renamed parameter rule — so no change needed. If it *had* referenced `parameter-name-camelcase`, update the name there too.

- [ ] **Step 3: Lint**

```bash
make lint
```

Expected: PASS — all existing query/path params are already camelCase and the only header param is `Idempotency-Key`.

- [ ] **Step 4: Update `API_GUIDELINES.md` naming section**

Change the Naming bullet from:

> - **JSON properties, enum values, operationIds, parameter names:** `camelCase`

to:

> - **JSON properties, enum values, operationIds, query/path parameter names:** `camelCase`
> - **Header parameter names:** `Hyphenated-Pascal-Case` (e.g. `Idempotency-Key`)

- [ ] **Step 5: Commit**

```bash
git add .spectral.yaml API_GUIDELINES.md
git commit -m "chore: split parameter naming lint rules by parameter location"
```

---

## Phase 3 — Align the pagination guideline with reality

### Task 11: Soften the pagination guideline

**Files:**
- Modify: `API_GUIDELINES.md`
- Modify: `.spectral.yaml` (header comment only)

No endpoint implements pagination and none needs it at homelab scale (`listContainers` already documents this). Keep cursor-based as the *reserved* design so a future addition is consistent and non-breaking (adding an optional `next` field is a `feat:` minor bump).

- [ ] **Step 1: Rewrite the "Collections and pagination" section in `API_GUIDELINES.md`**

Replace:

```markdown
## Collections and pagination

- **Collection root key:** `"items": [...]`
- **Pagination:** Cursor-based only. Query params: `cursor` + `limit`. Response includes a `next` link (no `previous`, no offset)
```

with:

```markdown
## Collections and pagination

- **Collection root key:** `"items": [...]`
- **Pagination:** List endpoints are **unpaginated by design** — a homelab
  has a manageable number of resources, so collections return all matching
  results. State this in the operation description when it is not obvious.
- **If pagination is ever needed** for a specific endpoint, it must be
  cursor-based: query params `cursor` + `limit`, response gains an optional
  `next` link (no `previous`, no offset). Adding the optional `next` field
  and the query params is a non-breaking `feat:` change.
```

- [ ] **Step 2: Fix the stale `.spectral.yaml` header comment**

Change:

```yaml
# Rules encode the conventions from the 002-api-patterns decisions
# doc: camelCase JSON fields, kebab-case paths, plural nouns, cursor
# pagination, RFC 9457 problem responses, operationId + description
# on every operation, no inline schemas.
```

to:

```yaml
# Rules encode the conventions from the 002-api-patterns decisions
# doc: camelCase JSON fields, kebab-case paths, plural nouns,
# RFC 9457 problem responses, operationId + description on every
# operation, no inline schemas. Lists are unpaginated by design
# (see API_GUIDELINES.md).
```

- [ ] **Step 3: Lint (sanity) and commit**

```bash
make lint
git add API_GUIDELINES.md .spectral.yaml
git commit -m "docs: document that list endpoints are unpaginated by design"
```

---

## Final verification (after all phases)

- [ ] `make lint` — PASS
- [ ] `make bundle && diff /tmp/openapi-baseline.yaml dist/openapi.bundled.yaml` — diff shows **only**: the two meta examples added, the two 401 responses removed, and the 403 added to `getNetworkTopology`. Nothing else.
- [ ] `git log --oneline` — commits follow the conventions above; no `BREAKING CHANGE` footers (all endpoints are draft).
- [ ] Do **not** push; leave the branch for review.
