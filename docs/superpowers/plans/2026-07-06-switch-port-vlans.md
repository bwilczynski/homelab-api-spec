# Switch Port VLAN Policy & Detail Fields — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-port VLAN policy (native + tagged, with mode discriminator) and four operator-facing detail fields (`label`, `sfpModulePresent`, `linkUptime`, `lagMembership`) to the `SwitchPort` schema, then retrofit three inline `uptime` fields in the network domain to reference the shared `units/Seconds.yaml`.

**Architecture:** Contract-first OpenAPI 3.0.3 spec split into per-resource YAML files under `openapi/`. Redocly's `bundle` command resolves all `$ref`s into a single artifact under `dist/`. Validation runs in two stages: Redocly lint on the source, Spectral lint on the bundled artifact. All new fields are optional; existing consumers keep working.

**Tech Stack:** OpenAPI 3.0.3, Redocly CLI 1.25.15, Spectral 6.15.0, GNU Make, `npx` (no global installs). Runs entirely in the `homelab-api-spec` submodule at `/Users/bwilczynski/Projects/github/bwilczynski/homelab-api/spec/`.

**Spec reference:** `docs/superpowers/specs/2026-07-05-switch-port-vlans-design.md`

---

## Working directory

Every task runs inside the spec submodule. The current branch is `feat/switch-port-vlans`, already created off `origin/main` at `f7fbf26 chore(release): 1.2.1 [skip ci]`. Two commits are already on the branch (`c6a398a`, `74bd059`) that add the design doc.

All shell commands below assume:

```sh
cd /Users/bwilczynski/Projects/github/bwilczynski/homelab-api/spec
```

Confirm branch before starting:

```sh
git rev-parse --abbrev-ref HEAD
# Expected: feat/switch-port-vlans
```

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `openapi/components/schemas/network/NetworkVlanRef.yaml` | Lightweight VLAN reference (`id`, `uri`, `name`, `vlanId`). Peer to `NetworkDeviceRef` / `NetworkClientRef`. |
| `openapi/components/schemas/network/SwitchPortVlanConfig.yaml` | Per-port VLAN policy sub-object with `mode: access\|trunk`, `nativeVlan`, and nested `taggedVlans: {scope, items}`. Referenced from `SwitchPort.vlanConfig`. |

**Modified files:**

| Path | Change |
|---|---|
| `openapi/components/schemas/network/SwitchPort.yaml` | Add 5 optional fields: `label`, `sfpModulePresent`, `linkUptime`, `lagMembership`, `vlanConfig`. |
| `openapi/components/schemas/network/NetworkDeviceDetailBase.yaml` | Retrofit inline `uptime: integer` to `allOf: [$ref: ../units/Seconds.yaml]`. |
| `openapi/components/schemas/network/WiredNetworkClientDetail.yaml` | Same retrofit for wired client session `uptime`. |
| `openapi/components/schemas/network/WirelessNetworkClientDetail.yaml` | Same retrofit for wireless client session `uptime`. |
| `openapi/paths/network-devices-id.yaml` | Update the `switch` example to exercise `vlanConfig`, `label`, `sfpModulePresent`, `linkUptime`, and `lagMembership`. |

**Not touched (out of scope):** the Go implementation repo `homelab-api`; the `hlctl` repo; any other spec paths.

---

## How to verify

Every task ends with `make lint`. Expected clean output:

```
$ make lint
npx --yes @redocly/cli@1.25.15 lint openapi/openapi.yaml
No configurations were provided.  Redocly will use the built-in defaults.

validating openapi/openapi.yaml...
openapi/openapi.yaml: validated in <n>ms

Woohoo! Your API description is valid. 🎉

npx --yes @redocly/cli@1.25.15 bundle openapi/openapi.yaml -o dist/openapi.bundled.yaml
...
npx --yes @stoplight/spectral-cli@6.15.0 lint dist/openapi.bundled.yaml
No results with a severity of 'error' or higher found!
```

If Spectral reports an `error`, the task is not done. If it reports a `warning`, read it — some warnings (e.g. `oas3-unused-component`) are acceptable transient states between tasks; the plan calls those out where they apply.

---

## Task 1: Create `NetworkVlanRef` and `SwitchPortVlanConfig` schema files

**Files:**
- Create: `openapi/components/schemas/network/NetworkVlanRef.yaml`
- Create: `openapi/components/schemas/network/SwitchPortVlanConfig.yaml`

