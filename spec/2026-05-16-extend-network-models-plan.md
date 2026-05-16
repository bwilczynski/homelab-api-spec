# Extend Network Models — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [`spec/2026-05-16-extend-network-models.md`](./2026-05-16-extend-network-models.md)

**Goal:** Extend `/network/devices` detail responses with switch ports (PoE/speed/connected refs), AP connected-client lists, per-device traffic stats, and uplink topology. Restructure wired/wireless client details around a shared `connectedTo` shape. Introduce a cross-resource reference pattern and polymorphic device detail.

**Architecture:** Spec-only repo — every task adds or edits YAML under `openapi/` (plus a Spectral rule and a guideline note). Verification is `make lint` (Redocly + Spectral on the bundled output). No application code, no unit tests; the "test" for each task is `make lint` passing and, where relevant, the bundled output containing the expected shapes.

**Tech stack:** OpenAPI 3.0.3 (multi-file via Redocly), Spectral 6.15.0 for lint, Redocly 1.25.15 for bundle/build, oasdiff for breaking-change detection.

**Branch suggestion:** Work on a feature branch (e.g. `feat/extend-network-models`) and merge via PR so `make breaking BASE=origin/main` has a meaningful baseline. Not strictly required — this user has committed comparable work directly to `main` before.

**YAML gotcha:** The string `off` parses as boolean `false` under YAML 1.1 and some OpenAPI tools. Always quote it: `'off'`. Applies to `SwitchPortPoeMode` and to any examples using `poeMode: 'off'`.

---

## File Structure

### New schemas (17)

Under `openapi/components/schemas/`:

| File | Responsibility |
|---|---|
| `NetworkDeviceRef.yaml` | Lightweight `{ kind: device, id, uri, name }` pointer to a device |
| `NetworkClientRef.yaml` | Lightweight `{ kind: client, id, uri, name }` pointer to a client |
| `NetworkConnectionRef.yaml` | `anyOf` wrapper polymorphic on `kind`; used by `SwitchPort.connectedTo` |
| `NetworkConnection.yaml` | Rich downstream→upstream connection (`device + port + linkSpeed`); used by `uplink` and wired `connectedTo` |
| `WirelessConnection.yaml` | Wireless analog (`device + ssid + signalStrength`); used by wireless `connectedTo` |
| `NetworkTraffic.yaml` | Shared rx/tx total + rate block |
| `SwitchPort.yaml` | One physical port on a switch (number, state, link speed, PoE, traffic, connectedTo) |
| `NetworkLinkSpeed.yaml` | Enum: `e, fe, gbe1, gbe2_5, gbe5, gbe10` |
| `NetworkPortState.yaml` | Enum: `up, down, disabled` |
| `SwitchPortPoeMode.yaml` | Enum: `'off', auto, passive24v, passthrough` |
| `NetworkDeviceDetailBase.yaml` | Common detail fields (extends `NetworkDevice` via `allOf`) |
| `SwitchDetail.yaml` | Switch variant (pins `type: switch`, adds `ports[]`) |
| `AccessPointDetail.yaml` | AP variant (pins `type: accessPoint`, adds `numClients`, `connectedClients[]`) |
| `GatewayDetail.yaml` | Gateway variant (pins `type: gateway`; no extras yet) |
| `UnknownDeviceDetail.yaml` | Catch-all variant (pins `type: unknown`; no extras) |
| `AccessPointClient.yaml` | AP-side client association (`client + ssid + signalStrength`) |
| `units/Watts.yaml` | Float watts, `minimum: 0` |

### Updated schemas (5)

| File | Change |
|---|---|
| `NetworkDevice.yaml` | Add required `uri`; remove `numClients` |
| `NetworkClient.yaml` | Add required `uri` |
| `NetworkDeviceDetail.yaml` | Replace flat `allOf` with polymorphic `anyOf` wrapper over the four variants, discriminated on `type` |
| `WiredNetworkClientDetail.yaml` | Replace `switchName` + `switchPort` with `connectedTo: NetworkConnection` |
| `WirelessNetworkClientDetail.yaml` | Replace top-level `ssid` + `signalStrength` with `connectedTo: WirelessConnection` |

### Updated paths (4, examples only)

`openapi/paths/network-devices.yaml`, `network-devices-id.yaml`, `network-clients.yaml`, `network-clients-id.yaml` — example blocks only; no structural change.

### Tooling and docs

- `.spectral.yaml` — new `enum-value-camelcase` rule.
- `API_GUIDELINES.md` — extend the Naming section with the digit-underscore-digit enum exception.

---

## Task 1: Add `units/Watts.yaml`

**Files:**
- Create: `openapi/components/schemas/units/Watts.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/units/Watts.yaml`:

```yaml
type: number
format: float
minimum: 0
description: A quantity of electrical power expressed in watts.
```

- [ ] **Step 2: Verify lint still passes**

