# Network SSIDs, VLANs, and WANs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six read-only endpoints under `/network` — list + detail for SSIDs, VLANs, and WAN interfaces — following the established contract-first OpenAPI spec conventions.

**Architecture:** Each resource follows the list/detail split via `allOf`: a compact list-item schema extended by a detail schema. All three resources use composite `{controller}.{name}` IDs. Two new shared schemas (`IpAddress`, `units/Seconds`) are created first since multiple resources depend on them.

**Tech Stack:** OpenAPI 3.0.3, Redocly CLI (source lint), Spectral 6.x (bundled lint), `make lint` / `make bundle` / `make preview`.

---

## Task 1: Shared schemas — IpAddress and Seconds

**Files:**
- Create: `openapi/components/schemas/IpAddress.yaml`
- Create: `openapi/components/schemas/units/Seconds.yaml`

- [ ] **Step 1: Create IpAddress.yaml**

```yaml
# openapi/components/schemas/IpAddress.yaml
type: string
format: ipv4
description: An IPv4 address in dotted-decimal notation (e.g. `192.168.1.1`).
```

- [ ] **Step 2: Create units/Seconds.yaml**

```yaml
# openapi/components/schemas/units/Seconds.yaml
type: integer
description: A duration expressed in seconds.
```

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/IpAddress.yaml openapi/components/schemas/units/Seconds.yaml
git commit -m "feat: add IpAddress and Seconds shared schemas"
```

---

## Task 2: SSID schemas

**Files:**
- Create: `openapi/components/schemas/WifiBand.yaml`
- Create: `openapi/components/schemas/WifiSecurityProtocol.yaml`
- Create: `openapi/components/schemas/Ssid.yaml`
- Create: `openapi/components/schemas/SsidDetail.yaml`
- Create: `openapi/components/schemas/SsidList.yaml`

- [ ] **Step 1: Create WifiBand.yaml**

```yaml
# openapi/components/schemas/WifiBand.yaml
type: string
description: |
  A radio frequency band on which a WiFi network broadcasts.
  - `band2g` — 2.4 GHz
  - `band5g` — 5 GHz
  - `band6g` — 6 GHz
enum:
  - band2g
  - band5g
  - band6g
```

- [ ] **Step 2: Create WifiSecurityProtocol.yaml**

```yaml
# openapi/components/schemas/WifiSecurityProtocol.yaml
type: string
description: |
  The security protocol used by a WiFi network.
  - `open` — No authentication
  - `wpa2` — WPA2 Personal
  - `wpa3` — WPA3 Personal
  - `wpa2Wpa3` — WPA2/WPA3 Personal transition mode
  - `wpa2Enterprise` — WPA2 Enterprise (802.1X)
  - `wpa3Enterprise` — WPA3 Enterprise (802.1X)
  - `wpa2Wpa3Enterprise` — WPA2/WPA3 Enterprise transition mode
enum:
  - open
  - wpa2
  - wpa3
  - wpa2Wpa3
  - wpa2Enterprise
  - wpa3Enterprise
  - wpa2Wpa3Enterprise
```

- [ ] **Step 3: Create Ssid.yaml**

```yaml
# openapi/components/schemas/Ssid.yaml
type: object
description: A WiFi network (SSID) managed by a network controller.
properties:
  id:
    type: string
    description: |
      Composite SSID identifier in the form `{controller}.{name}`,
      e.g. `unifi.iot`. The controller prefix disambiguates SSIDs
      across multiple controllers.
    example: "unifi.iot"
  uri:
    type: string
    description: Relative API path to fetch this SSID's detail.
    example: "/network/ssids/unifi.iot"
  name:
    type: string
    description: The broadcast SSID name clients see when scanning for networks.
    example: "IoT"
  vlanId:
    type: integer
    description: The numeric VLAN tag this WiFi network is associated with.
    example: 20
  bands:
    type: array
    description: Radio frequency bands on which this SSID broadcasts.
    items:
      $ref: "./WifiBand.yaml"
  numClients:
    type: integer
    description: Number of clients currently connected to this SSID.
    example: 4