Neither schema is referenced from any path yet. Redocly's bundler follows `$ref`s from the root — unreferenced files are simply not bundled, so lint stays clean on this commit. They get wired up in Task 2.

- [ ] **Step 1: Create `NetworkVlanRef.yaml`**

Write to `openapi/components/schemas/network/NetworkVlanRef.yaml`:

```yaml
type: object
description: Lightweight reference to a VLAN.
properties:
  id:
    type: string
    description: Composite VLAN identifier (matches `Vlan.id`).
    example: "unifi.iot"
  uri:
    type: string
    description: Relative API path to fetch this VLAN's detail.
    example: "/network/vlans/unifi.iot"
  name:
    type: string
    description: Human-readable VLAN name.
    example: "IoT"
  vlanId:
    type: integer
    description: Numeric 802.1Q tag (1–4094).
    example: 20
required:
  - id
  - uri
  - name
  - vlanId
```

- [ ] **Step 2: Create `SwitchPortVlanConfig.yaml`**

Write to `openapi/components/schemas/network/SwitchPortVlanConfig.yaml`:

```yaml
type: object
description: |
  VLAN policy configured on a switch port. Present when the port is
  not administratively disabled (`state != disabled`).
properties:
  mode:
    type: string
    enum: [access, trunk]
    description: |
      - `access` — port carries a single untagged VLAN (the native VLAN)
        and blocks all tagged traffic. Typical for end-device ports.
      - `trunk` — port carries an untagged native VLAN plus one or more
        tagged VLANs. Typical for uplinks and downstream AP links.
  nativeVlan:
    allOf:
      - $ref: "./NetworkVlanRef.yaml"
    description: The untagged VLAN carried on this port.
  taggedVlans:
    type: object
    description: |
      Tagged VLANs allowed on this port. Present only when `mode` is
      `trunk`; omitted for `access`.
    properties:
      scope:
        type: string
        enum: [all, custom]
        description: |
          - `all` — every VLAN configured on the switch is allowed
            (trunk-all).
          - `custom` — only the VLANs listed under `items` are allowed.
      items:
        type: array
        description: |
          Explicit allow-list of tagged VLANs. Present only when
          `scope` is `custom`.
        items:
          $ref: "./NetworkVlanRef.yaml"
    required:
      - scope
required:
  - mode
  - nativeVlan
```

Note on the `allOf: [$ref]` wrapper on `nativeVlan`: the Spectral rule `no-$ref-siblings` (error) forbids `$ref` alongside `description`. The wrapper is required whenever we want to attach a per-property description to a schema reference. The unwrapped `$ref` inside `taggedVlans.items` is fine because it has no siblings.

- [ ] **Step 3: Verify lint still passes**

Run:

```sh
make lint
```

Expected: clean output as shown in "How to verify". Neither new file is referenced yet, so neither appears in the bundle; Spectral has nothing new to say about them and Redocly does not lint standalone component files.

- [ ] **Step 4: Commit**

```sh
git add openapi/components/schemas/network/NetworkVlanRef.yaml \
        openapi/components/schemas/network/SwitchPortVlanConfig.yaml
git commit -m "feat: add NetworkVlanRef and SwitchPortVlanConfig schemas"
```

---

## Task 2: Extend `SwitchPort` with five optional fields

**Files:**
- Modify: `openapi/components/schemas/network/SwitchPort.yaml`

Add `label`, `sfpModulePresent`, `linkUptime`, `lagMembership`, and `vlanConfig` — all optional, so no changes to the `required` list. The existing fields (`number`, `state`, `linkSpeed`, `poeMode`, `poePowerWatts`, `traffic`, `connectedTo`) are untouched.

- [ ] **Step 1: Read the current `SwitchPort.yaml`**

Familiarize yourself with the file so the edit slots the new fields in cleanly.

Run:

```sh
cat openapi/components/schemas/network/SwitchPort.yaml
```

- [ ] **Step 2: Rewrite `SwitchPort.yaml` with the new fields**

Overwrite `openapi/components/schemas/network/SwitchPort.yaml` with:

