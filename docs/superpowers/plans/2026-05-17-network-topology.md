# Network Topology Endpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `GET /network/topology` returning the network as a graph of nodes and edges, with optional client inclusion via `?includeClients=true`.

**Architecture:** Seven new schemas build from existing refs (`NetworkDeviceRef`, `NetworkClientRef`, `NetworkConnectionRef`, `NetworkLinkSpeed`) using the `allOf` + `anyOf/discriminator` pattern already established in the spec. One new path file and one line in `openapi.yaml`. No existing schemas are modified.

**Tech Stack:** OpenAPI 3.0.3, Redocly CLI (lint + bundle), Spectral (lint bundled artifact). All tools run via `npx` — no global installs. Verification: `make lint`.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `openapi/components/schemas/TopologyDeviceNode.yaml` | Create | Device node: `allOf NetworkDeviceRef` + `type` + `status` + `numClients?` |
| `openapi/components/schemas/TopologyClientNode.yaml` | Create | Client node: `allOf NetworkClientRef` + `connectionType` + `status` |
| `openapi/components/schemas/TopologyNode.yaml` | Create | Polymorphic wrapper discriminated on `kind` |
| `openapi/components/schemas/TopologyWiredEdge.yaml` | Create | Wired edge: `source` + `target` + `port?` + `linkSpeed?` |
| `openapi/components/schemas/TopologyWirelessEdge.yaml` | Create | Wireless edge: `source` + `target` + `ssid` + `signalStrength?` |
| `openapi/components/schemas/TopologyEdge.yaml` | Create | Polymorphic wrapper discriminated on `kind` |
| `openapi/components/schemas/NetworkTopology.yaml` | Create | Response body: `{ nodes: TopologyNode[], edges: TopologyEdge[] }` |
| `openapi/paths/network-topology.yaml` | Create | `GET /network/topology` operation with examples |
| `openapi/openapi.yaml` | Modify | Register `/network/topology` path |

---

## Task 1: Node schemas

**Files:**
- Create: `openapi/components/schemas/TopologyDeviceNode.yaml`
- Create: `openapi/components/schemas/TopologyClientNode.yaml`
- Create: `openapi/components/schemas/TopologyNode.yaml`

- [ ] **Step 1: Create `TopologyDeviceNode.yaml`**

```yaml
allOf:
  - $ref: "./NetworkDeviceRef.yaml"
  - type: object
    description: A network device node in the topology graph.
    properties:
      type:
        $ref: "./NetworkDeviceType.yaml"
      status:
        $ref: "./NetworkDeviceStatus.yaml"
      numClients:
        type: integer
        minimum: 0
        description: |
          Number of associated wireless clients. Present only on access
          point nodes; omitted for switches, gateways, and unknown devices.
        example: 3
    required:
      - type
      - status
```

- [ ] **Step 2: Create `TopologyClientNode.yaml`**

```yaml
allOf:
  - $ref: "./NetworkClientRef.yaml"
  - type: object
    description: A client device node in the topology graph.
    properties:
      connectionType:
        $ref: "./NetworkClientConnectionType.yaml"
      status:
        $ref: "./NetworkClientStatus.yaml"
    required:
      - connectionType
      - status
```

- [ ] **Step 3: Create `TopologyNode.yaml`**

```yaml
anyOf:
  - $ref: "./TopologyDeviceNode.yaml"
  - $ref: "./TopologyClientNode.yaml"
discriminator:
  propertyName: kind
  mapping:
    device: "./TopologyDeviceNode.yaml"
    client: "./TopologyClientNode.yaml"
description: |
  Polymorphic topology node discriminated on `kind`. `device` nodes are
  infrastructure devices (gateway, switch, access point, unknown); `client`
  nodes are end-user devices. Follow `uri` to fetch full detail for either
  type.
```

- [ ] **Step 4: Verify the three schemas bundle cleanly**

Run: `make bundle`

Expected: `dist/openapi.bundled.yaml` produced with no errors. (The schemas are not yet referenced from any path, so Redocly lint will not check them yet — bundle is sufficient here.)

