# Design: Network SSID, VLAN, and WAN Endpoints

**Date:** 2026-05-22  
**Status:** Approved

## Context

The `/network` group currently exposes devices, clients, and topology. Three logical network constructs — WiFi networks (SSIDs), VLANs, and WAN connections — are missing. These are needed to give consumers visibility into the network configuration layer, not just the device/client layer.

## URLs

All endpoints are read-only (`GET`) and scoped to `read:network`.

```
GET /network/ssids                        → list SSIDs
GET /network/ssids/{ssidId}               → SSID detail

GET /network/vlans                        → list VLANs
GET /network/vlans/{vlanId}               → VLAN detail

GET /network/wans                         → list WAN connections
GET /network/wans/{wanId}                 → WAN detail
```

Path parameters use the composite `{controller}.{name}` format (e.g. `unifi.iot`, `unifi.wan1`), consistent with `/network/devices` and `/network/clients`.

## Schema Design

All resources use the standard list/detail split via `allOf`. No polymorphism — differences between DHCP modes are expressed as optional fields with descriptions.

### SSIDs

**`Ssid`** (list item):
- `id`: string — composite ID
- `uri`: string — self-link
- `name`: string — broadcast SSID name
- `vlanId`: integer — numeric VLAN tag this network is on
- `bands`: `WifiBand[]` — bands this SSID broadcasts on
- `numClients`: integer — current connected client count

**`SsidDetail`** (allOf Ssid, adds):
- `securityProtocol`: `WifiSecurityProtocol`
- `clients`: `NetworkClientRef[]` — refs to connected clients
- `broadcastingAps`: `NetworkDeviceRef[]` — refs to APs broadcasting this SSID

**`SsidList`**: `{ items: Ssid[] }`

**`WifiBand`** enum: `band2g`, `band5g`, `band6g`

**`WifiSecurityProtocol`** enum: `open`, `wpa2`, `wpa3`, `wpa2Wpa3`, `wpa2Enterprise`, `wpa3Enterprise`, `wpa2Wpa3Enterprise`

### VLANs

**`Vlan`** (list item):
- `id`: string — composite ID
- `uri`: string — self-link
- `name`: string — human-readable name
- `vlanId`: integer — numeric VLAN tag (1–4094)
- `subnet`: string — CIDR notation, e.g. `192.168.10.0/24`

**`VlanDetail`** (allOf Vlan, adds):
- `gatewayIp`: `IpAddress`
- `broadcastIp`: `IpAddress`
- `dhcpMode`: `DhcpMode`
- `dhcpRange`: `DhcpRange` — present only when `dhcpMode` is `server`
- `relayServer`: `IpAddress` — present only when `dhcpMode` is `relay`
- `dnsServers`: `IpAddress[]`

**`VlanList`**: `{ items: Vlan[] }`

**`DhcpMode`** enum: `server`, `relay`, `disabled`

**`DhcpRange`**: `{ start: IpAddress, end: IpAddress }`

### WANs

**`Wan`** (list item):
- `id`: string — composite ID
- `uri`: string — self-link
- `name`: string — human-readable name
- `ipAddress`: `IpAddress` — current public IP
- `uptime`: `Seconds` — seconds the connection has been up
- `status`: `WanStatus`

**`WanDetail`** (allOf Wan, adds):
- `dnsServers`: `IpAddress[]`

**`WanList`**: `{ items: Wan[] }`

**`WanStatus`** enum: `connected`, `disconnected`, `failover`

## New Shared Schemas

Two new reusable schemas to create before the resource schemas:

| Schema | Location | Description |
|---|---|---|
| `IpAddress` | `openapi/components/schemas/IpAddress.yaml` | `type: string, format: ipv4` — used for all IP address fields across all three resources |
| `Seconds` | `openapi/components/schemas/units/Seconds.yaml` | `type: integer` — duration in seconds; `uptime` on WAN and existing device schemas share this type |

## Files to Create

### Path files (6 new)
```
openapi/paths/network-ssids.yaml
openapi/paths/network-ssids-id.yaml
openapi/paths/network-vlans.yaml
openapi/paths/network-vlans-id.yaml
openapi/paths/network-wans.yaml
openapi/paths/network-wans-id.yaml
```

### Schema files (16 new)
```
openapi/components/schemas/IpAddress.yaml
openapi/components/schemas/units/Seconds.yaml
openapi/components/schemas/Ssid.yaml
openapi/components/schemas/SsidDetail.yaml
openapi/components/schemas/SsidList.yaml
openapi/components/schemas/WifiBand.yaml
openapi/components/schemas/WifiSecurityProtocol.yaml
openapi/components/schemas/Vlan.yaml
openapi/components/schemas/VlanDetail.yaml
openapi/components/schemas/VlanList.yaml
openapi/components/schemas/DhcpMode.yaml
openapi/components/schemas/DhcpRange.yaml
openapi/components/schemas/Wan.yaml
openapi/components/schemas/WanDetail.yaml
openapi/components/schemas/WanList.yaml
openapi/components/schemas/WanStatus.yaml
```

### Root document update
Add 6 new path entries to `openapi/openapi.yaml` under `paths:`.

## Conventions to Follow

- Every operation needs `operationId` (camelCase), `description`, `tags: [network]`
- Every operation must declare `401` and `500` responses; detail endpoints also `404`
- Error responses use `$ref` to existing shared responses (`Unauthorized.yaml`, `NotFound.yaml`, `InternalServerError.yaml`, `BadRequest.yaml`, `TooManyRequests.yaml`, `Forbidden.yaml`)
- All response schemas use `$ref` to components — no inline schemas
- Path files reference component files via relative `$ref` paths (e.g. `../components/schemas/Ssid.yaml`)
- IP address fields use `allOf: [$ref: "./IpAddress.yaml"]` pattern

## Verification

```sh
make lint     # Spectral + Redocly — must pass with zero errors
make bundle   # Produce dist/openapi.bundled.{yaml,json}
make preview  # Browse http://localhost:8080 and verify all 6 endpoints appear with correct fields
```
