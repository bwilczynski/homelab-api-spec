# Gateway LAN ports and gateway WAN references — design

## Problem

`/network/ports` and `SwitchDetail` today only surface ports from managed
switches. Gateways (security gateways / routers) have a built-in LAN
switch fabric that carries client and downstream-device traffic just like
a standalone switch — but those ports are invisible in the current spec.
A consumer that wants to audit VLAN policy, link state, PoE draw, or
downstream connectivity across the whole homelab has to fan out per
resource and reconstruct the picture by hand.

Separately, `GatewayDetail` doesn't tell a consumer which logical WAN
interfaces live on this gateway. `/network/wans` lists WANs globally,
but there's no "which WANs belong to this gateway" join without
inspecting every WAN by hand.

## Scope

- Rename port schemas from `SwitchPort*` to `DevicePort*` so both switches
  and gateways share the same port model.
- Add `ports` to `GatewayDetail` for the gateway's **LAN** switch-fabric
  ports, using the same `DevicePort` schema switches use.
- Broaden `/network/ports` to return LAN-side ports from switches **and**
  gateways as a single flat list. WAN-role gateway ports are **not**
  included; `/network/wans` remains the source of truth for WAN
  interfaces.
- Add `wans: [WanRef]` to `GatewayDetail` so a consumer can enumerate a
  gateway's WAN interfaces without fanning out to `/network/wans`.
- Make `poeMode` optional so ports without a PoE cage don't misreport
  `off`.

Out of scope:

- Modelling WAN-role physical ports as `DevicePort` entries. WANs stay
  a logical resource under `/network/wans`.
- Any port ↔ WAN cross-link at the physical port level (no `wan` field
  on `DevicePort`, no `port` field on `Wan`).
- LAG-bonded WAN modelling.
- Modelling upstream ISP devices (modems / ONTs). `connectedTo` remains
  free for that in the future.
- New endpoints. All changes are additive on existing paths, plus renames.

## Schema changes

### Renames

Both the file basename and every internal reference are renamed. Basenames
must stay unique across `openapi/components/**` per repo guidelines.

| From | To |
|---|---|
| `components/schemas/network/SwitchPort.yaml` | `components/schemas/network/DevicePort.yaml` |
| `components/schemas/network/SwitchPortLagMembership.yaml` | `components/schemas/network/DevicePortLagMembership.yaml` |
| `components/schemas/network/SwitchPortPoeMode.yaml` | `components/schemas/network/DevicePortPoeMode.yaml` |
| `components/schemas/network/SwitchPortVlanConfig.yaml` | `components/schemas/network/DevicePortVlanConfig.yaml` |
| `components/schemas/network/SwitchPortVlanMode.yaml` | `components/schemas/network/DevicePortVlanMode.yaml` |
| `components/parameters/SwitchIdFilter.yaml` | `components/parameters/DeviceIdFilter.yaml` |
| `components/parameters/SwitchPortModeFilter.yaml` | `components/parameters/DevicePortModeFilter.yaml` |

### `DevicePort` field changes (relative to today's `SwitchPort`)

- `poeMode` becomes **optional**. Present only when the port has a PoE
  cage; omitted when the hardware has no PoE support (typical for most
  gateway ports). Consumers can now distinguish "PoE-capable but disabled"
  (`poeMode: 'off'`) from "no PoE hardware" (field absent).
- `poePowerWatts` description updated: "omitted when `poeMode` is absent
  or `'off'`, or when no powered device is attached."

Everything else (`number`, `label`, `state`, `linkSpeed`, `linkUptime`,
`sfpModulePresent`, `lagMembership`, `vlanConfig`, `traffic`,
`connectedTo`) is unchanged in shape and semantics. `DevicePort` carries
no WAN- or role-specific fields; it is exactly a LAN-side switch-fabric
port, whether hosted by a switch or by a gateway.

### `NetworkPort` field change

- `switch: NetworkDeviceRef` renamed to `device: NetworkDeviceRef`. Same
  ref shape; the new name reflects that ports can now belong to switches
  or gateways.

### New schema

**`components/schemas/network/WanRef.yaml`**