```yaml
type: object
description: A physical port on a managed switch.
properties:
  number:
    type: integer
    minimum: 1
    description: Physical port number (1-based) as labelled on the switch.
    example: 7
  label:
    type: string
    description: |
      Operator-assigned port label. Omitted when the port uses the
      controller's default label (`Port <number>`).
    example: "Backhaul to attic"
  state:
    $ref: "./NetworkPortState.yaml"
  linkSpeed:
    allOf:
      - $ref: "./NetworkLinkSpeed.yaml"
    description: |
      Negotiated link speed. Omitted when `state` is not `up`.
  linkUptime:
    allOf:
      - $ref: "../units/Seconds.yaml"
    description: |
      Seconds since the current link came up. Present only when
      `state` is `up`; resets on link flap.
  sfpModulePresent:
    type: boolean
    description: |
      Whether an SFP/SFP+ optical module is currently inserted in this
      port's fiber cage. Present only on ports with an SFP cage;
      omitted on RJ45-only ports.
  poeMode:
    $ref: "./SwitchPortPoeMode.yaml"
  poePowerWatts:
    allOf:
      - $ref: "../units/Watts.yaml"
    description: |
      Power currently being delivered through this port. Omitted when
      `poeMode` is `off` or when no powered device is attached.
  lagMembership:
    type: object
    description: |
      Link-aggregation (LAG) membership. Present only when this port
      participates in a LAG (bond).
    properties:
      id:
        type: integer
        minimum: 1
        description: |
          LAG identifier on this switch. Ports sharing an `id` are
          bonded together.
        example: 3
      role:
        type: string
        enum: [master, member]
        description: |
          - `master` — the port that owns the LAG's configuration and
            reports aggregated traffic.
          - `member` — a port bonded into the LAG under a master.
    required:
      - id
      - role
  vlanConfig:
    allOf:
      - $ref: "./SwitchPortVlanConfig.yaml"
    description: |
      VLAN policy configured on this port. Omitted when `state` is
      `disabled` (the port carries no traffic) or when the controller
      does not report enough data to resolve the native VLAN.
  traffic:
    $ref: "./NetworkTraffic.yaml"
  connectedTo:
    allOf:
      - $ref: "./NetworkConnectionRef.yaml"
    description: |
      Reference to the device or client connected on this port. Omitted
      when nothing is connected. When an unmanaged downstream switch
      hangs off the port with multiple endpoints, the controller reports
      a single endpoint (UniFi behavior); consumers should not treat
      this as authoritative for multi-endpoint cases.
required:
  - number
  - state
  - poeMode
  - traffic
```

Field ordering rationale: identity (`number`, `label`) → link status (`state`, `linkSpeed`, `linkUptime`, `sfpModulePresent`) → power (`poeMode`, `poePowerWatts`) → aggregation and VLAN policy (`lagMembership`, `vlanConfig`) → runtime data (`traffic`, `connectedTo`). Preserves the semantic grouping of the original file.

- [ ] **Step 3: Verify lint passes**

Run:

```sh
make lint
```

Expected: clean output. The new schemas `SwitchPortVlanConfig` and `NetworkVlanRef` are now transitively reachable from the root spec (via `SwitchDetail` → `SwitchPort` → `SwitchPortVlanConfig` → `NetworkVlanRef`), so they get bundled and Spectral lints them.

Common failure modes to check for if lint fails:
- Missing `description` on any property — Spectral doesn't require it on schemas, but the codebase style does.
- Enum value not camelCase — `access`, `trunk`, `all`, `custom`, `master`, `member` are all valid.
- `$ref` sibling — every `$ref` in this task is either alone in its property or wrapped in `allOf`.

- [ ] **Step 4: Commit**

```sh
git add openapi/components/schemas/network/SwitchPort.yaml
git commit -m "feat: add label, sfpModulePresent, linkUptime, lagMembership, vlanConfig to SwitchPort"
```

---

## Task 3: Retrofit inline `uptime` fields to `Seconds` schema

**Files:**
- Modify: `openapi/components/schemas/network/NetworkDeviceDetailBase.yaml`
- Modify: `openapi/components/schemas/network/WiredNetworkClientDetail.yaml`
- Modify: `openapi/components/schemas/network/WirelessNetworkClientDetail.yaml`

Three schemas define `uptime` as inline `type: integer` instead of referencing `units/Seconds.yaml`. `Wan.uptime` already uses the shared schema — retrofit the outliers for consistency. `Seconds.yaml` is `type: integer`, so the wire type is unchanged.

- [ ] **Step 1: Edit `NetworkDeviceDetailBase.yaml`**

In `openapi/components/schemas/network/NetworkDeviceDetailBase.yaml`, replace:

```yaml
      uptime:
        type: integer
        description: Seconds since the device last (re)connected to the controller.
        example: 86400
```