- [ ] **Step 5: Commit**

```bash
git add openapi/components/schemas/TopologyDeviceNode.yaml \
        openapi/components/schemas/TopologyClientNode.yaml \
        openapi/components/schemas/TopologyNode.yaml
git commit -m "feat: add topology node schemas"
```

---

## Task 2: Edge schemas

**Files:**
- Create: `openapi/components/schemas/TopologyWiredEdge.yaml`
- Create: `openapi/components/schemas/TopologyWirelessEdge.yaml`
- Create: `openapi/components/schemas/TopologyEdge.yaml`

- [ ] **Step 1: Create `TopologyWiredEdge.yaml`**

```yaml
type: object
description: |
  A wired connection between two nodes. `source` is the downstream
  endpoint (a device or a wired client); `target` is the upstream device.
  `port` and `linkSpeed` are present for live connections and omitted when
  only the upstream reference is known (e.g. an offline wired client where
  the controller retains the last known switch but not the last port).
properties:
  kind:
    type: string
    enum: [wired]
    description: Discriminator identifying this as a wired edge.
  source:
    $ref: "./NetworkConnectionRef.yaml"
  target:
    $ref: "./NetworkDeviceRef.yaml"
  port:
    type: integer
    minimum: 1
    description: |
      Physical port number on the upstream device. Omitted when the
      connection is not live.
    example: 4
  linkSpeed:
    allOf:
      - $ref: "./NetworkLinkSpeed.yaml"
    description: Negotiated link speed. Omitted when the connection is not live.
required:
  - kind
  - source
  - target
```

- [ ] **Step 2: Create `TopologyWirelessEdge.yaml`**

```yaml
type: object
description: |
  A wireless association between a client and an access point. `source`
  is the client; `target` is the AP. `signalStrength` is present for
  online clients and omitted for offline clients (no live measurement).
  `ssid` is always present — retained as last known when the client is
  offline.
properties:
  kind:
    type: string
    enum: [wireless]
    description: Discriminator identifying this as a wireless edge.
  source:
    $ref: "./NetworkClientRef.yaml"
  target:
    $ref: "./NetworkDeviceRef.yaml"
  ssid:
    type: string
    description: |
      SSID the client is (or was last) associated with. Present for both
      online and offline clients.
    example: "HomeNetwork"
  signalStrength:
    type: integer
    description: |
      Signal strength in dBm as measured by the access point. Omitted
      for offline clients (no live measurement available).
    example: -55
required:
  - kind
  - source
  - target
  - ssid
```

- [ ] **Step 3: Create `TopologyEdge.yaml`**

```yaml
anyOf:
  - $ref: "./TopologyWiredEdge.yaml"
  - $ref: "./TopologyWirelessEdge.yaml"
discriminator:
  propertyName: kind
  mapping:
    wired: "./TopologyWiredEdge.yaml"
    wireless: "./TopologyWirelessEdge.yaml"
description: |
  Polymorphic topology edge discriminated on `kind`. `wired` edges connect
  devices to devices (uplinks) or wired clients to their upstream switch.
  `wireless` edges connect wireless clients to their access point.
```

- [ ] **Step 4: Verify the three schemas bundle cleanly**

Run: `make bundle`

Expected: `dist/openapi.bundled.yaml` produced with no errors.

- [ ] **Step 5: Commit**

```bash
git add openapi/components/schemas/TopologyWiredEdge.yaml \
        openapi/components/schemas/TopologyWirelessEdge.yaml \
        openapi/components/schemas/TopologyEdge.yaml
git commit -m "feat: add topology edge schemas"
```

---

## Task 3: Response body schema

**Files:**
- Create: `openapi/components/schemas/NetworkTopology.yaml`

- [ ] **Step 1: Create `NetworkTopology.yaml`**

