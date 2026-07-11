# Gateway LAN Ports & Gateway WAN References — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the `SwitchPort*` schema family to `DevicePort*`, expose gateway LAN switch-fabric ports through `GatewayDetail` and the flat `/network/ports` listing, and add `wans: [WanRef]` to `GatewayDetail` so consumers can enumerate a gateway's WAN interfaces without fanning out.

**Architecture:** Contract-first OpenAPI 3.0.3 spec split into per-resource YAML files under `openapi/`. Redocly's `bundle` resolves all `$ref`s into a single artifact under `dist/`. Validation is two-stage: Redocly lint on the source, Spectral lint on the bundled artifact. Every affected endpoint carries `x-stability-level: draft`, so renames and required-field additions on `GatewayDetail` are allowed without a `BREAKING CHANGE` footer.

**Tech Stack:** OpenAPI 3.0.3, Redocly CLI 1.25.15, Spectral 6.15.0, GNU Make, `npx` (no global installs).

**Spec reference:** `docs/superpowers/specs/2026-07-11-gateway-ports-design.md`

---

## Working directory

Every task runs at the repo root:

```sh
cd /Users/bwilczynski/Projects/github/bwilczynski/homelab-api-spec
```

The current branch is `feat/gateway-lan-ports`, already created off `origin/main` at `e258d2c chore(release): 1.4.0 [skip ci]`. One commit is already on the branch (`563a78c`) that added the design doc.

Confirm branch before starting:

```sh
git rev-parse --abbrev-ref HEAD
# Expected: feat/gateway-lan-ports
```

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `openapi/components/schemas/network/WanRef.yaml` | Lightweight WAN reference (`id`, `uri`, `name`). Monomorphic — no `kind` discriminator. Peer to `NetworkVlanRef`. Consumed by `GatewayDetail.wans[]`. |

**Renamed files (git mv):**

| From | To |
|---|---|
| `openapi/components/schemas/network/SwitchPort.yaml` | `openapi/components/schemas/network/DevicePort.yaml` |
| `openapi/components/schemas/network/SwitchPortLagMembership.yaml` | `openapi/components/schemas/network/DevicePortLagMembership.yaml` |
| `openapi/components/schemas/network/SwitchPortPoeMode.yaml` | `openapi/components/schemas/network/DevicePortPoeMode.yaml` |
| `openapi/components/schemas/network/SwitchPortVlanConfig.yaml` | `openapi/components/schemas/network/DevicePortVlanConfig.yaml` |
| `openapi/components/schemas/network/SwitchPortVlanMode.yaml` | `openapi/components/schemas/network/DevicePortVlanMode.yaml` |
| `openapi/components/parameters/SwitchIdFilter.yaml` | `openapi/components/parameters/DeviceIdFilter.yaml` |
| `openapi/components/parameters/SwitchPortModeFilter.yaml` | `openapi/components/parameters/DevicePortModeFilter.yaml` |

**Modified files (in addition to renames):**

| Path | Change |
|---|---|
| `openapi/components/schemas/network/DevicePort.yaml` (post-rename) | Remove `poeMode` from `required`; update `poePowerWatts` description. |
| `openapi/components/schemas/network/NetworkPort.yaml` | Rename `switch` field to `device`; update description. |
| `openapi/components/schemas/network/NetworkConnectionRef.yaml` | Update prose reference in description (`SwitchPort.connectedTo` → `DevicePort.connectedTo`). |
| `openapi/components/schemas/network/SwitchDetail.yaml` | Update `$ref` from `SwitchPort.yaml` to `DevicePort.yaml`. |
| `openapi/components/schemas/network/GatewayDetail.yaml` | Add required `ports: [DevicePort]` and `wans: [WanRef]`. |
| `openapi/components/parameters/DeviceIdFilter.yaml` (post-rename) | Rename query param `name: switchId` → `name: deviceId`; update description. |
| `openapi/paths/network-ports.yaml` | Update `$ref`s to renamed parameter files; update summary, description, example (`switch` → `device`; add gateway LAN port entry). |
| `openapi/paths/network-devices-id.yaml` | Update description; extend `gateway` example with `ports` and `wans`. |

**Not touched (out of scope):** the Go implementation repo `homelab-api`; the `hlctl` repo; `Wan.yaml`, `WanDetail.yaml`, `WanList.yaml`, and the `/network/wans*` path files (this design does not add a `port` back-reference on `Wan`).

---