Follows the monomorphic ref shape used by `NetworkVlanRef` (no `kind`
discriminator, since this ref isn't used inside a polymorphic union).

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

### `GatewayDetail` additions

- New required `ports: [DevicePort]`. Physical LAN switch-fabric ports on
  the gateway, using the same schema switches use. WAN-role ports are
  **not** included. Empty array when the gateway reports no LAN ports;
  never null.
- New required `wans: [WanRef]`. WAN interfaces configured on this
  gateway. Empty array when no WANs are configured; never null. Consumers
  dereference each ref via `/network/wans/{id}` for full detail (public
  IP, DNS, status, uptime).

### `SwitchDetail`

- `ports` field now references `DevicePort` instead of `SwitchPort`
  (mechanical rename; no semantic change).

### `Wan`

- No changes. `Wan` still lives at `/network/wans` and does not gain a
  physical-port back-reference.

## Endpoint changes

### `/network/ports`

- **Summary**: `List switch ports across all switches` → `List LAN ports
  across all switches and gateways`.
- **Description**: rewritten to state that both switch-hosted ports and
  gateway LAN switch-fabric ports are returned. Explicitly notes that
  WAN-role gateway ports are excluded and that `/network/wans` is the
  source of truth for WAN interfaces. Preserves the existing filter
  semantics: `mode` and `vlanId` never match ports without a `vlanConfig`
  (still covers administratively-disabled ports).
- **Operation ID**: unchanged (`listNetworkPorts`).
- **Parameters**: `switchId` → `deviceId`; `mode` renamed at the file
  level to `DevicePortModeFilter.yaml`; `state` and `vlanId` unchanged.
  No new filters.
- **Examples**: extend the existing `typicalHomelab` example so it
  includes at least one gateway LAN-port entry alongside the switch
  entries. The gateway entry has `device` (not `switch`) pointing at the
  gateway. Rename `switch` → `device` on every existing entry.

### `/network/devices/{deviceId}`

- **Description**: note that gateways now include a `ports` array (LAN
  switch-fabric ports only) and a `wans` array (references to WAN
  interfaces on this gateway).
- **Example**: extend the existing `gateway` example under `examples:`
  with a `ports:` array (a couple of LAN ports, one connected downstream
  to the switch) and a `wans:` array (at least one `WanRef` pointing at
  WAN 1).

### `/network/wans` and `/network/wans/{wanId}`

- No changes.

### Root document

`openapi/openapi.yaml` needs no change.

## Filters on `/network/ports` — final set

| Filter | Change | Notes |
|---|---|---|
| `deviceId` (from `SwitchIdFilter.yaml`) | Rename | "Filter to ports belonging to a specific device (switch or gateway)." |
| `mode` (from `SwitchPortModeFilter.yaml`) | Rename only | Description unchanged in substance: ports without `vlanConfig` never match. |
| `state` (`NetworkPortStateFilter.yaml`) | No change | |
| `vlanId` (`VlanIdFilter.yaml`) | No change | |

No `role`, `deviceType`, or `wanId` filter — WAN ports are excluded from
this listing, so no filter needs to discriminate them.

## Cross-endpoint invariants

- Any `WanRef` in `GatewayDetail.wans` must correspond to an existing
  `Wan` at `/network/wans/{id}`. Example payloads must agree with the
  `/network/wans/*` examples on `id` / `name`.
- `DevicePort` entries in `GatewayDetail.ports` are LAN switch-fabric
  ports only. WAN uplinks never appear here.

The spec cannot lint the first invariant end-to-end (it crosses
endpoints), but examples in `/network/devices/{deviceId}` and
`/network/wans/*` must be internally consistent.

## Stability and versioning

Every affected endpoint (`/network/ports`, `/network/devices/{deviceId}`)
is `x-stability-level: draft`. Per repo release rules:

- Renames (`switch` → `device`, `SwitchPort*` → `DevicePort*`,
  `switchId` → `deviceId`) do **not** require a `BREAKING CHANGE` footer.
- Making `poeMode` optional does **not** require a `BREAKING CHANGE`
  footer.
- Additions to `GatewayDetail` (`ports`, `wans`) are additive on a draft
  endpoint.
- The change lands as a single `feat:` commit (minor SemVer bump). Do not
  edit `info.version` by hand — semantic-release handles it.

## Verification

- `make lint` (Redocly on source, Spectral on bundled) must pass.
- Manually spot-check that the WAN entries in the updated
  `/network/devices/{deviceId}` gateway example match the existing
  `/network/wans/*` examples on `id`, `uri`, and `name`.
- No `make breaking` / `oasdiff` run — hand-check the diff for breaking
  intent. All endpoints are draft, so the CI breaking-changes job ignores
  them regardless.

## Non-goals

- No physical modelling of WAN ports. WANs stay at `/network/wans` as
  logical resources; gateway detail exposes them via `WanRef`.
- No port ↔ WAN cross-link at the port level. `DevicePort` carries no
  `wan` field; `Wan` carries no `port` field.
- No modelling of upstream ISP devices. `connectedTo` on any port stays
  available for a future modem / ONT variant.
- No new endpoint. No `/network/ports/{portId}` and no `wanId` filter.
- No polymorphism split between switch ports and gateway ports. They are
  the same shape (`DevicePort`).
