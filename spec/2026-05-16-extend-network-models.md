# Extend Network Models

## Context

Adding detail-level richness to `/network/devices` so consumers (agents, MCP tools, UIs) can answer four operational questions without follow-up calls:

1. **Switch ports.** What's plugged into each port, at what speed, with what PoE state and throughput, and is the port up?
2. **AP clients.** Which clients are associated with each access point (referenceable by URI)?
3. **Per-device traffic.** Cumulative and instantaneous rx/tx on every device (gateway, switch, AP).
4. **Topology.** What's each device's upstream connection — and on which port at which speed?

The spec is in `draft` stability across all endpoints, so breaking changes are acceptable now.

Introduces a small cross-resource **reference** pattern (`{ kind, id, uri, name }`) plus polymorphism on `NetworkDeviceDetail` (per-type variants discriminated on `type`). The same `NetworkConnection` shape models a downstream-to-upstream connection from both the device side (`uplink`) and the wired-client side (`connectedTo`).

---

## Cross-resource references

Three new reference schemas. The bare refs always carry a `kind` discriminator (cheap, makes refs self-identifying, enables polymorphism on switch-port `connectedTo`).

**`NetworkDeviceRef.yaml`** — `{ kind: "device", id, uri, name }`. Required fields all four. `uri` is the relative API path (e.g. `/network/devices/unifi.ap-living-room`).

**`NetworkClientRef.yaml`** — `{ kind: "client", id, uri, name }`. Same shape, different discriminator.

**`NetworkConnectionRef.yaml`** — polymorphic wrapper used only by `SwitchPort.connectedTo`:

```yaml
anyOf:
  - $ref: "./NetworkDeviceRef.yaml"
  - $ref: "./NetworkClientRef.yaml"
discriminator:
  propertyName: kind
  mapping:
    device: "./NetworkDeviceRef.yaml"
    client: "./NetworkClientRef.yaml"
```

---

## Traffic stats

**`NetworkTraffic.yaml`** — reusable block, embedded as `traffic:` on every device-detail variant and on every switch port.

- `rxBytesTotal` — `allOf Bytes` — cumulative since current uptime (resets on device reboot)
- `txBytesTotal` — `allOf Bytes`
- `rxBytesPerSec` — `allOf BytesPerSec` — current throughput
- `txBytesPerSec` — `allOf BytesPerSec`
- All four required.

Counter semantics: "since current uptime started." Documented in the schema description. No persisted lifetime totals.

---

## Switch port

**`SwitchPort.yaml`**:

- `number` — `integer`, `minimum: 1`. Physical port number as labelled on the switch.
- `state` — `$ref NetworkPortState`. Required.
- `linkSpeed` — `$ref NetworkLinkSpeed`. Omitted when `state` ≠ `up`.
- `poeMode` — `$ref SwitchPortPoeMode`. Required.
- `poePowerWatts` — `allOf units/Watts`. Omitted when `poeMode == off` or no powered device attached.
- `traffic` — `$ref NetworkTraffic`. Required.
- `connectedTo` — `$ref NetworkConnectionRef`. Omitted when nothing plugged in. When an unmanaged downstream switch hangs off the port with multiple endpoints, the controller picks one endpoint to report (UniFi behavior); the schema description must call this out so consumers don't treat it as authoritative for multi-endpoint cases.

### Supporting enums (new)

**`NetworkPortState.yaml`** — `enum: [up, down, disabled]`.

**`NetworkLinkSpeed.yaml`** — UniFi nomenclature:

- `e` — 10 Mbps
- `fe` — 100 Mbps
- `gbe1` — 1 Gbps
- `gbe2_5` — 2.5 Gbps
- `gbe5` — 5 Gbps
- `gbe10` — 10 Gbps

**`SwitchPortPoeMode.yaml`** — `enum: [off, auto, passive24v, passthrough]`. PoE+/PoE++ are runtime negotiation outcomes of `auto`, not configurable modes; deliberately not modelled in this round (see Out of scope).

### Supporting unit (new)

**`units/Watts.yaml`** — `type: number`, `format: float`, `minimum: 0`. Watts can be fractional (UniFi reports e.g. `4.5 W`).

---

## Connections (downstream → upstream)

One reusable schema for the rich connection shape, used wherever a downstream entity points to its upstream device + port + link speed.

**`NetworkConnection.yaml`**:

- `device` — `$ref NetworkDeviceRef`. The upstream device. **Required.**
- `port` — `integer`, `minimum: 1`. Physical port number on the upstream device. **Optional.**
- `linkSpeed` — `$ref NetworkLinkSpeed`. Negotiated speed. **Optional.**

Only `device` is required. `port` and `linkSpeed` are present when the connection is live (online client, connected device) and omitted when only the upstream reference is known (e.g. offline wired client where the controller retains the last known switch but not the last port). This preserves "last known device" semantics from PR #10 (status field).

Used by:

- `NetworkDeviceDetailBase.uplink` (field name `uplink`, omitted for gateways)
- `WiredNetworkClientDetail.connectedTo` (field name `connectedTo`)