## How to verify

Every task ends with `make lint`. Expected clean output:

```
$ make lint
npx --yes @redocly/cli@1.25.15 lint openapi/openapi.yaml
...
openapi/openapi.yaml: validated in <n>ms

Woohoo! Your API description is valid. 🎉

npx --yes @redocly/cli@1.25.15 bundle openapi/openapi.yaml -o dist/openapi.bundled.yaml
...
npx --yes @stoplight/spectral-cli@6.15.0 lint dist/openapi.bundled.yaml
No results with a severity of 'error' or higher found!
```

If Spectral reports an `error`, the task is not done. A single warning of `oas3-unused-component` is acceptable **only** on Task 5 (creating `WanRef.yaml` before it is referenced); every other task must produce zero warnings and zero errors.

---

## Task 1: Rename the `SwitchPort*` schema family to `DevicePort*`

**Files:**
- Rename: `openapi/components/schemas/network/SwitchPort.yaml` → `DevicePort.yaml`
- Rename: `openapi/components/schemas/network/SwitchPortLagMembership.yaml` → `DevicePortLagMembership.yaml`
- Rename: `openapi/components/schemas/network/SwitchPortPoeMode.yaml` → `DevicePortPoeMode.yaml`
- Rename: `openapi/components/schemas/network/SwitchPortVlanConfig.yaml` → `DevicePortVlanConfig.yaml`
- Rename: `openapi/components/schemas/network/SwitchPortVlanMode.yaml` → `DevicePortVlanMode.yaml`
- Modify: `openapi/components/schemas/network/DevicePort.yaml` (internal `$ref`s to sibling files)
- Modify: `openapi/components/schemas/network/DevicePortVlanConfig.yaml` (internal `$ref` to `DevicePortVlanMode.yaml`)
- Modify: `openapi/components/schemas/network/NetworkPort.yaml` ($ref + prose)
- Modify: `openapi/components/schemas/network/NetworkConnectionRef.yaml` (prose)
- Modify: `openapi/components/schemas/network/SwitchDetail.yaml` ($ref)
- Modify: `openapi/components/parameters/SwitchPortModeFilter.yaml` ($ref) — file itself is renamed in Task 3

This is a mechanical rename. To keep `make lint` green through the commit, the file renames and every incoming reference must land together in a single commit.

- [ ] **Step 1: Rename the five schema files with `git mv`**

```sh
git mv openapi/components/schemas/network/SwitchPort.yaml openapi/components/schemas/network/DevicePort.yaml
git mv openapi/components/schemas/network/SwitchPortLagMembership.yaml openapi/components/schemas/network/DevicePortLagMembership.yaml
git mv openapi/components/schemas/network/SwitchPortPoeMode.yaml openapi/components/schemas/network/DevicePortPoeMode.yaml
git mv openapi/components/schemas/network/SwitchPortVlanConfig.yaml openapi/components/schemas/network/DevicePortVlanConfig.yaml
git mv openapi/components/schemas/network/SwitchPortVlanMode.yaml openapi/components/schemas/network/DevicePortVlanMode.yaml
```

- [ ] **Step 2: Update internal `$ref`s inside `DevicePort.yaml`**

Open `openapi/components/schemas/network/DevicePort.yaml` and replace the three `$ref` values so it reads:

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
      Whether an SFP/SFP+ optical module is currently inserted.
      Omitted on ports without an SFP cage.
  poeMode:
    $ref: "./DevicePortPoeMode.yaml"
  poePowerWatts:
    allOf:
      - $ref: "../units/Watts.yaml"
    description: |
      Power currently being delivered through this port. Omitted when
      `poeMode` is `off` or when no powered device is attached.
  lagMembership:
    $ref: "./DevicePortLagMembership.yaml"
  vlanConfig:
    allOf:
      - $ref: "./DevicePortVlanConfig.yaml"
    description: |
      VLAN policy configured on this port. Omitted when the port is
      administratively disabled or when the controller does not report
      enough data to resolve the native VLAN.
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

Note: `poeMode` is still `required` at this step. Task 2 removes it and updates the prose.

- [ ] **Step 3: Update `DevicePortVlanConfig.yaml` to reference `DevicePortVlanMode.yaml`**

Open `openapi/components/schemas/network/DevicePortVlanConfig.yaml`. Change the single `$ref` on line 7 from `./SwitchPortVlanMode.yaml` to `./DevicePortVlanMode.yaml`. Everything else stays as-is.