required:
  - id
  - uri
  - name
  - vlanId
  - bands
  - numClients
```

- [ ] **Step 4: Create SsidDetail.yaml**

```yaml
# openapi/components/schemas/SsidDetail.yaml
allOf:
  - $ref: "./Ssid.yaml"
  - type: object
    description: Full detail for a WiFi network (SSID), including connected clients and broadcasting access points.
    properties:
      securityProtocol:
        $ref: "./WifiSecurityProtocol.yaml"
      clients:
        type: array
        description: Clients currently connected to this SSID.
        items:
          $ref: "./NetworkClientRef.yaml"
      broadcastingAps:
        type: array
        description: Access points currently broadcasting this SSID.
        items:
          $ref: "./NetworkDeviceRef.yaml"
    required:
      - securityProtocol
      - clients
      - broadcastingAps
```

- [ ] **Step 5: Create SsidList.yaml**

```yaml
# openapi/components/schemas/SsidList.yaml
type: object
description: List of WiFi networks (SSIDs).
properties:
  items:
    type: array
    description: All SSIDs managed by connected controllers. Empty array, never null.
    items:
      $ref: "./Ssid.yaml"
required:
  - items
```

- [ ] **Step 6: Commit**

```bash
git add openapi/components/schemas/WifiBand.yaml \
        openapi/components/schemas/WifiSecurityProtocol.yaml \
        openapi/components/schemas/Ssid.yaml \
        openapi/components/schemas/SsidDetail.yaml \
        openapi/components/schemas/SsidList.yaml
git commit -m "feat: add SSID schemas"
```

---

## Task 3: SSID endpoints

**Files:**
- Create: `openapi/paths/network-ssids.yaml`
- Create: `openapi/paths/network-ssids-id.yaml`
- Modify: `openapi/openapi.yaml`

- [ ] **Step 1: Create network-ssids.yaml**

```yaml
# openapi/paths/network-ssids.yaml
get:
  operationId: listSsids
  x-stability-level: draft
  summary: List WiFi networks
  description: |
    Returns all WiFi networks (SSIDs) managed by all configured
    controllers.

    A homelab typically has a small number of SSIDs, so this endpoint
    returns all results without pagination.
  tags:
    - network
  security:
    - bearerAuth: [read:network]
  responses:
    "200":
      description: List of WiFi networks.
      content:
        application/json:
          schema:
            $ref: "../components/schemas/SsidList.yaml"
          examples:
            typicalHomelab:
              summary: A homelab with a main network and IoT SSID.
              value:
                items:
                  - id: "unifi.home"
                    uri: "/network/ssids/unifi.home"
                    name: "Home"
                    vlanId: 1
                    bands: [band2g, band5g, band6g]
                    numClients: 12
                  - id: "unifi.iot"
                    uri: "/network/ssids/unifi.iot"
                    name: "IoT"
                    vlanId: 20
                    bands: [band2g, band5g]
                    numClients: 8
    "401":
      $ref: "../components/responses/Unauthorized.yaml"
    "403":
      $ref: "../components/responses/Forbidden.yaml"
    "429":
      $ref: "../components/responses/TooManyRequests.yaml"
    "500":
      $ref: "../components/responses/InternalServerError.yaml"