Run: `make lint`
Expected: PASS. The schema is unreferenced, so `oas3-unused-component: warn` may produce a warning (warnings are allowed; only `error` severity fails lint).

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/units/Watts.yaml
git commit -m "Add units/Watts.yaml unit schema"
```

---

## Task 2: Add `NetworkLinkSpeed.yaml` enum

**Files:**
- Create: `openapi/components/schemas/NetworkLinkSpeed.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/NetworkLinkSpeed.yaml`:

```yaml
type: string
description: |
  Negotiated link speed of a network port, using UniFi nomenclature.
  - `e` — 10 Mbps (Ethernet)
  - `fe` — 100 Mbps (Fast Ethernet)
  - `gbe1` — 1 Gbps
  - `gbe2_5` — 2.5 Gbps
  - `gbe5` — 5 Gbps
  - `gbe10` — 10 Gbps
enum:
  - e
  - fe
  - gbe1
  - gbe2_5
  - gbe5
  - gbe10
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS (unreferenced-component warning OK).

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkLinkSpeed.yaml
git commit -m "Add NetworkLinkSpeed enum schema"
```

---

## Task 3: Add `NetworkPortState.yaml` enum

**Files:**
- Create: `openapi/components/schemas/NetworkPortState.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/NetworkPortState.yaml`:

```yaml
type: string
description: |
  Operational state of a physical network port.
  - `up` — link active
  - `down` — no link (nothing plugged in or peer unreachable)
  - `disabled` — administratively shut off in the controller
enum:
  - up
  - down
  - disabled
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkPortState.yaml
git commit -m "Add NetworkPortState enum schema"
```

---

## Task 4: Add `SwitchPortPoeMode.yaml` enum

**Files:**
- Create: `openapi/components/schemas/SwitchPortPoeMode.yaml`

Note: `off` must be quoted — bare `off` parses as YAML boolean `false` in some parsers.

- [ ] **Step 1: Create the file**

`openapi/components/schemas/SwitchPortPoeMode.yaml`:

```yaml
type: string
description: |
  Configured PoE behavior on a switch port.
  - `off` — PoE disabled
  - `auto` — auto-negotiated 802.3af/at/bt (PoE+/PoE++ are runtime outcomes of `auto`)
  - `passive24v` — legacy 24 V passive PoE
  - `passthrough` — forwards power from the switch's PoE input
enum:
  - 'off'
  - auto
  - passive24v
  - passthrough
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/SwitchPortPoeMode.yaml
git commit -m "Add SwitchPortPoeMode enum schema"
```

---

## Task 5: Add `enum-value-camelcase` Spectral rule and update guidelines

**Files:**
- Modify: `.spectral.yaml`
- Modify: `API_GUIDELINES.md`

The rule must permit `_` only between two digits (so `gbe2_5` is valid). Verify against the spec, which already contains `gbe2_5`, `passive24v`, etc.

- [ ] **Step 1: Add the rule to `.spectral.yaml`**

Append under the `# --- naming ---` section, after the `parameter-name-camelcase` rule:

```yaml
  enum-value-camelcase:
    description: |
      Enum values must be camelCase. A single underscore is allowed only
      between two digits (to encode a decimal point in numeric enums,
      e.g. `gbe2_5`).
    message: "Enum value '{{value}}' must be camelCase (with `_` allowed only between digits)."
    severity: error
    given: "$..enum[*]"
    then:
      function: pattern
      functionOptions:
        match: "^[a-z][a-zA-Z0-9]*(?:[0-9]_[0-9][a-zA-Z0-9]*)?$"
```

- [ ] **Step 2: Verify the rule passes against the current spec**

Run: `make lint`
Expected: PASS. If any existing enum value fails, capture the message — every current enum (`accessPoint`, `switch`, `gateway`, `unknown`, `connected`, `disconnected`, `wired`, `wireless`, plus those added in tasks 2–4) is intentionally camelCase or `gbe2_5`-style.

- [ ] **Step 3: TDD check — confirm the rule rejects bad values**

Temporarily edit `openapi/components/schemas/NetworkPortState.yaml` and add `- bad_value` to the enum.

Run: `make lint`
Expected: FAIL with `Enum value 'bad_value' must be camelCase (with '_' allowed only between digits).`

Revert the change: remove the `- bad_value` line.

Run: `make lint`
Expected: PASS.

- [ ] **Step 4: Update `API_GUIDELINES.md`**

In `API_GUIDELINES.md`, find the **Naming** section. Below the existing `- **JSON properties, enum values, operationIds, parameter names:** \`camelCase\`` bullet, add this paragraph (one blank line above and below):

```markdown
**Enum value exception:** When an enum value encodes a numeric quantity (`<unit><value>`), a single underscore is allowed *between two digits* to encode a decimal point — e.g. `gbe2_5` for 2.5 Gbps. The `_` is permitted only between two digits; everywhere else, the value must remain camelCase. This is enforced by the `enum-value-camelcase` Spectral rule.
```

- [ ] **Step 5: Run lint one more time**

Run: `make lint`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add .spectral.yaml API_GUIDELINES.md
git commit -m "Enforce enum-value camelCase with digit-underscore-digit exception