with:

```yaml
      uptime:
        allOf:
          - $ref: "../units/Seconds.yaml"
        description: Seconds since the device last (re)connected to the controller.
        example: 86400
```

Preserve the existing indentation (6 spaces for the property key — this file has an `allOf: - $ref: NetworkDevice.yaml - type: object` outer structure).

- [ ] **Step 2: Edit `WiredNetworkClientDetail.yaml`**

In `openapi/components/schemas/network/WiredNetworkClientDetail.yaml`, replace:

```yaml
      uptime:
        type: integer
        description: Seconds since the client's current session started. Omitted for offline clients.
        example: 604800
```

with:

```yaml
      uptime:
        allOf:
          - $ref: "../units/Seconds.yaml"
        description: Seconds since the client's current session started. Omitted for offline clients.
        example: 604800
```

- [ ] **Step 3: Edit `WirelessNetworkClientDetail.yaml`**

In `openapi/components/schemas/network/WirelessNetworkClientDetail.yaml`, replace:

```yaml
      uptime:
        type: integer
        description: Seconds since the client's current session started. Omitted for offline clients.
        example: 7200
```

with:

```yaml
      uptime:
        allOf:
          - $ref: "../units/Seconds.yaml"
        description: Seconds since the client's current session started. Omitted for offline clients.
        example: 7200
```

- [ ] **Step 4: Verify lint passes**

Run:

```sh
make lint
```

Expected: clean output. Every `$ref` is wrapped in `allOf`, satisfying `no-$ref-siblings`.

- [ ] **Step 5: Commit**

```sh
git add openapi/components/schemas/network/NetworkDeviceDetailBase.yaml \
        openapi/components/schemas/network/WiredNetworkClientDetail.yaml \
        openapi/components/schemas/network/WirelessNetworkClientDetail.yaml
git commit -m "fix: reference shared Seconds schema for network uptime fields"
```

Commit prefix is `fix:` (patch bump) because this is a consistency cleanup with no new field or new endpoint. `Seconds.yaml` is `type: integer` — wire type unchanged.

---

## Task 4: Update the switch example in `paths/network-devices-id.yaml`

**Files:**
- Modify: `openapi/paths/network-devices-id.yaml`

Extend the existing `switch:` example under `responses.200.content.application/json.examples` to exercise the new fields on a representative mix of ports (trunk-all uplink, custom-trunk AP downlink, idle access port, LAG member with SFP). Keep the other three examples (`accessPoint`, `gateway`, `unknown`) unchanged. Also update the example's `summary` line to reflect the new port mix.

- [ ] **Step 1: Read the current `switch` example**

Run:

```sh
sed -n '38,115p' openapi/paths/network-devices-id.yaml
```

Familiarize yourself with the exact indentation of the port list. It matters — this file lives under `paths/` and the example lives inside `responses.200.content.application/json.examples`, so the `value:` block is deeply indented.

- [ ] **Step 2: Replace the `switch` example**

Find the `switch:` example block (starts around line 38, ends before `accessPoint:`) and replace it with the block below. The `accessPoint:`, `gateway:`, and `unknown:` examples that follow must be preserved unchanged.

