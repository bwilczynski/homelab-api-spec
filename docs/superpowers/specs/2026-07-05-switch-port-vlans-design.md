# Design: Per-Port VLAN Policy and Dashboard Fields for Switch Ports

**Date:** 2026-07-05
**Status:** Draft

## Context

`GET /network/devices/{deviceId}` returns a `SwitchDetail` variant whose `ports[]` describe each physical port on a managed switch. Today, a port carries link/PoE/traffic information and a reference to what is connected on the other end, but nothing about its VLAN policy — a dashboard cannot show which VLAN a port is on, whether it is an access or trunk port, or which tagged VLANs a trunk carries.

A few adjacent per-port fields that a homelab operator inspecting a switch would routinely want are also missing: an operator-assigned port label, SFP module presence on fiber cages, current link uptime, and link-aggregation (LAG) membership.

This design extends the existing `SwitchPort` schema with:

1. A `vlan` sub-object modeling the port's VLAN policy.
2. Four additional optional dashboard-oriented fields (`label`, `sfpModulePresent`, `linkUptime`, `lag`).

The endpoint is `x-stability-level: draft`; all additions are optional, and no existing field or requirement changes. As a small consistency cleanup that falls out of introducing the new `linkUptime` field, three pre-existing inline `uptime: integer` fields elsewhere in the `network` domain switch to the shared `units/Seconds.yaml` schema.

## Use case

The primary consumer is a dashboard/inspection view — a UI that renders "what is each port doing right now" so a human can understand the switch at a glance. This shapes:

- Preferring resolvable references (`NetworkVlanRef` with `id`, `uri`, `name`, `vlanId`) over raw numeric tags, so the UI can render human names and deep-link to the VLAN detail endpoint.
- Preferring an explicit `mode: access | trunk` discriminator over shape-inference, so the UI has a single field to switch layouts on.
- Adding fields that answer routine visual questions (labeled ports, fiber modules, LAG grouping) rather than deep-troubleshooting fields (STP state, dot1x, port security).

## Schema Design

### New: `NetworkVlanRef`

A lightweight reference to a VLAN, matching the existing `NetworkDeviceRef` / `NetworkClientRef` pattern.

```yaml
type: object
description: Lightweight reference to a VLAN.
properties:
  id:
    type: string
    description: Composite VLAN identifier (matches Vlan.id).
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
required: [id, uri, name, vlanId]
```

Rationale for including both `id` and `vlanId`:

- `id` is the composite `{controller}.{name}` identifier used to fetch VLAN detail via `/network/vlans/{vlanId}`.
- `vlanId` is the numeric 802.1Q tag humans and network gear speak in.

Both are cheap to include; each answers a distinct question a dashboard asks.

### New: `SwitchPortVlanConfig`

The per-port VLAN policy, referenced from `SwitchPort.vlan`. Modeling notes follow the schema.

```yaml
type: object
description: |
  VLAN policy configured on this port. Present when the port is not
  administratively disabled (`state != disabled`).
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
    $ref: "./NetworkVlanRef.yaml"
    description: The untagged VLAN carried on this port.
  taggedVlans:
    type: object
    description: |
      Tagged VLANs allowed on this port. Present only when `mode` is `trunk`.
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
    required: [scope]
required: [mode, nativeVlan]
```

Design notes:

- **Two modes, not four.** Port admin-state (`disabled`) is already carried on `SwitchPort.state`; overloading `vlan.mode` with a `disabled` value would duplicate the same fact. When `state: disabled`, the `vlan` sub-object is omitted entirely.
- **`taggedVlans` uses a nested `scope` + `items`** rather than a polymorphic `oneOf: [string, array]`. Two enums are easier to render, easier to validate, and OpenAPI 3.0 handles this shape cleanly.
- **`taggedVlans.scope: all` with no `items`** represents a trunk allowing every VLAN currently configured on the switch — the natural encoding for `forward: "all"` and for `forward: "customize"` with an empty exclusion list.

### Extensions to `SwitchPort`

Five new optional fields on `SwitchPort` (existing fields unchanged: `number`, `state`, `linkSpeed`, `poeMode`, `poePowerWatts`, `traffic`, `connectedTo`).