Adds the enum-value-camelcase Spectral rule and documents the
narrow exception in API_GUIDELINES.md. Permits enum values like
gbe2_5 (2.5 Gbps) while still rejecting underscores elsewhere."
```

---

## Task 6: Add `NetworkDeviceRef.yaml` and `NetworkClientRef.yaml`

**Files:**
- Create: `openapi/components/schemas/NetworkDeviceRef.yaml`
- Create: `openapi/components/schemas/NetworkClientRef.yaml`

- [ ] **Step 1: Create `NetworkDeviceRef.yaml`**

`openapi/components/schemas/NetworkDeviceRef.yaml`:

```yaml
type: object
description: Lightweight reference to a network device.
properties:
  kind:
    type: string
    enum: [device]
    description: Discriminator marking this reference as pointing to a device.
  id:
    type: string
    description: Globally unique device identifier (matches `NetworkDevice.id`).
    example: "unifi.switch-living-room"
  uri:
    type: string
    description: Relative API path to fetch this device's detail.
    example: "/network/devices/unifi.switch-living-room"
  name:
    type: string
    description: Human-readable device name.
    example: "Switch Living Room"
required:
  - kind
  - id
  - uri
  - name
```

- [ ] **Step 2: Create `NetworkClientRef.yaml`**

`openapi/components/schemas/NetworkClientRef.yaml`:

```yaml
type: object
description: Lightweight reference to a network client.
properties:
  kind:
    type: string
    enum: [client]
    description: Discriminator marking this reference as pointing to a client.
  id:
    type: string
    description: Globally unique client identifier (matches `NetworkClient.id`).
    example: "unifi.macbook-pro-3c"
  uri:
    type: string
    description: Relative API path to fetch this client's detail.
    example: "/network/clients/unifi.macbook-pro-3c"
  name:
    type: string
    description: Human-readable client name.
    example: "MacBook Pro"
required:
  - kind
  - id
  - uri
  - name
```

- [ ] **Step 3: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add openapi/components/schemas/NetworkDeviceRef.yaml openapi/components/schemas/NetworkClientRef.yaml
git commit -m "Add NetworkDeviceRef and NetworkClientRef schemas"
```

---

## Task 7: Add `NetworkConnectionRef.yaml` polymorphic wrapper

**Files:**
- Create: `openapi/components/schemas/NetworkConnectionRef.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/NetworkConnectionRef.yaml`:

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
  either resource type (e.g. `SwitchPort.connectedTo`).
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkConnectionRef.yaml
git commit -m "Add NetworkConnectionRef polymorphic wrapper"
```

---

## Task 8: Add `NetworkConnection.yaml`

**Files:**
- Create: `openapi/components/schemas/NetworkConnection.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/NetworkConnection.yaml`:

```yaml
type: object
description: |
  A connection to an upstream network device, including the physical
  port and the negotiated link speed. Used both as a device's `uplink`
  and as a wired client's `connectedTo`.
properties:
  device:
    $ref: "./NetworkDeviceRef.yaml"
  port:
    type: integer
    minimum: 1
    description: Physical port number on the upstream device.
    example: 8
  linkSpeed:
    $ref: "./NetworkLinkSpeed.yaml"
required:
  - device
  - port
  - linkSpeed
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkConnection.yaml
git commit -m "Add NetworkConnection schema (device + port + linkSpeed)"
```

---

## Task 9: Add `WirelessConnection.yaml`

**Files:**
- Create: `openapi/components/schemas/WirelessConnection.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/WirelessConnection.yaml`:

```yaml
type: object
description: |
  A wireless client's association with an access point, including the
  AP reference, the SSID it's joined to, and the AP-measured signal
  strength.
properties:
  device:
    $ref: "./NetworkDeviceRef.yaml"
  ssid:
    type: string
    description: SSID the client is associated with.
    example: "HomeNetwork"
  signalStrength:
    type: integer
    description: |
      Received signal strength in dBm as measured by the AP.
      Typical range: -30 (excellent) to -90 (poor).
    example: -62
required:
  - device
  - ssid
  - signalStrength
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/WirelessConnection.yaml
git commit -m "Add WirelessConnection schema (device + ssid + signalStrength)"
```

---

## Task 10: Add `NetworkTraffic.yaml`

**Files:**
- Create: `openapi/components/schemas/NetworkTraffic.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/NetworkTraffic.yaml`:

```yaml
type: object
description: |
  Network throughput stats for a device or port. Cumulative byte
  counters are measured since the reporting device's current uptime
  started; they reset when the device reboots.
properties:
  rxBytesTotal:
    allOf:
      - $ref: "./units/Bytes.yaml"
    description: Cumulative bytes received since the device's current uptime started.
    example: 12884901888
  txBytesTotal:
    allOf:
      - $ref: "./units/Bytes.yaml"
    description: Cumulative bytes transmitted since the device's current uptime started.
    example: 4294967296
  rxBytesPerSec:
    allOf:
      - $ref: "./units/BytesPerSec.yaml"
    description: Current receive throughput in bytes per second.
    example: 125000
  txBytesPerSec:
    allOf:
      - $ref: "./units/BytesPerSec.yaml"
    description: Current transmit throughput in bytes per second.
    example: 50000