Field names differ because the domain phrasing differs (devices have an "uplink", clients "connect to" something), but the structure is one schema. Including `linkSpeed` on the wired-client side too is intentional: a NAS plugged into a 1 Gbps port instead of a 2.5 Gbps port is the same gotcha at both layers.

**`WirelessConnection.yaml`** — wireless analog (no port, no link speed; has SSID and signal strength):

- `device` — `$ref NetworkDeviceRef`. The AP. **Required.**
- `ssid` — `string`. SSID the client is associated with. **Required.** (Generally retained as last known when client is offline.)
- `signalStrength` — `integer`. dBm as measured by the AP. **Optional** — absent for offline clients (no live measurement).

Used by `WirelessNetworkClientDetail.connectedTo`.

---

## Polymorphic device detail

Replace the flat `NetworkDeviceDetail` with a polymorphic wrapper over per-type variants. Per-type fields move out of the list shape and into the variant they actually apply to.

### List shape

**`NetworkDevice.yaml`** changes:

- **Add** `uri` (required) — relative API path to detail.
- **Remove** `numClients` — AP-only field; moves to `AccessPointDetail`.

Other fields (`id`, `name`, `mac`, `ip`, `type`, `status`) unchanged.

### Detail base

**`NetworkDeviceDetailBase.yaml`** — `allOf NetworkDevice +`:

- `model` — string. Required.
- `firmwareVersion` — string. Required.
- `uptime` — integer (seconds since (re)connection). Required.
- `traffic` — `$ref NetworkTraffic`. Required.
- `uplink` — `$ref NetworkConnection`. Optional; omitted for gateways.

### Per-type variants

**`SwitchDetail.yaml`** — `allOf NetworkDeviceDetailBase +`:

- `type` — `enum [switch]` (pinned).
- `ports` — `array` of `$ref SwitchPort`. Required.

**`AccessPointDetail.yaml`** — `allOf NetworkDeviceDetailBase +`:

- `type` — `enum [accessPoint]` (pinned).
- `numClients` — integer. Required. Number of associated wireless clients.
- `connectedClients` — `array` of `$ref AccessPointClient`. Required (empty array `[]` when no clients).

**`GatewayDetail.yaml`** — `allOf NetworkDeviceDetailBase +`:

- `type` — `enum [gateway]` (pinned).
- No extra fields in this round. WAN port info deferred (see Out of scope).

**`UnknownDeviceDetail.yaml`** — `allOf NetworkDeviceDetailBase +`:

- `type` — `enum [unknown]` (pinned).
- No extra fields. Exists so the discriminator maps every value in `NetworkDeviceType`.

### Polymorphic wrapper

**`NetworkDeviceDetail.yaml`** (replaces the existing flat schema):

```yaml
anyOf:
  - $ref: "./SwitchDetail.yaml"
  - $ref: "./AccessPointDetail.yaml"
  - $ref: "./GatewayDetail.yaml"
  - $ref: "./UnknownDeviceDetail.yaml"
discriminator:
  propertyName: type
  mapping:
    switch: "./SwitchDetail.yaml"
    accessPoint: "./AccessPointDetail.yaml"
    gateway: "./GatewayDetail.yaml"
    unknown: "./UnknownDeviceDetail.yaml"
```

### AP-side client association

**`AccessPointClient.yaml`** — symmetric mirror of `WirelessConnection`, but pointing at the client:

- `client` — `$ref NetworkClientRef`. Required.
- `ssid` — string. Required.
- `signalStrength` — integer (dBm). Required.

The same association data is reachable from both sides: from the AP via `connectedClients[].client`, from the client via `connectedTo.device`. Both carry `ssid` and `signalStrength`.

---

## Updates to `NetworkClient`

### List shape