```yaml
            switch:
              summary: A managed switch with four ports (trunk uplink, AP downlink, idle access port, and a NAS on a fiber port bonded into a LAG).
              value:
                id: "unifi.switch-living-room"
                uri: "/network/devices/unifi.switch-living-room"
                name: "Switch Living Room"
                mac: "aa:bb:cc:dd:00:02"
                ip: "192.168.1.2"
                type: switch
                status: connected
                model: "USW-Lite-8-PoE"
                firmwareVersion: "6.6.77.14522"
                uptime: 172800
                traffic:
                  rxBytesTotal: 87960930222
                  txBytesTotal: 43980465111
                  rxBytesPerSec: 1250000
                  txBytesPerSec: 600000
                uplink:
                  device:
                    kind: device
                    id: "unifi.usg"
                    uri: "/network/devices/unifi.usg"
                    name: "USG"
                  port: 1
                  linkSpeed: gbe1
                ports:
                  - number: 1
                    state: up
                    linkSpeed: gbe1
                    linkUptime: 172800
                    poeMode: 'off'
                    vlanConfig:
                      mode: trunk
                      nativeVlan:
                        id: "unifi.default"
                        uri: "/network/vlans/unifi.default"
                        name: "Default"
                        vlanId: 1
                      taggedVlans:
                        scope: all
                    traffic:
                      rxBytesTotal: 43980465111
                      txBytesTotal: 87960930222
                      rxBytesPerSec: 600000
                      txBytesPerSec: 1250000
                    connectedTo:
                      kind: device
                      id: "unifi.usg"
                      uri: "/network/devices/unifi.usg"
                      name: "USG"
                  - number: 7
                    label: "AP Living Room uplink"
                    state: up
                    linkSpeed: gbe2_5
                    linkUptime: 86400
                    poeMode: auto
                    poePowerWatts: 4.5
                    vlanConfig:
                      mode: trunk
                      nativeVlan:
                        id: "unifi.default"
                        uri: "/network/vlans/unifi.default"
                        name: "Default"
                        vlanId: 1
                      taggedVlans:
                        scope: custom
                        items:
                          - id: "unifi.iot"
                            uri: "/network/vlans/unifi.iot"
                            name: "IoT"
                            vlanId: 20
                          - id: "unifi.guest"
                            uri: "/network/vlans/unifi.guest"
                            name: "Guest"
                            vlanId: 30
                    traffic:
                      rxBytesTotal: 12884901888
                      txBytesTotal: 4294967296
                      rxBytesPerSec: 125000
                      txBytesPerSec: 50000
                    connectedTo:
                      kind: device
                      id: "unifi.ap-living-room"
                      uri: "/network/devices/unifi.ap-living-room"
                      name: "AP Living Room"
                  - number: 2
                    state: down
                    poeMode: 'off'
                    vlanConfig:
                      mode: access
                      nativeVlan:
                        id: "unifi.servers"
                        uri: "/network/vlans/unifi.servers"
                        name: "Servers"
                        vlanId: 100
                    traffic:
                      rxBytesTotal: 0
                      txBytesTotal: 0
                      rxBytesPerSec: 0
                      txBytesPerSec: 0
                  - number: 8
                    state: up
                    linkSpeed: gbe2_5
                    linkUptime: 3600
                    sfpModulePresent: true
                    poeMode: 'off'
                    lagMembership:
                      id: 8
                      role: master
                    vlanConfig:
                      mode: access
                      nativeVlan:
                        id: "unifi.servers"
                        uri: "/network/vlans/unifi.servers"
                        name: "Servers"
                        vlanId: 100
                    traffic:
                      rxBytesTotal: 5497558138
                      txBytesTotal: 2748779069
                      rxBytesPerSec: 800000
                      txBytesPerSec: 100000
                    connectedTo:
                      kind: client
                      id: "unifi.nas-1-68"
                      uri: "/network/clients/unifi.nas-1-68"
                      name: "nas-1"
```

Field order in each port matches the `SwitchPort` schema in Task 2 (identity → link → power → aggregation → VLAN → runtime).

- [ ] **Step 3: Verify lint passes**

Run:

```sh
make lint
```

Expected: clean output. If Redocly complains about the example not conforming to the schema, re-check field order isn't the issue (order doesn't matter to the validator) — the more likely cause is a typo (e.g. `vlan:` instead of `vlanConfig:`, `role: `master`` mis-quoted).

- [ ] **Step 4: Confirm the example round-trips through the bundler**

Run:

```sh
grep -c 'vlanConfig' dist/openapi.bundled.yaml
```

Expected: at least `5` (the schema definition plus each of the four ports in the example).

Run:

```sh
grep -c 'lagMembership' dist/openapi.bundled.yaml
```

Expected: at least `2` (the schema definition plus port 8 in the example).

- [ ] **Step 5: Commit**

```sh
git add openapi/paths/network-devices-id.yaml
git commit -m "docs: exercise new switch port fields in the getNetworkDevice example"
```

Commit prefix is `docs:` (no release) because updating an example without changing the schema is a description/example fix.

---

## Task 5: Final validation and design-doc status update

**Files:**
- Modify: `docs/superpowers/specs/2026-07-05-switch-port-vlans-design.md`

- [ ] **Step 1: Re-run the full lint and bundle cycle**

Run:

```sh
make clean && make lint
```

Expected: clean output. `make clean` forces a fresh bundle, so any stale artifact from earlier tasks doesn't mask a problem.

- [ ] **Step 2: Inspect the bundled artifact for the new schemas**

Run:

```sh
grep -E 'NetworkVlanRef:|SwitchPortVlanConfig:' dist/openapi.bundled.yaml
```