required:
  - rxBytesTotal
  - txBytesTotal
  - rxBytesPerSec
  - txBytesPerSec
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkTraffic.yaml
git commit -m "Add NetworkTraffic schema"
```

---

## Task 11: Add `SwitchPort.yaml`

**Files:**
- Create: `openapi/components/schemas/SwitchPort.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/SwitchPort.yaml`:

```yaml
type: object
description: A physical port on a managed switch.
properties:
  number:
    type: integer
    minimum: 1
    description: Physical port number (1-based) as labelled on the switch.
    example: 7
  state:
    $ref: "./NetworkPortState.yaml"
  linkSpeed:
    allOf:
      - $ref: "./NetworkLinkSpeed.yaml"
    description: |
      Negotiated link speed. Omitted when `state` is not `up`.
  poeMode:
    $ref: "./SwitchPortPoeMode.yaml"
  poePowerWatts:
    allOf:
      - $ref: "./units/Watts.yaml"
    description: |
      Power currently being delivered through this port. Omitted when
      `poeMode` is `off` or when no powered device is attached.
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

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/SwitchPort.yaml
git commit -m "Add SwitchPort schema"
```

---

## Task 12: Add `AccessPointClient.yaml`

**Files:**
- Create: `openapi/components/schemas/AccessPointClient.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/AccessPointClient.yaml`:

```yaml
type: object
description: |
  A wireless client currently associated with an access point. Mirrors
  the structure of `WirelessConnection` from the AP side (carries a
  client reference instead of a device reference).
properties:
  client:
    $ref: "./NetworkClientRef.yaml"
  ssid:
    type: string
    description: SSID the client is associated with.
    example: "HomeNetwork"
  signalStrength:
    type: integer
    description: |
      Received signal strength in dBm as measured by the AP.
      Typical range: -30 (excellent) to -90 (poor).
    example: -62
required:
  - client
  - ssid
  - signalStrength
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/AccessPointClient.yaml
git commit -m "Add AccessPointClient schema"
```

---

## Task 13: Update `NetworkDevice.yaml` (list shape)

**Files:**
- Modify: `openapi/components/schemas/NetworkDevice.yaml`

Add `uri` (required). Remove `numClients` (moves to `AccessPointDetail`).

- [ ] **Step 1: Replace file contents**

Overwrite `openapi/components/schemas/NetworkDevice.yaml` with:

```yaml
type: object
description: A managed network device reported by a UniFi controller.
properties:
  id:
    type: string
    description: |
      Globally unique device identifier in the form `{controller}.{name}`,
      where `name` is the device name in kebab-case. The implementation
      ensures uniqueness across controllers.
      Use this value directly in path parameters.
    example: "unifi.ap-living-room"
  uri:
    type: string
    description: Relative API path to fetch this device's detail.
    example: "/network/devices/unifi.ap-living-room"
  name:
    type: string
    description: Human-readable device name as configured in the controller.
    example: "AP Living Room"
  mac:
    type: string
    description: Device MAC address in lowercase colon-separated notation.
    example: "aa:bb:cc:dd:ee:ff"
  ip:
    type: string
    description: Management IP address of the device.
    example: "192.168.1.5"
  type:
    $ref: "./NetworkDeviceType.yaml"
  status:
    $ref: "./NetworkDeviceStatus.yaml"
required:
  - id
  - uri
  - name
  - mac
  - ip
  - type
  - status
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS. The list endpoint example in `paths/network-devices.yaml` still references the old shape (`numClients` field) — Spectral does not enforce example/schema parity, so lint stays green. Examples are corrected in Task 23.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkDevice.yaml
git commit -m "NetworkDevice: add uri, remove numClients (moves to AP detail)"
```

---

## Task 14: Add `NetworkDeviceDetailBase.yaml`

**Files:**
- Create: `openapi/components/schemas/NetworkDeviceDetailBase.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/NetworkDeviceDetailBase.yaml`:

```yaml
allOf:
  - $ref: "./NetworkDevice.yaml"
  - type: object
    description: Detail fields shared by every device-detail variant.
    properties:
      model:
        type: string
        description: Device model identifier as reported by the controller.
        example: "U6-Lite"
      firmwareVersion:
        type: string
        description: Installed firmware version.
        example: "6.6.77.14522"
      uptime:
        type: integer
        description: Seconds since the device last (re)connected to the controller.
        example: 86400
      traffic:
        $ref: "./NetworkTraffic.yaml"
      uplink:
        allOf:
          - $ref: "./NetworkConnection.yaml"
        description: |
          The upstream device this one is connected through. Omitted for
          gateways (root of the topology).
    required:
      - model
      - firmwareVersion
      - uptime
      - traffic
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkDeviceDetailBase.yaml
git commit -m "Add NetworkDeviceDetailBase schema"
```

---

## Task 15: Add `SwitchDetail.yaml`, `GatewayDetail.yaml`, `UnknownDeviceDetail.yaml`

**Files:**
- Create: `openapi/components/schemas/SwitchDetail.yaml`
- Create: `openapi/components/schemas/GatewayDetail.yaml`
- Create: `openapi/components/schemas/UnknownDeviceDetail.yaml`

- [ ] **Step 1: Create `SwitchDetail.yaml`**

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
          $ref: "./SwitchPort.yaml"
    required:
      - type
      - ports
```