The full file after this edit:

```yaml
type: object
description: |
  VLAN policy configured on a switch port. Omitted when the port is
  administratively disabled.
properties:
  mode:
    $ref: "./DevicePortVlanMode.yaml"
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
          Explicit allow-list of tagged VLANs. Present when `scope`
          is `custom` (may be empty if no tagged VLANs are allowed);
          omitted when `scope` is `all`.
        items:
          $ref: "./NetworkVlanRef.yaml"
    required:
      - scope
required:
  - mode
  - nativeVlan
```

- [ ] **Step 4: Update `NetworkPort.yaml` to reference `DevicePort.yaml`**

Open `openapi/components/schemas/network/NetworkPort.yaml`. Replace the `$ref` path and the prose word `SwitchPort` with `DevicePort`. Full file after edit:

```yaml
allOf:
  - $ref: "./DevicePort.yaml"
  - type: object
    description: |
      A physical switch port surfaced in the flat `/network/ports` listing.
      Inherits every field from `DevicePort` and carries a reference to its
      parent switch so consumers can audit ports across all switches in a
      single call.
    properties:
      switch:
        allOf:
          - $ref: "./NetworkDeviceRef.yaml"
        description: Reference to the switch this port belongs to.
    required:
      - switch
```

Note: the `switch` field name is renamed to `device` in Task 4, not here.

- [ ] **Step 5: Update prose in `NetworkConnectionRef.yaml`**

Open `openapi/components/schemas/network/NetworkConnectionRef.yaml`. In the description block, change `SwitchPort.connectedTo` to `DevicePort.connectedTo`. Full file after edit:

```yaml
anyOf:
  - $ref: "./NetworkDeviceRef.yaml"
  - $ref: "./NetworkClientRef.yaml"
discriminator:
  propertyName: kind
  mapping:
    device: "./NetworkDeviceRef.yaml"
    client: "./NetworkClientRef.yaml"
description: |
  Polymorphic reference to either a network device or a network client,
  discriminated on `kind`. Used wherever a single field may point at
  either resource type (e.g. `DevicePort.connectedTo`).
```

- [ ] **Step 6: Update `SwitchDetail.yaml` `$ref`**

Open `openapi/components/schemas/network/SwitchDetail.yaml`. Change the port `$ref` from `SwitchPort.yaml` to `DevicePort.yaml`. Full file after edit:

```yaml
allOf:
  - $ref: "./NetworkDeviceDetailBase.yaml"
  - type: object
    description: Detail for a managed switch, including its physical ports.
    properties:
      type:
        type: string
        enum: [switch]
      ports:
        type: array
        description: Physical ports on this switch.
        items:
          $ref: "./DevicePort.yaml"
    required:
      - type
      - ports
```

- [ ] **Step 7: Update `SwitchPortModeFilter.yaml` internal `$ref`**

Open `openapi/components/parameters/SwitchPortModeFilter.yaml`. Change the `$ref` from `../schemas/network/SwitchPortVlanMode.yaml` to `../schemas/network/DevicePortVlanMode.yaml`. Do **not** rename the file itself yet — Task 3 does that.

Full file after edit:

```yaml
name: mode
in: query
required: false
description: |
  Filter by VLAN mode. Ports without a `vlanConfig` never match.
schema:
  $ref: "../schemas/network/DevicePortVlanMode.yaml"
example: trunk
```

- [ ] **Step 8: Verify no stale references remain**

Run:

```sh
grep -rln "SwitchPort" openapi/
```

Expected: no matches (the string `SwitchPort` should not appear anywhere in `openapi/`). If any file still contains `SwitchPort`, edit it to use `DevicePort` before continuing.

- [ ] **Step 9: Run `make lint`**

```sh
make lint
```

Expected: `Your API description is valid` (Redocly) and `No results with a severity of 'error' or higher found!` (Spectral). No warnings.

- [ ] **Step 10: Commit**

```sh
git add -A openapi/
git commit -m "refactor: rename SwitchPort schema family to DevicePort"
```

---

## Task 2: Make `poeMode` optional on `DevicePort`

**Files:**
- Modify: `openapi/components/schemas/network/DevicePort.yaml`

Rationale: `poeMode: 'off'` is misleading on ports whose hardware has no PoE cage. Making the field optional lets consumers distinguish "PoE-capable, disabled" (`poeMode: 'off'`) from "no PoE hardware" (field absent).