```yaml
label:
  type: string
  description: |
    Operator-assigned port label. Omitted when the port uses the
    controller's default label (`Port N`).
  example: "Backhaul to attic"

sfpModulePresent:
  type: boolean
  description: |
    Whether an SFP/SFP+ optical module is currently inserted in this
    port's fiber cage. Present only on ports with an SFP cage;
    omitted on RJ45-only ports.

linkUptime:
  allOf:
    - $ref: "../units/Seconds.yaml"
  description: |
    Seconds since the current link came up. Present only when
    `state` is `up`; resets on link flap.

lag:
  type: object
  description: |
    Link-aggregation membership. Present only when this port
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
  required: [id, role]

vlan:
  allOf:
    - $ref: "./SwitchPortVlanConfig.yaml"
  description: |
    VLAN policy configured on this port. Omitted when `state` is
    `disabled` (the port carries no traffic), or when the controller
    does not report enough data to resolve the native VLAN.
```

All five are optional. None becomes required, so consumers written against the current spec keep working unchanged.

### Consistency cleanup: retrofit inline `uptime` to `Seconds`

Three network-domain schemas define `uptime` as an inline `type: integer` instead of referencing the shared `units/Seconds.yaml`:

- `NetworkDeviceDetailBase.yaml` — device uptime
- `WiredNetworkClientDetail.yaml` — client session uptime
- `WirelessNetworkClientDetail.yaml` — client session uptime

Each converts to the `allOf: [$ref: "../units/Seconds.yaml"]` pattern already used by `Wan.uptime` and required by the CLAUDE.md "unit schemas" convention. `Seconds.yaml` is `type: integer`, so the wire type is unchanged — this is a non-breaking spec cleanup grouped into the same PR because `linkUptime` on `SwitchPort` establishes the same pattern.

## Mapping rules (UniFi controller → API)

The service layer normalizes the four UniFi port combinations into the API's two-mode representation. Captured from a real UniFi OS controller (`scripts/responses/unifi-devices-os-raw.json` and `unifi-networkconf-os-raw.json`), the mapping is:

### VLAN policy

| UniFi `port_table` fields                                             | API `vlan` value                                                                       |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `forward: "native"` + `tagged_vlan_mgmt: "block_all"`                  | `mode: access`, `nativeVlan: <ref to native_networkconf_id>`                            |
| `forward: "all"`                                                      | `mode: trunk`, `taggedVlans: { scope: all }`, `nativeVlan: <switch default network>`   |
| `forward: "customize"` + `excluded_networkconf_ids: []`                | `mode: trunk`, `taggedVlans: { scope: all }` (semantically equivalent)                  |
| `forward: "customize"` + `excluded_networkconf_ids: [id1, id2, ...]`   | `mode: trunk`, `taggedVlans: { scope: custom, items: <all VLANs minus excluded> }`     |
| `forward: "disable"`                                                  | `state: disabled` on `SwitchPort`; `vlan` omitted                                       |

The `native_networkconf_id` and each `excluded_networkconf_ids[i]` are UniFi controller ObjectIDs. The adapter resolves them against the controller's `networkconf` collection (`purpose: corporate` entries) into `NetworkVlanRef` values whose `id`/`uri`/`name`/`vlanId` mirror the `/network/vlans/{vlanId}` resource.

For `forward: "all"` ports, the raw `port_table` entry reports `native_networkconf_id: null`; the native VLAN falls back to the switch-level default network (the `networkconf` entry with `purpose: corporate` and no `vlan` tag, or explicitly marked as default). If no such default can be resolved (rare — misconfigured or partial controller data), the adapter omits the entire `vlan` sub-object on that port rather than emitting a partially populated one.

### Additional port fields

| UniFi field                                       | API field on `SwitchPort`                          |
| ------------------------------------------------- | -------------------------------------------------- |
| `name` (when different from `Port <port_idx>`)    | `label`                                            |
| `sfp_found`                                       | `sfpModulePresent`                                 |
| `uptime` (port-level, when `up: true`)            | `linkUptime`                                       |
| `aggregated_by: false` on a port with downstream members | `lag: { id: <port_idx>, role: master }`      |
| `aggregated_by: <master_port_idx>`                | `lag: { id: <master_port_idx>, role: member }`     |