- [ ] **Step 2: Create `GatewayDetail.yaml`**

```yaml
allOf:
  - $ref: "./NetworkDeviceDetailBase.yaml"
  - type: object
    description: Detail for a security gateway / router.
    properties:
      type:
        type: string
        enum: [gateway]
    required:
      - type
```

- [ ] **Step 3: Create `UnknownDeviceDetail.yaml`**

```yaml
allOf:
  - $ref: "./NetworkDeviceDetailBase.yaml"
  - type: object
    description: |
      Catch-all detail variant for devices whose `type` is `unknown`.
      Carries only the shared base fields.
    properties:
      type:
        type: string
        enum: [unknown]
    required:
      - type
```

- [ ] **Step 4: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add openapi/components/schemas/SwitchDetail.yaml openapi/components/schemas/GatewayDetail.yaml openapi/components/schemas/UnknownDeviceDetail.yaml
git commit -m "Add SwitchDetail, GatewayDetail, UnknownDeviceDetail variants"
```

---

## Task 16: Add `AccessPointDetail.yaml`

**Files:**
- Create: `openapi/components/schemas/AccessPointDetail.yaml`

- [ ] **Step 1: Create the file**

`openapi/components/schemas/AccessPointDetail.yaml`:

```yaml
allOf:
  - $ref: "./NetworkDeviceDetailBase.yaml"
  - type: object
    description: Detail for a wireless access point, including its associated clients.
    properties:
      type:
        type: string
        enum: [accessPoint]
      numClients:
        type: integer
        description: Number of wireless clients currently associated with this AP.
        example: 5
      connectedClients:
        type: array
        description: |
          Wireless clients currently associated with this AP. Empty
          array (`[]`) when none, never null.
        items:
          $ref: "./AccessPointClient.yaml"
    required:
      - type
      - numClients
      - connectedClients
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/AccessPointDetail.yaml
git commit -m "Add AccessPointDetail variant with connectedClients"
```

---

## Task 17: Replace `NetworkDeviceDetail.yaml` with the polymorphic wrapper

**Files:**
- Modify: `openapi/components/schemas/NetworkDeviceDetail.yaml`

This is a structural breaking change: the schema goes from a flat `allOf` to an `anyOf` wrapper with a discriminator.

- [ ] **Step 1: Replace file contents**

Overwrite `openapi/components/schemas/NetworkDeviceDetail.yaml` with:

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
description: |
  Polymorphic detail for a managed network device. The concrete shape
  depends on `type`: `switch` adds physical ports, `accessPoint` adds
  associated wireless clients, `gateway` and `unknown` carry only the
  shared base fields.
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkDeviceDetail.yaml
git commit -m "Make NetworkDeviceDetail polymorphic over device type

Replaces the flat allOf with anyOf+discriminator over SwitchDetail,
AccessPointDetail, GatewayDetail, and UnknownDeviceDetail. Per-type
fields (ports, connectedClients) now live on the appropriate variant.

BREAKING: consumers reading the previous flat shape must dispatch on
\`type\` to read variant-specific fields."
```

---

## Task 18: Update `NetworkClient.yaml` (list shape)

**Files:**
- Modify: `openapi/components/schemas/NetworkClient.yaml`

Add `uri` (required).

- [ ] **Step 1: Replace file contents**

Overwrite `openapi/components/schemas/NetworkClient.yaml` with:

```yaml
type: object
description: A client device currently connected to the network.
properties:
  id:
    type: string
    description: |
      Globally unique client identifier in the form
      `{controller}.{hostname}-{macPrefix}`, where `hostname` is the
      client's name in kebab-case and `macPrefix` is the first two
      characters of the MAC address for disambiguation. The
      implementation ensures uniqueness across controllers.
    example: "unifi.macbook-pro-3c"
  uri:
    type: string
    description: Relative API path to fetch this client's detail.
    example: "/network/clients/unifi.macbook-pro-3c"
  name:
    type: string
    description: |
      Display name for the client: the user-assigned alias when set,
      otherwise the DHCP hostname.
    example: "MacBook Pro"
  mac:
    type: string
    description: Client MAC address in lowercase colon-separated notation.
    example: "3c:22:fb:09:aa:b1"
  ip:
    type: string
    description: Current IP address of the client.
    example: "192.168.1.100"
  connectionType:
    $ref: "./NetworkClientConnectionType.yaml"
required:
  - id
  - uri
  - name
  - mac
  - connectionType
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/NetworkClient.yaml
git commit -m "NetworkClient: add uri field"
```

---

## Task 19: Restructure `WiredNetworkClientDetail.yaml`

**Files:**
- Modify: `openapi/components/schemas/WiredNetworkClientDetail.yaml`