- [ ] **Step 1: Remove `poeMode` from `required` and update `poePowerWatts` description**

Open `openapi/components/schemas/network/DevicePort.yaml`.

1. Update the `poeMode` property description to note it's omitted on ports with no PoE hardware. Change the `poeMode` block from:

```yaml
  poeMode:
    $ref: "./DevicePortPoeMode.yaml"
```

to:

```yaml
  poeMode:
    allOf:
      - $ref: "./DevicePortPoeMode.yaml"
    description: |
      Configured PoE behaviour on this port. Omitted on ports whose
      hardware has no PoE cage (typical for most gateway ports and for
      non-PoE switches).
```

2. Update the `poePowerWatts` description to reflect the new optionality of `poeMode`. Change the description text of `poePowerWatts` from:

```
Power currently being delivered through this port. Omitted when
`poeMode` is `off` or when no powered device is attached.
```

to:

```
Power currently being delivered through this port. Omitted when
`poeMode` is absent or `'off'`, or when no powered device is
attached.
```

3. Remove the `poeMode` line from the bottom `required:` list. The final `required:` block becomes:

```yaml
required:
  - number
  - state
  - traffic
```

- [ ] **Step 2: Run `make lint`**

```sh
make lint
```

Expected: valid + no errors + no warnings.

- [ ] **Step 3: Commit**

```sh
git add openapi/components/schemas/network/DevicePort.yaml
git commit -m "feat: make DevicePort.poeMode optional to distinguish no-PoE hardware from disabled PoE"
```

---

## Task 3: Rename parameter files (`SwitchIdFilter` → `DeviceIdFilter`, `SwitchPortModeFilter` → `DevicePortModeFilter`)

**Files:**
- Rename: `openapi/components/parameters/SwitchIdFilter.yaml` → `DeviceIdFilter.yaml`
- Rename: `openapi/components/parameters/SwitchPortModeFilter.yaml` → `DevicePortModeFilter.yaml`
- Modify: `openapi/components/parameters/DeviceIdFilter.yaml` (post-rename) — change `name`, update description
- Modify: `openapi/paths/network-ports.yaml` — update `$ref`s

- [ ] **Step 1: Rename parameter files**

```sh
git mv openapi/components/parameters/SwitchIdFilter.yaml openapi/components/parameters/DeviceIdFilter.yaml
git mv openapi/components/parameters/SwitchPortModeFilter.yaml openapi/components/parameters/DevicePortModeFilter.yaml
```

- [ ] **Step 2: Update `DeviceIdFilter.yaml` param name and description**

Open `openapi/components/parameters/DeviceIdFilter.yaml`. Replace the file contents with:

```yaml
name: deviceId
in: query
required: false
description: |
  Filter to ports belonging to a specific device (switch or gateway),
  matched against the composite device identifier
  (`{controller}.{name}`).
schema:
  type: string
example: "unifi.switch-living-room"
```

- [ ] **Step 3: Update `$ref`s in `network-ports.yaml`**

Open `openapi/paths/network-ports.yaml`. Change the two parameter `$ref`s (currently lines 25–26) to reference the renamed files:

```yaml
    - $ref: "../components/parameters/DeviceIdFilter.yaml"
    - $ref: "../components/parameters/DevicePortModeFilter.yaml"
```

Leave the other two `$ref`s (`NetworkPortStateFilter.yaml`, `VlanIdFilter.yaml`) unchanged. No other edits in this task.

- [ ] **Step 4: Verify no stale references remain**

```sh
grep -rln "SwitchIdFilter\|SwitchPortModeFilter" openapi/
```

Expected: no matches.

- [ ] **Step 5: Run `make lint`**

```sh
make lint
```

Expected: valid + no errors + no warnings.

- [ ] **Step 6: Commit**

```sh
git add -A openapi/
git commit -m "refactor: rename port filters to DeviceIdFilter / DevicePortModeFilter and switchId -> deviceId"
```

---

## Task 4: Rename `NetworkPort.switch` → `NetworkPort.device`

**Files:**
- Modify: `openapi/components/schemas/network/NetworkPort.yaml`
- Modify: `openapi/paths/network-ports.yaml` (example payloads: `switch:` → `device:`)

Ports in the flat `/network/ports` listing now come from switches and gateways, so the parent-ref field name changes.

- [ ] **Step 1: Rename the `switch` field to `device` in `NetworkPort.yaml`**