**`NetworkClient.yaml`** — add `uri` (required). All other fields (including the `status: online | offline` added by PR #10) are preserved.

### Wired detail (breaking)

**`WiredNetworkClientDetail.yaml`** — replace `switchName: string` and `switchPort: integer` with a single `connectedTo: $ref NetworkConnection`. The "last known switch" semantics from PR #10 are preserved through `connectedTo.device` (required) while `port` and `linkSpeed` inside `NetworkConnection` are optional (absent for offline clients).

Resulting required fields on the detail: `connectionType`, `connectedTo`. `uptime` is optional (matches PR #10's offline handling — session-specific, absent when offline).

### Wireless detail (breaking)

**`WirelessNetworkClientDetail.yaml`** — group `ssid` and `signalStrength` (previously top-level) into a new `connectedTo: $ref WirelessConnection`. The "last known AP" semantics from PR #10 are preserved through `connectedTo.device` and `connectedTo.ssid` (both required). `signalStrength` inside `WirelessConnection` is optional (absent for offline clients).

Resulting required fields on the detail: `connectionType`, `connectedTo`. `uptime` is optional.

---

## Guidelines + lint

### `API_GUIDELINES.md`

Extend the **Naming** section with a clarification for enum values:

> **Enum value naming:** `camelCase`, with one exception — when an enum value encodes a numeric quantity (`<unit><value>`), an underscore is allowed *between two digits* to encode a decimal point. Example: `gbe2_5` for 2.5 Gbps. The `_` is permitted only between two digits; everywhere else, the value must remain camelCase.

### `.spectral.yaml`

New rule `enum-value-camelcase` (regex permits the digit-underscore-digit decimal exception):

```yaml
enum-value-camelcase:
  description: |
    Enum values must be camelCase. A single underscore is allowed only
    between two digits (to encode a decimal point in numeric enums, e.g.
    `gbe2_5`).
  message: "Enum value '{{value}}' must be camelCase (with `_` allowed only between digits)."
  severity: error
  given: "$..enum[*]"
  then:
    function: pattern
    functionOptions:
      match: "^[a-z][a-zA-Z0-9]*(?:[0-9]_[0-9][a-zA-Z0-9]*)?$"
```

Before adopting, verify no existing enum values in the bundled spec fail the new pattern. Fix any that do in the same change set.

---

## Endpoint changes

No new endpoints; no new paths in `openapi.yaml`. The two detail endpoints continue to reference `$ref NetworkDeviceDetail` / `$ref NetworkClientDetail`, which now point at the polymorphic wrappers. Path-file changes are limited to `example:` blocks:

- `paths/network-devices.yaml` — examples include `uri` per item; AP entries no longer carry `numClients`.
- `paths/network-devices-id.yaml` — one example per variant (switch, AP, gateway, unknown), each showing the relevant per-type fields.
- `paths/network-clients.yaml` — examples include `uri` per item.
- `paths/network-clients-id.yaml` — wired example uses `connectedTo: NetworkConnection`; wireless example uses `connectedTo: WirelessConnection`.

---

## Files

### New schemas

- `openapi/components/schemas/NetworkDeviceRef.yaml`
- `openapi/components/schemas/NetworkClientRef.yaml`
- `openapi/components/schemas/NetworkConnectionRef.yaml`
- `openapi/components/schemas/NetworkConnection.yaml`
- `openapi/components/schemas/WirelessConnection.yaml`
- `openapi/components/schemas/NetworkTraffic.yaml`
- `openapi/components/schemas/SwitchPort.yaml`
- `openapi/components/schemas/NetworkLinkSpeed.yaml`
- `openapi/components/schemas/NetworkPortState.yaml`
- `openapi/components/schemas/SwitchPortPoeMode.yaml`
- `openapi/components/schemas/NetworkDeviceDetailBase.yaml`
- `openapi/components/schemas/SwitchDetail.yaml`
- `openapi/components/schemas/AccessPointDetail.yaml`
- `openapi/components/schemas/GatewayDetail.yaml`
- `openapi/components/schemas/UnknownDeviceDetail.yaml`
- `openapi/components/schemas/AccessPointClient.yaml`
- `openapi/components/schemas/units/Watts.yaml`

### Updated schemas

- `openapi/components/schemas/NetworkDevice.yaml` — add `uri`, remove `numClients`.
- `openapi/components/schemas/NetworkClient.yaml` — add `uri`.
- `openapi/components/schemas/NetworkDeviceDetail.yaml` — replace flat `allOf` shape with polymorphic `anyOf` wrapper.
- `openapi/components/schemas/WiredNetworkClientDetail.yaml` — replace `switchName` + `switchPort` with `connectedTo: NetworkConnection`.
- `openapi/components/schemas/WirelessNetworkClientDetail.yaml` — move `ssid` + `signalStrength` under `connectedTo: WirelessConnection`.

### Updated paths

- `openapi/paths/network-devices.yaml` — examples only.
- `openapi/paths/network-devices-id.yaml` — examples (one per variant).
- `openapi/paths/network-clients.yaml` — examples only.
- `openapi/paths/network-clients-id.yaml` — examples updated for new shapes.

### Updated docs and tooling

- `API_GUIDELINES.md` — enum naming exception.
- `.spectral.yaml` — new `enum-value-camelcase` rule.

---

## Breaking changes

1. `NetworkDeviceDetail` becomes polymorphic (anyOf over four variants). Consumers reading a flat shape must dispatch on `type`.
2. `NetworkDevice` (list) loses `numClients`. Moves to `AccessPointDetail`.
3. `WiredNetworkClientDetail` loses `switchName` and `switchPort`; gains `connectedTo: NetworkConnection`.
4. `WirelessNetworkClientDetail` loses top-level `ssid` and `signalStrength`; gains `connectedTo: WirelessConnection` containing both.

`make breaking BASE=origin/main` (oasdiff) will flag these. The `homelab-api` implementation repo needs a matching update once this lands.

---

## Out of scope

Deferred for separate spec(s) when needed:

- Gateway WAN info (per-interface throughput, public IP, WAN link state).
- Per-radio AP info (2.4/5/6 GHz channels, utilization, tx power).
- VLAN tagging and port profiles on switch ports.
- LACP / link aggregation.
- Per-switch PoE budget (total available / consumed watts).
- `poeStandard` runtime field (negotiated 802.3af/at/bt class).
- Historical / time-series traffic — instantaneous + cumulative only.