```

- [ ] **Step 2: Create network-ssids-id.yaml**

```yaml
# openapi/paths/network-ssids-id.yaml
get:
  operationId: getSsid
  x-stability-level: draft
  summary: Get a WiFi network
  description: |
    Returns a single WiFi network (SSID) by its composite identifier
    (`{controller}.{name}`, e.g. `unifi.iot`).

    The response includes connected clients, broadcasting access points,
    and security protocol in addition to the list fields.
  tags:
    - network
  security:
    - bearerAuth: [read:network]
  parameters:
    - name: ssidId
      in: path
      required: true
      description: |
        Composite SSID identifier in the form `{controller}.{name}`
        (e.g. `unifi.iot`). The controller prefix disambiguates SSIDs
        across multiple controllers.
      schema:
        type: string
      example: "unifi.iot"
  responses:
    "200":
      description: The requested WiFi network.
      content:
        application/json:
          schema:
            $ref: "../components/schemas/SsidDetail.yaml"
          examples:
            iotSsid:
              summary: An IoT SSID with WPA2 security and connected clients.
              value:
                id: "unifi.iot"
                uri: "/network/ssids/unifi.iot"
                name: "IoT"
                vlanId: 20
                bands: [band2g, band5g]
                numClients: 3
                securityProtocol: wpa2
                clients:
                  - kind: client
                    id: "unifi.sonos-one-sl-c4"
                    uri: "/network/clients/unifi.sonos-one-sl-c4"
                    name: "Sonos One SL"
                  - kind: client
                    id: "unifi.philips-hue-bridge-b8"
                    uri: "/network/clients/unifi.philips-hue-bridge-b8"
                    name: "Philips Hue Bridge"
                  - kind: client
                    id: "unifi.nest-thermostat-0a"
                    uri: "/network/clients/unifi.nest-thermostat-0a"
                    name: "Nest Thermostat"
                broadcastingAps:
                  - kind: device
                    id: "unifi.ap-living-room"
                    uri: "/network/devices/unifi.ap-living-room"
                    name: "AP Living Room"
                  - kind: device
                    id: "unifi.ap-kitchen"
                    uri: "/network/devices/unifi.ap-kitchen"
                    name: "AP Kitchen"
    "401":
      $ref: "../components/responses/Unauthorized.yaml"
    "403":
      $ref: "../components/responses/Forbidden.yaml"
    "404":
      $ref: "../components/responses/NotFound.yaml"
    "429":
      $ref: "../components/responses/TooManyRequests.yaml"
    "500":
      $ref: "../components/responses/InternalServerError.yaml"
```

- [ ] **Step 3: Register SSID paths in openapi/openapi.yaml**

Add after the `/network/topology` line:

```yaml
  /network/ssids:
    $ref: "./paths/network-ssids.yaml"
  /network/ssids/{ssidId}:
    $ref: "./paths/network-ssids-id.yaml"
```

- [ ] **Step 4: Run lint**

```bash
make lint
```

Expected: no errors. If Spectral or Redocly reports errors, fix them before proceeding.

- [ ] **Step 5: Commit**

```bash
git add openapi/paths/network-ssids.yaml \
        openapi/paths/network-ssids-id.yaml \
        openapi/openapi.yaml
git commit -m "feat: add GET /network/ssids and GET /network/ssids/{ssidId}"
```

---

## Task 4: VLAN schemas

**Files:**
- Create: `openapi/components/schemas/DhcpMode.yaml`
- Create: `openapi/components/schemas/DhcpRange.yaml`
- Create: `openapi/components/schemas/Vlan.yaml`
- Create: `openapi/components/schemas/VlanDetail.yaml`
- Create: `openapi/components/schemas/VlanList.yaml`

- [ ] **Step 1: Create DhcpMode.yaml**

```yaml
# openapi/components/schemas/DhcpMode.yaml
type: string
description: |
  The DHCP operating mode for a VLAN.
  - `server` — This VLAN runs its own DHCP server; `dhcpRange` is present in the detail
  - `relay` — DHCP requests are forwarded to an upstream server; `relayServer` is present in the detail
  - `disabled` — No DHCP on this VLAN
enum:
  - server
  - relay
  - disabled
```

- [ ] **Step 2: Create DhcpRange.yaml**

```yaml
# openapi/components/schemas/DhcpRange.yaml
type: object
description: The IP address range allocated by the DHCP server for a VLAN.
properties:
  start:
    allOf:
      - $ref: "./IpAddress.yaml"
    description: First IP address in the DHCP pool.
    example: "192.168.20.100"
  end:
    allOf:
      - $ref: "./IpAddress.yaml"
    description: Last IP address in the DHCP pool.
    example: "192.168.20.200"