Open `openapi/components/schemas/network/NetworkPort.yaml`. Replace the file contents with:

```yaml
allOf:
  - $ref: "./DevicePort.yaml"
  - type: object
    description: |
      A physical device port surfaced in the flat `/network/ports`
      listing. Inherits every field from `DevicePort` and carries a
      reference to its parent device (a switch, or a gateway for
      LAN-role gateway ports) so consumers can audit ports across
      every device in a single call.
    properties:
      device:
        allOf:
          - $ref: "./NetworkDeviceRef.yaml"
        description: Reference to the device this port belongs to.
    required:
      - device
```

- [ ] **Step 2: Rename `switch:` to `device:` in every example entry in `network-ports.yaml`**

Open `openapi/paths/network-ports.yaml`. In the `typicalHomelab` example, every entry currently ends with a `switch:` block like:

```yaml
                    switch:
                      kind: device
                      id: "unifi.switch-living-room"
                      uri: "/network/devices/unifi.switch-living-room"
                      name: "Switch Living Room"
```

Change the key `switch:` to `device:` on every occurrence in this file (there are four in the current example, one per port entry). Do not change any nested values. The rest of the file is untouched in this task — the summary/description and any additional example entries are handled in Task 7.

- [ ] **Step 3: Verify the field rename by inspecting the diff**

```sh
git diff openapi/paths/network-ports.yaml | grep -E "^[-+]\s*(switch|device):"
```

Expected: matching pairs of `- switch:` and `+ device:` lines, no unmatched `-` or `+` lines for those keys.

- [ ] **Step 4: Run `make lint`**

```sh
make lint
```

Expected: valid + no errors + no warnings.

- [ ] **Step 5: Commit**

```sh
git add openapi/components/schemas/network/NetworkPort.yaml openapi/paths/network-ports.yaml
git commit -m "refactor: rename NetworkPort.switch to NetworkPort.device"
```

---

## Task 5: Create `WanRef.yaml`

**Files:**
- Create: `openapi/components/schemas/network/WanRef.yaml`

