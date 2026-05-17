# Network Topology Endpoint

## Context

The existing spec encodes topology implicitly: each device detail carries an `uplink` (`NetworkConnection`) and each client detail carries a `connectedTo` (`NetworkConnection` or `WirelessConnection`). Reconstructing the full graph requires N+1 calls. This endpoint materialises the topology in a single response, purpose-built for graph rendering and agent consumption.

---

## Endpoint

```
GET /network/topology
```

- **Group / resource:** `network` / `topology` — singleton resource, no `{id}` variant.
- **operationId:** `getNetworkTopology`
- **Scope:** `read:network`
- **Query parameter:** `includeClients` (boolean, optional, default `false`). When `false`, only infrastructure devices appear. When `true`, all network clients (online and offline) are added as nodes with corresponding edges.
- **Responses:** `200 NetworkTopology`, `401 Unauthorized`, `429 TooManyRequests`, `500 InternalServerError`. No `404` — an empty network returns `{ nodes: [], edges: [] }`.

---

## Response shape

```
NetworkTopology
├── nodes: TopologyNode[]
└── edges: TopologyEdge[]
```

`TopologyNode` and `TopologyEdge` are polymorphic wrappers following the `anyOf` + `discriminator` pattern already established in the spec.

---

## Schemas

### Nodes

**`TopologyDeviceNode.yaml`** — `allOf NetworkDeviceRef` +

| Field | Schema | Required |
|---|---|---|
| `type` | `$ref NetworkDeviceType` | yes |
| `status` | `$ref NetworkDeviceStatus` | yes |
| `numClients` | `integer` | no — present only on AP nodes |

**`TopologyClientNode.yaml`** — `allOf NetworkClientRef` +

| Field | Schema | Required |
|---|---|---|
| `connectionType` | `$ref NetworkClientConnectionType` | yes |
| `status` | `$ref NetworkClientStatus` | yes |

**`TopologyNode.yaml`** — polymorphic wrapper discriminated on `kind`:

```yaml
anyOf:
  - $ref: "./TopologyDeviceNode.yaml"
  - $ref: "./TopologyClientNode.yaml"
discriminator:
  propertyName: kind
  mapping:
    device: "./TopologyDeviceNode.yaml"
    client: "./TopologyClientNode.yaml"
```

`kind` is inherited from `NetworkDeviceRef` (`"device"`) and `NetworkClientRef` (`"client"`) respectively — no new discriminator field needed.

### Edges

**`TopologyWiredEdge.yaml`**

| Field | Schema | Required | Notes |
|---|---|---|---|
| `kind` | `enum [wired]` | yes | discriminator |
| `source` | `$ref NetworkConnectionRef` | yes | downstream end — device or client |
| `target` | `$ref NetworkDeviceRef` | yes | upstream device |
| `port` | `integer, minimum: 1` | no | port on the upstream device |
| `linkSpeed` | `$ref NetworkLinkSpeed` | no | absent for offline clients |

**`TopologyWirelessEdge.yaml`**

| Field | Schema | Required | Notes |
|---|---|---|---|
| `kind` | `enum [wireless]` | yes | discriminator |
| `source` | `$ref NetworkClientRef` | yes | only clients connect wirelessly |
| `target` | `$ref NetworkDeviceRef` | yes | the AP |
| `ssid` | `string` | yes | retained as last-known when client is offline |
| `signalStrength` | `integer` (dBm) | no | absent for offline clients |

**`TopologyEdge.yaml`** — polymorphic wrapper:

```yaml
anyOf:
  - $ref: "./TopologyWiredEdge.yaml"
  - $ref: "./TopologyWirelessEdge.yaml"
discriminator:
  propertyName: kind
  mapping:
    wired: "./TopologyWiredEdge.yaml"
    wireless: "./TopologyWirelessEdge.yaml"
```

### Response body

**`NetworkTopology.yaml`**

| Field | Schema | Required |
|---|---|---|
| `nodes` | `array of $ref TopologyNode` | yes |
| `edges` | `array of $ref TopologyEdge` | yes |