```yaml
type: object
description: |
  A snapshot of the network topology as a graph of nodes and edges.
  Nodes are devices and (optionally) clients; edges are the connections
  between them. The gateway node has no outgoing edge — it is the topology
  root. Identify it by `type: "gateway"`.
properties:
  nodes:
    type: array
    description: |
      All nodes in the topology. Always includes infrastructure devices
      (gateway, switches, access points). Includes clients when the
      `includeClients` query parameter is `true`.
    items:
      $ref: "./TopologyNode.yaml"
  edges:
    type: array
    description: |
      All connections between nodes. Device-to-device uplink edges are
      always present. Client-to-device edges are present when clients are
      included.
    items:
      $ref: "./TopologyEdge.yaml"
required:
  - nodes
  - edges
```

- [ ] **Step 2: Verify the schema bundles cleanly**

Run: `make bundle`

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkTopology.yaml
git commit -m "feat: add NetworkTopology response schema"
```

---

## Task 4: Path file

**Files:**
- Create: `openapi/paths/network-topology.yaml`

- [ ] **Step 1: Create `network-topology.yaml`**

```yaml
get:
  operationId: getNetworkTopology
  x-stability-level: draft
  summary: Get network topology
  description: |
    Returns the network topology as a graph of nodes and edges.

    By default only infrastructure devices (gateway, switches, access
    points) appear as nodes, with device-to-device uplink edges. Pass
    `includeClients=true` to add all network clients (online and offline)
    as nodes with their wired or wireless edges.

    The gateway node has no outgoing edge — it is the topology root.
    Consumers can identify it by `type: "gateway"`.
  tags:
    - network
  security:
    - bearerAuth: [read:network]
  parameters:
    - name: includeClients
      in: query
      required: false
      description: |
        When `true`, all network clients (online and offline) are included
        as nodes with their corresponding wired or wireless edges.
        Defaults to `false`.
      schema:
        type: boolean
        default: false
  responses:
    "200":
      description: Network topology graph.
      content:
        application/json:
          schema:
            $ref: "../components/schemas/NetworkTopology.yaml"
          examples:
            devicesOnly:
              summary: Devices-only topology (gateway → switch → AP).
              value:
                nodes:
                  - kind: device
                    id: "unifi.usg"
                    uri: "/network/devices/unifi.usg"
                    name: "USG"
                    type: gateway
                    status: connected
                  - kind: device
                    id: "unifi.switch-living-room"
                    uri: "/network/devices/unifi.switch-living-room"
                    name: "Switch Living Room"
                    type: switch
                    status: connected
                  - kind: device
                    id: "unifi.ap-living-room"
                    uri: "/network/devices/unifi.ap-living-room"
                    name: "AP Living Room"
                    type: accessPoint
                    status: connected
                    numClients: 1
                edges:
                  - kind: wired
                    source:
                      kind: device
                      id: "unifi.switch-living-room"
                      uri: "/network/devices/unifi.switch-living-room"
                      name: "Switch Living Room"
                    target:
                      kind: device
                      id: "unifi.usg"
                      uri: "/network/devices/unifi.usg"
                      name: "USG"
                    port: 1
                    linkSpeed: gbe1
                  - kind: wired
                    source:
                      kind: device
                      id: "unifi.ap-living-room"
                      uri: "/network/devices/unifi.ap-living-room"
                      name: "AP Living Room"
                    target:
                      kind: device
                      id: "unifi.switch-living-room"
                      uri: "/network/devices/unifi.switch-living-room"
                      name: "Switch Living Room"
                    port: 7
                    linkSpeed: gbe2_5
            withClients:
              summary: Topology with a wired client and a wireless client.
              value:
                nodes:
                  - kind: device
                    id: "unifi.usg"
                    uri: "/network/devices/unifi.usg"
                    name: "USG"
                    type: gateway
                    status: connected
                  - kind: device
                    id: "unifi.switch-living-room"
                    uri: "/network/devices/unifi.switch-living-room"
                    name: "Switch Living Room"
                    type: switch
                    status: connected
                  - kind: device
                    id: "unifi.ap-living-room"
                    uri: "/network/devices/unifi.ap-living-room"
                    name: "AP Living Room"
                    type: accessPoint
                    status: connected
                    numClients: 1
                  - kind: client
                    id: "unifi.nas-1-68"
                    uri: "/network/clients/unifi.nas-1-68"
                    name: "nas-1"
                    connectionType: wired
                    status: online
                  - kind: client
                    id: "unifi.macbook-pro-3c"
                    uri: "/network/clients/unifi.macbook-pro-3c"
                    name: "MacBook Pro"
                    connectionType: wireless
                    status: online
                edges:
                  - kind: wired
                    source:
                      kind: device
                      id: "unifi.switch-living-room"
                      uri: "/network/devices/unifi.switch-living-room"
                      name: "Switch Living Room"
                    target:
                      kind: device
                      id: "unifi.usg"
                      uri: "/network/devices/unifi.usg"
                      name: "USG"
                    port: 1
                    linkSpeed: gbe1
                  - kind: wired
                    source:
                      kind: device
                      id: "unifi.ap-living-room"
                      uri: "/network/devices/unifi.ap-living-room"
                      name: "AP Living Room"
                    target:
                      kind: device
                      id: "unifi.switch-living-room"
                      uri: "/network/devices/unifi.switch-living-room"
                      name: "Switch Living Room"
                    port: 7
                    linkSpeed: gbe2_5
                  - kind: wired
                    source:
                      kind: client
                      id: "unifi.nas-1-68"
                      uri: "/network/clients/unifi.nas-1-68"
                      name: "nas-1"
                    target:
                      kind: device
                      id: "unifi.switch-living-room"
                      uri: "/network/devices/unifi.switch-living-room"
                      name: "Switch Living Room"
                    port: 8
                    linkSpeed: gbe2_5
                  - kind: wireless
                    source:
                      kind: client
                      id: "unifi.macbook-pro-3c"
                      uri: "/network/clients/unifi.macbook-pro-3c"
                      name: "MacBook Pro"
                    target:
                      kind: device
                      id: "unifi.ap-living-room"
                      uri: "/network/devices/unifi.ap-living-room"
                      name: "AP Living Room"
                    ssid: "HomeNetwork"
                    signalStrength: -55
    "401":
      $ref: "../components/responses/Unauthorized.yaml"
    "429":
      $ref: "../components/responses/TooManyRequests.yaml"
    "500":
      $ref: "../components/responses/InternalServerError.yaml"