`WanRef` is a monomorphic lightweight ref used by `GatewayDetail.wans[]`. It follows the shape of `NetworkVlanRef` (no `kind` discriminator, since it's not part of a polymorphic union).

- [ ] **Step 1: Create `WanRef.yaml`**

Write to `openapi/components/schemas/network/WanRef.yaml`:

```yaml
type: object
description: Lightweight reference to a WAN interface.
properties:
  id:
    type: string
    description: Composite WAN identifier (matches `Wan.id`).
    example: "unifi.wan1"
  uri:
    type: string
    description: Relative API path to fetch this WAN's detail.
    example: "/network/wans/unifi.wan1"
  name:
    type: string
    description: Human-readable WAN interface name.
    example: "WAN 1"
required:
  - id
  - uri
  - name
```

- [ ] **Step 2: Run `make lint`**

```sh
make lint
```

Expected: Redocly valid + Spectral no errors. A single warning of `oas3-unused-component` for `WanRef.yaml` is **acceptable here only** — Task 6 wires the schema into `GatewayDetail`, at which point the warning must disappear.

- [ ] **Step 3: Commit**

```sh
git add openapi/components/schemas/network/WanRef.yaml
git commit -m "feat: add WanRef schema for lightweight WAN references"
```

---

## Task 6: Add `ports` and `wans` to `GatewayDetail`, and update the gateway example

**Files:**
- Modify: `openapi/components/schemas/network/GatewayDetail.yaml`
- Modify: `openapi/paths/network-devices-id.yaml` (description + gateway example)

Adds physical LAN switch-fabric ports and WAN-interface references to the gateway detail. Both fields are required arrays (empty `[]` when the gateway has none), matching the collection convention used elsewhere in the spec (e.g. `AccessPointDetail.connectedClients`).

- [ ] **Step 1: Extend `GatewayDetail.yaml` with `ports` and `wans`**

Open `openapi/components/schemas/network/GatewayDetail.yaml`. Replace the file contents with:

```yaml
allOf:
  - $ref: "./NetworkDeviceDetailBase.yaml"
  - type: object
    description: Detail for a security gateway / router.
    properties:
      type:
        type: string
        enum: [gateway]
      ports:
        type: array
        description: |
          Physical LAN switch-fabric ports on this gateway. WAN-role
          ports are not included here; see `wans` for the logical WAN
          interfaces this gateway exposes.
        items:
          $ref: "./DevicePort.yaml"
      wans:
        type: array
        description: |
          WAN interfaces configured on this gateway. Empty array (`[]`)
          when none, never null. Each entry is a lightweight reference;
          fetch full detail (public IP, DNS, status, uptime) from
          `/network/wans/{id}`.
        items:
          $ref: "./WanRef.yaml"
    required:
      - type
      - ports
      - wans
```

- [ ] **Step 2: Update the endpoint description in `network-devices-id.yaml`**

Open `openapi/paths/network-devices-id.yaml`. Locate the `description:` block starting at line 5 (`Returns a single network device by its composite identifier`).

Change the sentence:

```
switches include their physical `ports`, access points include `connectedClients` and `numClients`, gateways and unknown devices carry only the shared base fields.
```

to:

```
switches include their physical `ports`, access points include `connectedClients` and `numClients`, gateways include their LAN `ports` and configured `wans`, and unknown devices carry only the shared base fields.
```

Leave the rest of the `description:` block untouched.

- [ ] **Step 3: Extend the `gateway` example with `ports` and `wans`**

Open `openapi/paths/network-devices-id.yaml`. Locate the `gateway:` example (around line 200). Its current `value:` block ends with the `traffic:` block. Append `ports:` and `wans:` inside the `value:` block so the full `gateway:` example reads:

```yaml
            gateway:
              summary: The security gateway / router (root of the topology), with two LAN ports and two configured WANs.
              value:
                id: "unifi.usg"
                uri: "/network/devices/unifi.usg"
                name: "USG"
                mac: "aa:bb:cc:dd:00:01"
                ip: "192.168.1.1"
                type: gateway
                status: connected
                model: "UDM-Pro"
                firmwareVersion: "3.2.12"
                uptime: 604800
                traffic:
                  rxBytesTotal: 549755813888
                  txBytesTotal: 274877906944
                  rxBytesPerSec: 5000000
                  txBytesPerSec: 2000000
                ports:
                  - number: 1
                    label: "LAN to living room switch"
                    state: up
                    linkSpeed: gbe1
                    linkUptime: 172800
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
                      rxBytesTotal: 87960930222
                      txBytesTotal: 43980465111
                      rxBytesPerSec: 1250000
                      txBytesPerSec: 600000
                    connectedTo:
                      kind: device
                      id: "unifi.switch-living-room"
                      uri: "/network/devices/unifi.switch-living-room"
                      name: "Switch Living Room"
                  - number: 2
                    state: down
                    vlanConfig:
                      mode: access
                      nativeVlan:
                        id: "unifi.default"
                        uri: "/network/vlans/unifi.default"
                        name: "Default"
                        vlanId: 1
                    traffic:
                      rxBytesTotal: 0
                      txBytesTotal: 0
                      rxBytesPerSec: 0
                      txBytesPerSec: 0
                wans:
                  - id: "unifi.wan1"
                    uri: "/network/wans/unifi.wan1"
                    name: "WAN 1"
                  - id: "unifi.wan2"
                    uri: "/network/wans/unifi.wan2"
                    name: "WAN 2"
```

Notes on the example:
- Neither LAN port carries `poeMode` (UDM-Pro LAN ports have no PoE cage). This exercises the new optional behaviour.
- Both `wans[*]` ids match the existing WAN examples in `openapi/paths/network-wans.yaml` (`unifi.wan1`, `unifi.wan2`).

- [ ] **Step 4: Run `make lint`**

```sh
make lint
```

Expected: valid + no errors + no warnings. In particular, the `oas3-unused-component` warning from Task 5 must be gone — `WanRef.yaml` is now bundled.

- [ ] **Step 5: Commit**

```sh
git add openapi/components/schemas/network/GatewayDetail.yaml openapi/paths/network-devices-id.yaml
git commit -m "feat: expose gateway LAN ports and WAN references on GatewayDetail"
```

---

## Task 7: Broaden `/network/ports` to include gateway LAN ports (summary, description, example)

**Files:**
- Modify: `openapi/paths/network-ports.yaml`

Updates the endpoint's summary, description, and example so gateway LAN ports appear alongside switch ports. No new filters or parameters.

- [ ] **Step 1: Update the summary**

Open `openapi/paths/network-ports.yaml`. Change the `summary:` on line 4 from:

```yaml
  summary: List switch ports across all switches
```

to:

```yaml
  summary: List LAN ports across all switches and gateways
```

- [ ] **Step 2: Update the description**

Replace the `description:` block (currently lines 5–19) with:

```yaml
  description: |
    Returns physical LAN ports from every managed switch and gateway
    across all configured UniFi controllers as a single flat list. Each
    port carries a reference to its parent device so consumers can audit
    VLAN policy, PoE state, LAG membership, and connected endpoints
    without fanning out one call per device.

    Gateway LAN switch-fabric ports appear here alongside switch ports.
    WAN-role gateway ports are not included — enumerate them through
    `/network/wans` or through the `wans` array on `GatewayDetail`.

    A homelab typically has a small number of devices (each with tens of
    ports), so this endpoint returns all results without pagination.
    Result order is not guaranteed; clients should sort as needed.

    Filters are AND-composed and applied server-side; any combination is
    valid. Ports without a `vlanConfig` (either administratively disabled
    or when the controller does not report enough data to resolve the
    native VLAN) never match the `mode` or `vlanId` filters.
```

- [ ] **Step 3: Update the example summary line**

The `typicalHomelab` example currently says:

```yaml
            typicalHomelab:
              summary: One switch, four ports (trunk uplink, trunk AP downlink, idle access port, access LAG member).
```

Change it to:

```yaml
            typicalHomelab:
              summary: One switch (four ports) plus one gateway LAN port.
```

- [ ] **Step 4: Add a gateway LAN port entry to the example**

In the same file, at the end of the `items:` array under the `typicalHomelab` example (i.e., after the fourth port entry with `number: 8`), append a fifth entry for a gateway LAN port. The final entry to append (indent must match the existing entries):

```yaml
                  - number: 1
                    label: "LAN to living room switch"
                    state: up
                    linkSpeed: gbe1
                    linkUptime: 172800
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
                      rxBytesTotal: 87960930222
                      txBytesTotal: 43980465111
                      rxBytesPerSec: 1250000
                      txBytesPerSec: 600000
                    connectedTo:
                      kind: device
                      id: "unifi.switch-living-room"
                      uri: "/network/devices/unifi.switch-living-room"
                      name: "Switch Living Room"
                    device:
                      kind: device
                      id: "unifi.usg"
                      uri: "/network/devices/unifi.usg"
                      name: "USG"
```

Notes on the entry:
- No `poeMode` — gateway LAN cage without PoE, exercises the new optional behaviour from Task 2.
- `device:` block points to the gateway (`unifi.usg`), matching the gateway id used in `network-devices-id.yaml` and elsewhere.
- The trunk uplink from the gateway to the living-room switch mirrors the reciprocal trunk on switch port 1 (which reports `connectedTo: USG`) — this cross-consistency is intentional.

- [ ] **Step 5: Run `make lint`**

```sh
make lint
```

Expected: valid + no errors + no warnings.

- [ ] **Step 6: Commit**

```sh
git add openapi/paths/network-ports.yaml
git commit -m "feat: include gateway LAN ports in /network/ports listing"
```

---

## Final verification

After all seven tasks land:

- [ ] **Step 1: Confirm the full diff makes sense**

```sh
git log --oneline main..HEAD
```

Expected commit list (in order):

1. `docs: design spec for gateway LAN ports and gateway WAN references` (already on the branch)
2. `refactor: rename SwitchPort schema family to DevicePort`
3. `feat: make DevicePort.poeMode optional to distinguish no-PoE hardware from disabled PoE`
4. `refactor: rename port filters to DeviceIdFilter / DevicePortModeFilter and switchId -> deviceId`
5. `refactor: rename NetworkPort.switch to NetworkPort.device`
6. `feat: add WanRef schema for lightweight WAN references`
7. `feat: expose gateway LAN ports and WAN references on GatewayDetail`
8. `feat: include gateway LAN ports in /network/ports listing`

- [ ] **Step 2: Final lint**

```sh
make lint
```

Expected: valid + no errors + no warnings.

- [ ] **Step 3: Sanity-check no `SwitchPort`, `SwitchIdFilter`, `SwitchPortModeFilter`, or `NetworkPort.switch` references linger**

```sh
grep -rln "SwitchPort\|SwitchIdFilter\|SwitchPortModeFilter" openapi/
```

Expected: no matches.

```sh
grep -rn "^\s*switch:" openapi/paths/network-ports.yaml openapi/components/schemas/network/NetworkPort.yaml
```

Expected: no matches (all `switch:` port-parent refs have been renamed to `device:`).