Replace `switchName` + `switchPort` with `connectedTo: NetworkConnection`. Breaking change.

- [ ] **Step 1: Replace file contents**

Overwrite `openapi/components/schemas/WiredNetworkClientDetail.yaml` with:

```yaml
allOf:
  - $ref: "./NetworkClient.yaml"
  - type: object
    description: Detail for a wired network client, including the upstream switch and port it's plugged into.
    properties:
      connectionType:
        type: string
        enum: [wired]
      connectedTo:
        $ref: "./NetworkConnection.yaml"
      uptime:
        type: integer
        description: Seconds since the client's current session started.
        example: 604800
    required:
      - connectionType
      - connectedTo
      - uptime
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/WiredNetworkClientDetail.yaml
git commit -m "WiredNetworkClientDetail: replace switchName/switchPort with connectedTo

BREAKING: switchName and switchPort fields are removed; the upstream
switch reference now lives under connectedTo (a NetworkConnection,
matching the device-side uplink shape)."
```

---

## Task 20: Restructure `WirelessNetworkClientDetail.yaml`

**Files:**
- Modify: `openapi/components/schemas/WirelessNetworkClientDetail.yaml`

Move `ssid` and `signalStrength` into a new `connectedTo: WirelessConnection`. Breaking change.

- [ ] **Step 1: Replace file contents**

Overwrite `openapi/components/schemas/WirelessNetworkClientDetail.yaml` with:

```yaml
allOf:
  - $ref: "./NetworkClient.yaml"
  - type: object
    description: Detail for a wireless network client, including its association with an AP.
    properties:
      connectionType:
        type: string
        enum: [wireless]
      connectedTo:
        $ref: "./WirelessConnection.yaml"
      uptime:
        type: integer
        description: Seconds since the client's current session started.
        example: 7200
    required:
      - connectionType
      - connectedTo
      - uptime
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/components/schemas/WirelessNetworkClientDetail.yaml
git commit -m "WirelessNetworkClientDetail: group ssid/signalStrength under connectedTo

BREAKING: top-level ssid and signalStrength fields are removed; both
now live inside connectedTo (a WirelessConnection), symmetric with
the device-side AP→client association shape."
```

---

## Task 21: Run `make bundle` and verify schemas resolve

**Files:** none (verification only).

- [ ] **Step 1: Bundle the spec**

Run: `make bundle`
Expected: Produces `dist/openapi.bundled.yaml` and `dist/openapi.bundled.json` without errors.

- [ ] **Step 2: Verify the new schemas appear in the bundle**

Run: `grep -c "NetworkDeviceRef\|NetworkClientRef\|NetworkConnection\|WirelessConnection\|NetworkTraffic\|SwitchPort\|NetworkLinkSpeed\|NetworkPortState\|SwitchPortPoeMode\|NetworkDeviceDetailBase\|SwitchDetail\|AccessPointDetail\|GatewayDetail\|UnknownDeviceDetail\|AccessPointClient" dist/openapi.bundled.yaml`
Expected: Non-zero count (Redocly inlines refs; the schemas appear as named components or inlined definitions in the bundle).

- [ ] **Step 3: Verify discriminator wiring**

Run: `grep -A 5 "propertyName: type" dist/openapi.bundled.yaml | head -30`
Expected: Output shows the `mapping` entries for `switch`, `accessPoint`, `gateway`, `unknown` referencing the variant schemas.

- [ ] **Step 4: No commit required** (this task is verification only).

---

## Task 22: Update `paths/network-devices.yaml` example

**Files:**
- Modify: `openapi/paths/network-devices.yaml`

Update the list-endpoint example so each item carries `uri` and AP entries no longer carry `numClients`.

- [ ] **Step 1: Replace the example block**

In `openapi/paths/network-devices.yaml`, replace the `examples:` block (currently from `examples:` through to the end of the `value:` list, lines ~25–55 of the original file) with:

```yaml
          examples:
            typicalHomelab:
              summary: A gateway, a switch, and two access points.
              value:
                items:
                  - id: "unifi.usg"
                    uri: "/network/devices/unifi.usg"
                    name: "USG"
                    mac: "aa:bb:cc:dd:00:01"
                    ip: "192.168.1.1"
                    type: gateway
                    status: connected
                  - id: "unifi.switch-living-room"
                    uri: "/network/devices/unifi.switch-living-room"
                    name: "Switch Living Room"
                    mac: "aa:bb:cc:dd:00:02"
                    ip: "192.168.1.2"
                    type: switch
                    status: connected
                  - id: "unifi.ap-living-room"
                    uri: "/network/devices/unifi.ap-living-room"
                    name: "AP Living Room"
                    mac: "aa:bb:cc:dd:00:03"
                    ip: "192.168.1.3"
                    type: accessPoint
                    status: connected
                  - id: "unifi.ap-office"
                    uri: "/network/devices/unifi.ap-office"
                    name: "AP Office"
                    mac: "aa:bb:cc:dd:00:04"
                    ip: "192.168.1.4"
                    type: accessPoint
                    status: connected
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add openapi/paths/network-devices.yaml
git commit -m "network-devices: update list example with uri, drop numClients"
```