Expected: both schemas appear once each under `components.schemas`.

Run:

```sh
sed -n '/^ *SwitchPort:/,/^ *[A-Z][a-zA-Z]*:/p' dist/openapi.bundled.yaml | head -80
```

Expected: the bundled `SwitchPort` schema shows `label`, `linkUptime`, `sfpModulePresent`, `lagMembership`, `vlanConfig` as properties.

- [ ] **Step 3: Flip the design doc status from Draft to Approved**

In `docs/superpowers/specs/2026-07-05-switch-port-vlans-design.md`, change:

```
**Status:** Draft
```

to:

```
**Status:** Approved
```

- [ ] **Step 4: Commit the status flip**

```sh
git add docs/superpowers/specs/2026-07-05-switch-port-vlans-design.md
git commit -m "docs: mark switch-port-vlans design as approved"
```

- [ ] **Step 5: Review the branch's commit list**

Run:

```sh
git log --oneline origin/main..HEAD
```

Expected — six commits (two from design brainstorming plus four new ones):

```
<sha> docs: mark switch-port-vlans design as approved
<sha> docs: exercise new switch port fields in the getNetworkDevice example
<sha> fix: reference shared Seconds schema for network uptime fields
<sha> feat: add label, sfpModulePresent, linkUptime, lagMembership, vlanConfig to SwitchPort
<sha> feat: add NetworkVlanRef and SwitchPortVlanConfig schemas
74bd059 docs: revise design — rename vlan/lag props, drop dashboard framing
c6a398a docs: design for per-port VLAN policy and dashboard fields on switch ports
```

---

## Task 6: Push the branch and open a PR

**Files:** (no file changes — remote and GitHub only)

- [ ] **Step 1: Push the branch**

Run:

```sh
git push -u origin feat/switch-port-vlans
```

Expected: the branch is created upstream, with a hint that a PR can be opened.

- [ ] **Step 2: Open the PR**

Run:

```sh
gh pr create --title "feat: per-port VLAN policy and detail fields on switch ports" --body "$(cat <<'EOF'
## Summary

- Add `NetworkVlanRef` (peer to `NetworkDeviceRef` / `NetworkClientRef`) and `SwitchPortVlanConfig` schemas.
- Extend `SwitchPort` with five optional fields: `label`, `sfpModulePresent`, `linkUptime`, `lagMembership`, `vlanConfig` (native + tagged VLANs, mode discriminator).
- Retrofit three inline `uptime: integer` fields (`NetworkDeviceDetailBase`, `WiredNetworkClientDetail`, `WirelessNetworkClientDetail`) to reference the shared `units/Seconds.yaml`, matching the pattern already used by `Wan.uptime`.
- Update the `switch` example in `getNetworkDevice` to exercise the new fields across trunk-all, trunk-custom, access, and LAG-member ports.

Full design rationale in `docs/superpowers/specs/2026-07-05-switch-port-vlans-design.md`.

## Compatibility

- `GET /network/devices/{deviceId}` is `x-stability-level: draft` — no `BREAKING CHANGE` footer required.
- All new fields are optional. Existing consumers ignore them.
- The `uptime` retrofit swaps inline `type: integer` for a `$ref` to `units/Seconds.yaml` (itself `type: integer`) — the wire type is unchanged.

## Test plan

- [x] `make lint` clean
- [x] `make bundle` succeeds; new schemas appear in `dist/openapi.bundled.yaml`
- [ ] CI `validate.yaml` green on the PR
- [ ] Downstream `homelab-api` (Go impl) PR to follow — out of scope here
EOF
)"
```

Expected: `gh pr create` prints the PR URL. Return it in the final summary.

---

## Notes for the executing agent

- **Do not run `make breaking`.** Per the spec repo's CLAUDE.md, it requires Docker and is unreliable in agent environments. CI runs oasdiff automatically on the PR, and the endpoint is `x-stability-level: draft` anyway.
- **Do not touch `openapi/openapi.yaml`'s `info.version`.** It is managed by semantic-release on merge to `main`.
- **Do not stage or commit `dist/`.** It is a build artifact; `.gitignore` should already exclude it. If you see it in `git status`, stop and investigate before running `git add`.
- **The Go impl repo (`homelab-api`) is out of scope for this plan.** Its follow-up PR lands after this spec ships and the impl repo bumps its submodule pointer.
- **The `hlctl` renderer is out of scope for this plan.** It lands separately in the `hlctl` repo once this spec is available.