## Example

Updated switch example in `paths/network-devices-id.yaml` (other variants unchanged):

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
    traffic: { ... }
    uplink: { ... }
    ports:
      - number: 1
        state: up
        linkSpeed: gbe1
        poeMode: 'off'
        linkUptime: 172800
        traffic: { ... }
        connectedTo: { kind: device, id: "unifi.usg", uri: "/network/devices/unifi.usg", name: "USG" }
        vlan:
          mode: trunk
          nativeVlan:
            id: "unifi.default"
            uri: "/network/vlans/unifi.default"
            name: "Default"
            vlanId: 1
          taggedVlans:
            scope: all
      - number: 7
        state: up
        linkSpeed: gbe2_5
        poeMode: auto
        poePowerWatts: 4.5
        label: "AP Living Room uplink"
        linkUptime: 86400
        traffic: { ... }
        connectedTo: { kind: device, id: "unifi.ap-living-room", uri: "/network/devices/unifi.ap-living-room", name: "AP Living Room" }
        vlan:
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
      - number: 2
        state: down
        poeMode: 'off'
        traffic: { ... }
        vlan:
          mode: access
          nativeVlan:
            id: "unifi.servers"
            uri: "/network/vlans/unifi.servers"
            name: "Servers"
            vlanId: 100
      - number: 8
        state: up
        linkSpeed: gbe2_5
        poeMode: 'off'
        sfpModulePresent: true
        linkUptime: 3600
        lag: { id: 8, role: master }
        traffic: { ... }
        connectedTo: { kind: client, id: "unifi.nas-1-68", uri: "/network/clients/unifi.nas-1-68", name: "nas-1" }
        vlan:
          mode: access
          nativeVlan:
            id: "unifi.servers"
            uri: "/network/vlans/unifi.servers"
            name: "Servers"
            vlanId: 100
```

## Files touched

**New:**

- `openapi/components/schemas/network/NetworkVlanRef.yaml`
- `openapi/components/schemas/network/SwitchPortVlanConfig.yaml`

**Modified:**

- `openapi/components/schemas/network/SwitchPort.yaml` — adds `label`, `sfpModulePresent`, `linkUptime`, `lag`, `vlan` (all optional)
- `openapi/components/schemas/network/NetworkDeviceDetailBase.yaml` — `uptime` → `Seconds` ref
- `openapi/components/schemas/network/WiredNetworkClientDetail.yaml` — `uptime` → `Seconds` ref
- `openapi/components/schemas/network/WirelessNetworkClientDetail.yaml` — `uptime` → `Seconds` ref
- `openapi/paths/network-devices-id.yaml` — switch example updated with the new fields

## Compatibility and versioning

- `GET /network/devices/{deviceId}` is `x-stability-level: draft`; per `API_GUIDELINES.md`, changes on draft endpoints do not need a `BREAKING CHANGE` footer even when they would otherwise qualify.
- No fields are removed or renamed. All new fields on `SwitchPort` are optional. Existing consumers ignore them.
- The `uptime` retrofit swaps an inline `type: integer` for a `$ref` to `units/Seconds.yaml`, itself `type: integer` — the wire type is unchanged.
- Suggested commit prefix: `feat:` (minor bump), e.g. `feat: add per-port VLAN policy and dashboard fields to switch ports`.

## Out of scope

- **Impl PR in `homelab-api` (Go).** The adapter (`internal/adapters/unifi.go` `UniFiPortEntry`) needs to gain the missing UniFi fields (`name`, `forward`, `native_networkconf_id`, `tagged_vlan_mgmt`, `excluded_networkconf_ids`, `sfp_found`, `aggregated_by`, per-port `uptime`) and the service layer (`internal/network/devices_service.go` `buildSwitchPorts`) needs to be passed a VLAN lookup map and apply the mapping table above. Landing after this spec change ships.
- **Access-point port VLANs.** APs also expose port info; not covered here.
- **STP state, port isolation, 802.1X, port security, storm control.** Not needed for the current dashboard/inspection use case. Straightforward to add later as optional fields without breaking changes.
- **Voice VLAN (`voice_networkconf_id`).** Present in UniFi's data but empty in every captured port; deferred until a real use case emerges.