required:
  - start
  - end
```

- [ ] **Step 3: Create Vlan.yaml**

```yaml
# openapi/components/schemas/Vlan.yaml
type: object
description: A VLAN managed by a network controller.
properties:
  id:
    type: string
    description: |
      Composite VLAN identifier in the form `{controller}.{name}`,
      e.g. `unifi.iot`. The controller prefix disambiguates VLANs
      across multiple controllers.
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
    description: Numeric VLAN tag (1–4094).
    example: 20
  subnet:
    type: string
    description: Network subnet in CIDR notation.
    example: "192.168.20.0/24"
required:
  - id
  - uri
  - name
  - vlanId
  - subnet
```

- [ ] **Step 4: Create VlanDetail.yaml**

```yaml
# openapi/components/schemas/VlanDetail.yaml
allOf:
  - $ref: "./Vlan.yaml"
  - type: object
    description: Full detail for a VLAN, including DHCP configuration and DNS settings.
    properties:
      gatewayIp:
        allOf:
          - $ref: "./IpAddress.yaml"
        description: IP address of the gateway for this VLAN.
        example: "192.168.20.1"
      broadcastIp:
        allOf:
          - $ref: "./IpAddress.yaml"
        description: Broadcast IP address for this VLAN's subnet.
        example: "192.168.20.255"
      dhcpMode:
        $ref: "./DhcpMode.yaml"
      dhcpRange:
        allOf:
          - $ref: "./DhcpRange.yaml"
        description: IP address pool allocated by the DHCP server. Present only when `dhcpMode` is `server`.
      relayServer:
        allOf:
          - $ref: "./IpAddress.yaml"
        description: IP address of the upstream DHCP server. Present only when `dhcpMode` is `relay`.
        example: "192.168.1.1"
      dnsServers:
        type: array
        description: DNS server IP addresses configured for this VLAN.
        items:
          $ref: "./IpAddress.yaml"
    required:
      - gatewayIp
      - broadcastIp
      - dhcpMode
      - dnsServers
```

- [ ] **Step 5: Create VlanList.yaml**

```yaml
# openapi/components/schemas/VlanList.yaml
type: object
description: List of VLANs.
properties:
  items:
    type: array
    description: All VLANs managed by connected controllers. Empty array, never null.
    items:
      $ref: "./Vlan.yaml"
required:
  - items
```

- [ ] **Step 6: Commit**

```bash
git add openapi/components/schemas/DhcpMode.yaml \
        openapi/components/schemas/DhcpRange.yaml \
        openapi/components/schemas/Vlan.yaml \
        openapi/components/schemas/VlanDetail.yaml \
        openapi/components/schemas/VlanList.yaml
git commit -m "feat: add VLAN schemas"
```

---

## Task 5: VLAN endpoints

**Files:**
- Create: `openapi/paths/network-vlans.yaml`
- Create: `openapi/paths/network-vlans-id.yaml`
- Modify: `openapi/openapi.yaml`

- [ ] **Step 1: Create network-vlans.yaml**

```yaml
# openapi/paths/network-vlans.yaml
get:
  operationId: listVlans
  x-stability-level: draft
  summary: List VLANs
  description: |
    Returns all VLANs managed by all configured controllers.

    A homelab typically has a small number of VLANs, so this endpoint
    returns all results without pagination.
  tags:
    - network
  security:
    - bearerAuth: [read:network]
  responses:
    "200":
      description: List of VLANs.
      content:
        application/json:
          schema:
            $ref: "../components/schemas/VlanList.yaml"
          examples:
            typicalHomelab:
              summary: A homelab with main, IoT, and management VLANs.
              value:
                items:
                  - id: "unifi.default"
                    uri: "/network/vlans/unifi.default"
                    name: "Default"
                    vlanId: 1
                    subnet: "192.168.1.0/24"
                  - id: "unifi.iot"
                    uri: "/network/vlans/unifi.iot"
                    name: "IoT"
                    vlanId: 20
                    subnet: "192.168.20.0/24"
                  - id: "unifi.mgmt"
                    uri: "/network/vlans/unifi.mgmt"
                    name: "Management"
                    vlanId: 99
                    subnet: "10.0.99.0/24"
    "401":
      $ref: "../components/responses/Unauthorized.yaml"
    "403":
      $ref: "../components/responses/Forbidden.yaml"
    "429":
      $ref: "../components/responses/TooManyRequests.yaml"
    "500":
      $ref: "../components/responses/InternalServerError.yaml"