---

## Example

`GET /network/topology` (devices only):

```json
{
  "nodes": [
    {
      "kind": "device",
      "id": "unifi.gateway",
      "uri": "/network/devices/unifi.gateway",
      "name": "Gateway",
      "type": "gateway",
      "status": "connected"
    },
    {
      "kind": "device",
      "id": "unifi.switch-living-room",
      "uri": "/network/devices/unifi.switch-living-room",
      "name": "Switch Living Room",
      "type": "switch",
      "status": "connected"
    },
    {
      "kind": "device",
      "id": "unifi.ap-living-room",
      "uri": "/network/devices/unifi.ap-living-room",
      "name": "AP Living Room",
      "type": "accessPoint",
      "status": "connected",
      "numClients": 3
    }
  ],
  "edges": [
    {
      "kind": "wired",
      "source": { "kind": "device", "id": "unifi.switch-living-room", "uri": "/network/devices/unifi.switch-living-room", "name": "Switch Living Room" },
      "target": { "kind": "device", "id": "unifi.gateway", "uri": "/network/devices/unifi.gateway", "name": "Gateway" },
      "port": 1,
      "linkSpeed": "gbe1"
    },
    {
      "kind": "wired",
      "source": { "kind": "device", "id": "unifi.ap-living-room", "uri": "/network/devices/unifi.ap-living-room", "name": "AP Living Room" },
      "target": { "kind": "device", "id": "unifi.switch-living-room", "uri": "/network/devices/unifi.switch-living-room", "name": "Switch Living Room" },
      "port": 4,
      "linkSpeed": "gbe1"
    }
  ]
}
```

`GET /network/topology?includeClients=true` adds client nodes and their edges:

```json
{
  "nodes": [
    { "kind": "client", "id": "unifi.macbook-pro-3c", "uri": "/network/clients/unifi.macbook-pro-3c", "name": "MacBook Pro", "connectionType": "wireless", "status": "online" }
  ],
  "edges": [
    {
      "kind": "wireless",
      "source": { "kind": "client", "id": "unifi.macbook-pro-3c", "uri": "/network/clients/unifi.macbook-pro-3c", "name": "MacBook Pro" },
      "target": { "kind": "device", "id": "unifi.ap-living-room", "uri": "/network/devices/unifi.ap-living-room", "name": "AP Living Room" },
      "ssid": "HomeNetwork",
      "signalStrength": -55
    }
  ]
}
```

---

## Files

### New schemas

- `openapi/components/schemas/TopologyDeviceNode.yaml`
- `openapi/components/schemas/TopologyClientNode.yaml`
- `openapi/components/schemas/TopologyNode.yaml`
- `openapi/components/schemas/TopologyWiredEdge.yaml`
- `openapi/components/schemas/TopologyWirelessEdge.yaml`
- `openapi/components/schemas/TopologyEdge.yaml`
- `openapi/components/schemas/NetworkTopology.yaml`

### New path

- `openapi/paths/network-topology.yaml`

### Updated

- `openapi/openapi.yaml` — one new path entry: `/network/topology`

---

## Reused schemas (no changes)

- `NetworkDeviceRef` — base for `TopologyDeviceNode`
- `NetworkClientRef` — base for `TopologyClientNode`
- `NetworkConnectionRef` — `source` on `TopologyWiredEdge`
- `NetworkDeviceType`, `NetworkDeviceStatus` — fields on `TopologyDeviceNode`
- `NetworkClientConnectionType`, `NetworkClientStatus` — fields on `TopologyClientNode`
- `NetworkLinkSpeed` — field on `TopologyWiredEdge`

---

## Out of scope

- Pagination — topology is a single snapshot; if it grows unwieldy, a separate change can scope it.
- Filtering by device type or client status.
- Gateway WAN uplink edge (no upstream device to point to).
- Traffic stats on nodes or edges — available via individual device/client detail endpoints.