---

## Task 23: Update `paths/network-devices-id.yaml` examples (one per variant)

**Files:**
- Modify: `openapi/paths/network-devices-id.yaml`

Replace the single example with four — one per device variant — using the polymorphic detail shape.

- [ ] **Step 1: Replace the `200` response example block**

In `openapi/paths/network-devices-id.yaml`, locate the `responses → "200" → content → application/json` block. Replace the existing `example:` block with this `examples:` block (note `examples` plural):

```yaml
          examples:
            switch:
              summary: A managed switch with three ports.
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
                    poeMode: 'off'
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
                    state: up
                    linkSpeed: gbe2_5
                    poeMode: auto
                    poePowerWatts: 4.5
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
                    traffic:
                      rxBytesTotal: 0
                      txBytesTotal: 0
                      rxBytesPerSec: 0
                      txBytesPerSec: 0
            accessPoint:
              summary: An access point with one associated wireless client.
              value:
                id: "unifi.ap-living-room"
                uri: "/network/devices/unifi.ap-living-room"
                name: "AP Living Room"
                mac: "aa:bb:cc:dd:00:03"
                ip: "192.168.1.3"
                type: accessPoint
                status: connected
                model: "U6-Lite"
                firmwareVersion: "6.6.77.14522"
                uptime: 86400
                traffic:
                  rxBytesTotal: 8589934592
                  txBytesTotal: 17179869184
                  rxBytesPerSec: 80000
                  txBytesPerSec: 200000
                uplink:
                  device:
                    kind: device
                    id: "unifi.switch-living-room"
                    uri: "/network/devices/unifi.switch-living-room"
                    name: "Switch Living Room"
                  port: 7
                  linkSpeed: gbe2_5
                numClients: 1
                connectedClients:
                  - client:
                      kind: client
                      id: "unifi.macbook-pro-3c"
                      uri: "/network/clients/unifi.macbook-pro-3c"
                      name: "MacBook Pro"
                    ssid: "HomeNetwork"
                    signalStrength: -62
            gateway:
              summary: The security gateway / router (root of the topology).
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
            unknown:
              summary: A device whose role the controller does not recognise.
              value:
                id: "unifi.unknown-1"
                uri: "/network/devices/unifi.unknown-1"
                name: "Unknown 1"
                mac: "aa:bb:cc:dd:00:99"
                ip: "192.168.1.99"
                type: unknown
                status: disconnected
                model: "unknown"
                firmwareVersion: "unknown"
                uptime: 0
                traffic:
                  rxBytesTotal: 0
                  txBytesTotal: 0
                  rxBytesPerSec: 0
                  txBytesPerSec: 0
```

- [ ] **Step 2: Update the operation description**

In the same file, replace the existing operation `description:` (the paragraph mentioning "model, firmware version, connectivity status, and uptime") with:

```yaml
  description: |
    Returns a single network device by its composite identifier
    (`{controller}.{name}`, e.g. `unifi.ap-living-room`). The response
    is polymorphic on the device `type`: switches include their physical
    `ports`, access points include `connectedClients` and `numClients`,
    gateways and unknown devices carry only the shared base fields. All
    variants include `traffic` stats and (except gateways) an `uplink`
    reference to the upstream device.
```

- [ ] **Step 3: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add openapi/paths/network-devices-id.yaml
git commit -m "network-devices/{deviceId}: examples per variant, polymorphic description"
```

---

## Task 24: Update `paths/network-clients.yaml` example

**Files:**
- Modify: `openapi/paths/network-clients.yaml`

Add `uri` to each item in the list example. First read the file to see its exact current structure.

- [ ] **Step 1: Read the file**

Run: `cat openapi/paths/network-clients.yaml`
Note the structure of the `examples:` block.

- [ ] **Step 2: Update each item in the example**

For every object inside the `items:` array of the `value:` block, add a `uri:` field directly after the `id:` field. Pattern: `uri: "/network/clients/<id>"`.

Example transformation — before:

```yaml
                  - id: "unifi.macbook-pro-3c"
                    name: "MacBook Pro"
```

After:

```yaml
                  - id: "unifi.macbook-pro-3c"
                    uri: "/network/clients/unifi.macbook-pro-3c"
                    name: "MacBook Pro"
```

Apply to every list item.

- [ ] **Step 3: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add openapi/paths/network-clients.yaml
git commit -m "network-clients: add uri to list examples"
```

---

## Task 25: Update `paths/network-clients-id.yaml` examples

**Files:**
- Modify: `openapi/paths/network-clients-id.yaml`

Replace both example payloads with the new shapes.

- [ ] **Step 1: Replace the `examples:` block under the `200` response**

In `openapi/paths/network-clients-id.yaml`, replace the existing `wirelessClient` and `wiredClient` example values with:

```yaml
          examples:
            wirelessClient:
              summary: A wireless client associated with an AP.
              value:
                id: "unifi.macbook-pro-3c"
                uri: "/network/clients/unifi.macbook-pro-3c"
                name: "MacBook Pro"
                mac: "3c:22:fb:09:aa:b1"
                ip: "192.168.1.101"
                connectionType: wireless
                connectedTo:
                  device:
                    kind: device
                    id: "unifi.ap-living-room"
                    uri: "/network/devices/unifi.ap-living-room"
                    name: "AP Living Room"
                  ssid: "HomeNetwork"
                  signalStrength: -62
                uptime: 7200
            wiredClient:
              summary: A wired client plugged into a switch port.
              value:
                id: "unifi.nas-1-68"
                uri: "/network/clients/unifi.nas-1-68"
                name: "nas-1"
                mac: "68:d7:9a:12:bb:c2"
                ip: "192.168.1.10"
                connectionType: wired
                connectedTo:
                  device:
                    kind: device
                    id: "unifi.switch-living-room"
                    uri: "/network/devices/unifi.switch-living-room"
                    name: "Switch Living Room"
                  port: 8
                  linkSpeed: gbe2_5
                uptime: 604800
```

- [ ] **Step 2: Update the operation description**

Find the existing operation `description:` block. Replace it with:

```yaml
  description: |
    Returns a single connected client by its composite identifier
    (`{controller}.{hostname}-{macPrefix}`, e.g. `unifi.macbook-pro-3c`).
    The response shape varies by `connectionType`: wired clients carry
    a `connectedTo` referencing the upstream switch (with port and link
    speed); wireless clients carry a `connectedTo` referencing the AP
    they are associated with (with SSID and signal strength).

    Only currently connected clients can be retrieved; requesting an
    offline client returns 404.
```

- [ ] **Step 3: Run lint**

Run: `make lint`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add openapi/paths/network-clients-id.yaml
git commit -m "network-clients/{clientId}: update examples and description for new shapes"
```

---

## Task 26: Final verification

**Files:** none.

- [ ] **Step 1: Re-bundle and inspect the docs preview**

Run: `make bundle`
Expected: Produces `dist/openapi.bundled.yaml` and `dist/openapi.bundled.json` cleanly.

Optionally run: `make preview` (opens live-reload docs on http://localhost:8080). Manually verify in browser:
- `GET /network/devices/{deviceId}` shows four example tabs (switch, accessPoint, gateway, unknown).
- Switch example renders `ports[]` with PoE/speed/traffic/connectedTo.
- AP example renders `connectedClients[]` with `client`, `ssid`, `signalStrength`.
- Wired client example shows `connectedTo: { device, port, linkSpeed }`.
- Wireless client example shows `connectedTo: { device, ssid, signalStrength }`.

Stop the preview server when done (Ctrl+C).

- [ ] **Step 2: Run the breaking-change check**

Run: `make breaking BASE=origin/main`
Expected: oasdiff reports breaking changes. Specifically, expect entries for:
1. `NetworkDeviceDetail` shape changes (flat → anyOf).
2. `NetworkDevice.numClients` removal (now in `AccessPointDetail`).
3. `WiredNetworkClientDetail.switchName` and `.switchPort` removal.
4. `WirelessNetworkClientDetail.ssid` and `.signalStrength` removal (moved into `connectedTo`).

Capture the report output for the PR description.

- [ ] **Step 3: Final lint sanity**

Run: `make lint`
Expected: PASS with no errors. Warnings are acceptable.

- [ ] **Step 4: No commit required** (verification only).

---

## Self-review summary

**Spec coverage** (every section of the spec mapped to at least one task):

| Spec section | Task(s) |
|---|---|
| Cross-resource references | 6, 7 |
| Traffic stats | 10 |
| Switch port + supporting enums + unit | 1, 2, 3, 4, 11 |
| Connections (NetworkConnection, WirelessConnection) | 8, 9 |
| Polymorphic device detail (list, base, variants, wrapper) | 13, 14, 15, 16, 17 |
| AP-side client association | 12 |
| Updates to NetworkClient (list + wired + wireless) | 18, 19, 20 |
| Guidelines + lint rule | 5 |
| Endpoint example updates | 22, 23, 24, 25 |
| Bundle / breaking-change verification | 21, 26 |

**Type consistency:** Field names and types are consistent across tasks — `connectedTo`, `uplink`, `traffic`, `linkSpeed`, `poeMode`, `poePowerWatts`, `ssid`, `signalStrength`, `numClients`, `connectedClients` all match the spec.

**Notable risks for the executor:**
- YAML boolean `off`: always quote it as `'off'` in `SwitchPortPoeMode.yaml` and in examples (`poeMode: 'off'`).
- The Spectral rule `enum-value-camelcase` is added in Task 5 *before* the schemas that exercise its exception (`gbe2_5`). The rule is intentionally written so existing camelCase values continue to pass, and `gbe2_5` (added in Task 2 just before) is the first value that exercises the exception — Task 5's lint must pass after both schemas are in place.
- `make breaking BASE=origin/main` requires the local branch to be off of `origin/main`. If working directly on `main`, the BASE comparison will be HEAD-vs-HEAD; in that case, capture the report by running it *before* merging on a feature branch instead.