```

- [ ] **Step 2: Create network-vlans-id.yaml**

```yaml
# openapi/paths/network-vlans-id.yaml
get:
  operationId: getVlan
  x-stability-level: draft
  summary: Get a VLAN
  description: |
    Returns a single VLAN by its composite identifier
    (`{controller}.{name}`, e.g. `unifi.iot`).

    The response includes DHCP configuration and DNS settings in addition
    to the list fields. `dhcpRange` is present only when `dhcpMode` is
    `server`; `relayServer` is present only when `dhcpMode` is `relay`.
  tags:
    - network
  security:
    - bearerAuth: [read:network]
  parameters:
    - name: vlanId
      in: path
      required: true
      description: |
        Composite VLAN identifier in the form `{controller}.{name}`
        (e.g. `unifi.iot`). The controller prefix disambiguates VLANs
        across multiple controllers.
      schema:
        type: string
      example: "unifi.iot"
  responses:
    "200":
      description: The requested VLAN.
      content:
        application/json:
          schema:
            $ref: "../components/schemas/VlanDetail.yaml"
          examples:
            serverDhcp:
              summary: A VLAN running its own DHCP server.
              value:
                id: "unifi.iot"
                uri: "/network/vlans/unifi.iot"
                name: "IoT"
                vlanId: 20
                subnet: "192.168.20.0/24"
                gatewayIp: "192.168.20.1"
                broadcastIp: "192.168.20.255"
                dhcpMode: server
                dhcpRange:
                  start: "192.168.20.100"
                  end: "192.168.20.200"
                dnsServers:
                  - "1.1.1.1"
                  - "8.8.8.8"
            relayDhcp:
              summary: A VLAN relaying DHCP to an upstream server.
              value:
                id: "unifi.mgmt"
                uri: "/network/vlans/unifi.mgmt"
                name: "Management"
                vlanId: 99
                subnet: "10.0.99.0/24"
                gatewayIp: "10.0.99.1"
                broadcastIp: "10.0.99.255"
                dhcpMode: relay
                relayServer: "192.168.1.1"
                dnsServers:
                  - "192.168.1.1"
            disabledDhcp:
              summary: A VLAN with DHCP disabled (static assignments only).
              value:
                id: "unifi.servers"
                uri: "/network/vlans/unifi.servers"
                name: "Servers"
                vlanId: 10
                subnet: "192.168.10.0/24"
                gatewayIp: "192.168.10.1"
                broadcastIp: "192.168.10.255"
                dhcpMode: disabled
                dnsServers:
                  - "1.1.1.1"
    "401":
      $ref: "../components/responses/Unauthorized.yaml"
    "403":
      $ref: "../components/responses/Forbidden.yaml"
    "404":
      $ref: "../components/responses/NotFound.yaml"
    "429":
      $ref: "../components/responses/TooManyRequests.yaml"
    "500":
      $ref: "../components/responses/InternalServerError.yaml"
```

- [ ] **Step 3: Register VLAN paths in openapi/openapi.yaml**

Add after the `/network/ssids/{ssidId}` line:

```yaml
  /network/vlans:
    $ref: "./paths/network-vlans.yaml"
  /network/vlans/{vlanId}:
    $ref: "./paths/network-vlans-id.yaml"
```

- [ ] **Step 4: Run lint**

```bash
make lint
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add openapi/paths/network-vlans.yaml \
        openapi/paths/network-vlans-id.yaml \
        openapi/openapi.yaml