```

- [ ] **Step 2: Verify bundle (without registering the path yet)**

Run: `make bundle`

Expected: no errors. The path file is not yet referenced from `openapi.yaml` so Redocly won't validate it, but bundle should still succeed.

- [ ] **Step 3: Commit**

```bash
git add openapi/paths/network-topology.yaml
git commit -m "feat: add network-topology path file"
```

---

## Task 5: Register path and run full lint

**Files:**
- Modify: `openapi/openapi.yaml`

- [ ] **Step 1: Add the path entry to `openapi/openapi.yaml`**

In the `paths:` section, after the `/network/clients/{clientId}:` line, add:

```yaml
  /network/topology:
    $ref: "./paths/network-topology.yaml"
```

The full paths block should end with:

```yaml
  /network/clients:
    $ref: "./paths/network-clients.yaml"
  /network/clients/{clientId}:
    $ref: "./paths/network-clients-id.yaml"
  /network/topology:
    $ref: "./paths/network-topology.yaml"
```

- [ ] **Step 2: Run full lint**

Run: `make lint`

Expected: no errors or warnings. If Spectral reports issues, fix them before committing. Common issues to watch for:
- `operation-tag-defined` — `network` tag is already defined in `openapi.yaml`, so this should pass.
- `operation-operationId` — `getNetworkTopology` is present, so this should pass.
- `enum-value-camelcase` — all enum values in new schemas (`wired`, `wireless`, `connected`, `disconnected`, `online`, `offline`, `gateway`, `switch`, `accessPoint`, `unknown`) are already camelCase.

- [ ] **Step 3: Commit**

```bash
git add openapi/openapi.yaml
git commit -m "feat: register GET /network/topology"
```