git commit -m "feat: add GET /network/vlans and GET /network/vlans/{vlanId}"
```

---

## Task 6: WAN schemas

**Files:**
- Create: `openapi/components/schemas/WanStatus.yaml`
- Create: `openapi/components/schemas/Wan.yaml`
- Create: `openapi/components/schemas/WanDetail.yaml`
- Create: `openapi/components/schemas/WanList.yaml`

- [ ] **Step 1: Create WanStatus.yaml**

```yaml
# openapi/components/schemas/WanStatus.yaml
type: string
description: |
  The connection status of a WAN interface.
  - `connected` — WAN is up and passing traffic
  - `disconnected` — WAN link is down
  - `failover` — WAN is in failover/backup mode
enum:
  - connected
  - disconnected
  - failover
```

- [ ] **Step 2: Create Wan.yaml**

```yaml
# openapi/components/schemas/Wan.yaml
type: object
description: A WAN interface managed by a network controller.
properties:
  id:
    type: string
    description: |
      Composite WAN identifier in the form `{controller}.{name}`,
      e.g. `unifi.wan1`. The controller prefix disambiguates WAN
      interfaces across multiple controllers.
    example: "unifi.wan1"
  uri:
    type: string
    description: Relative API path to fetch this WAN's detail.
    example: "/network/wans/unifi.wan1"
  name:
    type: string
    description: Human-readable WAN interface name.
    example: "WAN 1"
  ipAddress:
    allOf:
      - $ref: "./IpAddress.yaml"
    description: Current public IP address assigned to this WAN interface. Last known address for disconnected interfaces.
    example: "203.0.113.42"
  uptime:
    allOf:
      - $ref: "./units/Seconds.yaml"
    description: Seconds since the WAN connection was last established. Zero when disconnected or in standby.
    example: 86400
  status:
    $ref: "./WanStatus.yaml"
required:
  - id
  - uri
  - name
  - ipAddress
  - uptime
  - status
```

- [ ] **Step 3: Create WanDetail.yaml**

```yaml
# openapi/components/schemas/WanDetail.yaml
allOf:
  - $ref: "./Wan.yaml"
  - type: object
    description: Full detail for a WAN interface, including DNS configuration.
    properties:
      dnsServers:
        type: array
        description: DNS server IP addresses assigned to this WAN interface.
        items:
          $ref: "./IpAddress.yaml"
    required:
      - dnsServers
```

- [ ] **Step 4: Create WanList.yaml**

```yaml
# openapi/components/schemas/WanList.yaml
type: object
description: List of WAN interfaces.
properties:
  items:
    type: array
    description: All WAN interfaces managed by connected controllers. Empty array, never null.
    items:
      $ref: "./Wan.yaml"
required:
  - items
```

- [ ] **Step 5: Commit**

```bash
git add openapi/components/schemas/WanStatus.yaml \
        openapi/components/schemas/Wan.yaml \
        openapi/components/schemas/WanDetail.yaml \
        openapi/components/schemas/WanList.yaml
git commit -m "feat: add WAN schemas"
```

---

## Task 7: WAN endpoints

**Files:**
- Create: `openapi/paths/network-wans.yaml`
- Create: `openapi/paths/network-wans-id.yaml`
- Modify: `openapi/openapi.yaml`

- [ ] **Step 1: Create network-wans.yaml**

```yaml
# openapi/paths/network-wans.yaml
get:
  operationId: listWans
  x-stability-level: draft
  summary: List WAN interfaces
  description: |
    Returns all WAN interfaces managed by all configured controllers.

    A homelab typically has a small number of WAN interfaces, so this
    endpoint returns all results without pagination.
  tags:
    - network
  security:
    - bearerAuth: [read:network]
  responses:
    "200":
      description: List of WAN interfaces.
      content:
        application/json:
          schema:
            $ref: "../components/schemas/WanList.yaml"
          examples:
            typicalHomelab:
              summary: A homelab with a primary WAN and a failover connection.
              value:
                items:
                  - id: "unifi.wan1"
                    uri: "/network/wans/unifi.wan1"
                    name: "WAN 1"
                    ipAddress: "203.0.113.42"
                    uptime: 86400
                    status: connected
                  - id: "unifi.wan2"
                    uri: "/network/wans/unifi.wan2"
                    name: "WAN 2"
                    ipAddress: "198.51.100.7"
                    uptime: 0
                    status: failover
    "401":
      $ref: "../components/responses/Unauthorized.yaml"
    "403":
      $ref: "../components/responses/Forbidden.yaml"
    "429":
      $ref: "../components/responses/TooManyRequests.yaml"
    "500":
      $ref: "../components/responses/InternalServerError.yaml"
```

- [ ] **Step 2: Create network-wans-id.yaml**

```yaml
# openapi/paths/network-wans-id.yaml
get:
  operationId: getWan
  x-stability-level: draft
  summary: Get a WAN interface
  description: |
    Returns a single WAN interface by its composite identifier
    (`{controller}.{name}`, e.g. `unifi.wan1`).

    The response includes DNS configuration in addition to the list fields.
  tags:
    - network
  security:
    - bearerAuth: [read:network]
  parameters:
    - name: wanId
      in: path
      required: true
      description: |
        Composite WAN identifier in the form `{controller}.{name}`
        (e.g. `unifi.wan1`). The controller prefix disambiguates WAN
        interfaces across multiple controllers.
      schema:
        type: string
      example: "unifi.wan1"
  responses:
    "200":
      description: The requested WAN interface.
      content:
        application/json:
          schema:
            $ref: "../components/schemas/WanDetail.yaml"
          examples:
            connectedWan:
              summary: A connected primary WAN with ISP-assigned DNS servers.
              value:
                id: "unifi.wan1"
                uri: "/network/wans/unifi.wan1"
                name: "WAN 1"
                ipAddress: "203.0.113.42"
                uptime: 86400
                status: connected
                dnsServers:
                  - "1.1.1.1"
                  - "1.0.0.1"
    "401":
      $ref: "../components/responses/Unauthorized.yaml"
    "403":
      $ref: "../components/responses/Forbidden.yaml"
    "404":
      $ref: "../components/responses/NotFound.yaml"
    "429":
      $ref: "../components/responses/TooManyRequests.yaml"
    "500":
      $ref: "../components/responses/InternalServerError.yaml"
```

- [ ] **Step 3: Register WAN paths in openapi/openapi.yaml**

Add after the `/network/vlans/{vlanId}` line:

```yaml
  /network/wans:
    $ref: "./paths/network-wans.yaml"
  /network/wans/{wanId}:
    $ref: "./paths/network-wans-id.yaml"
```

- [ ] **Step 4: Run lint**

```bash
make lint
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add openapi/paths/network-wans.yaml \
        openapi/paths/network-wans-id.yaml \
        openapi/openapi.yaml
git commit -m "feat: add GET /network/wans and GET /network/wans/{wanId}"
```

---

## Task 8: Final verification

- [ ] **Step 1: Bundle the spec**

```bash
make bundle
```

Expected: `dist/openapi.bundled.yaml` and `dist/openapi.bundled.json` created with no errors.

- [ ] **Step 2: Start preview and verify all six endpoints appear**

```bash
make preview
```

Open `http://localhost:8080` and verify:
- `GET /network/ssids` — list response with `items` array, each item has `id`, `uri`, `name`, `vlanId`, `bands`, `numClients`
- `GET /network/ssids/{ssidId}` — detail adds `securityProtocol`, `clients`, `broadcastingAps`
- `GET /network/vlans` — list response with `id`, `uri`, `name`, `vlanId`, `subnet`
- `GET /network/vlans/{vlanId}` — detail adds `gatewayIp`, `broadcastIp`, `dhcpMode`, `dhcpRange` (server example), `relayServer` (relay example), `dnsServers`; three examples shown
- `GET /network/wans` — list response with `id`, `uri`, `name`, `ipAddress`, `uptime`, `status`
- `GET /network/wans/{wanId}` — detail adds `dnsServers`
