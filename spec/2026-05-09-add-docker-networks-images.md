# Add Docker Networks & Images

## Context

Adding `/docker/networks` and `/docker/images` resources to the homelab OpenAPI spec. Design is grounded in actual DSM API responses probed live against the NAS.

**Key finding:** `SYNO.Docker.Network` and `SYNO.Docker.Image` each expose only a `list` method (no `get`). Detail endpoints are supported by the server filtering the list by ID. Network and image data is flat — no nested IPAM objects.

---

## Actual DSM Response Shapes

**`SYNO.Docker.Network list`** → `data.network[]`:
```json
{
  "id": "50e352a4de66...",
  "name": "grafana_default",
  "driver": "bridge",
  "enable_ipv6": false,
  "gateway": "172.22.0.1",
  "subnet": "172.22.0.0/16",
  "iprange": "",
  "containers": ["cadvisor", "grafana", "loki", "prometheus"]
}
```
Host network has empty `gateway` and `subnet`. `iprange` is empty when not configured.

**`SYNO.Docker.Image list`** → `data.images[]`:
```json
{
  "id": "sha256:925ff61909ae...",
  "repository": "ghcr.io/immich-app/immich-server",
  "tags": ["v1.120.0"],
  "size": 524288000,
  "virtual_size": 1073741824,
  "created": 1727386302,
  "description": ""
}
```
`repository` includes the registry prefix when non-Docker Hub. No `architecture`, `os`, `layers`, `entrypoint`, `cmd`, or `exposedPorts` in the DSM response.

---

## Schema Design

### Networks

**`DockerNetwork.yaml`** (list item):
- `id` — `{device}.{name}` (composite, e.g. `nas-1.immich_default`)
- `name` — DSM `name`
- `device` — backend identifier
- `connectedContainers` — `integer` — `len(containers)`

**`DockerNetworkDetail.yaml`** (`allOf DockerNetwork` + extras):
- `driver` — DSM `driver`
- `subnet` — string, optional (CIDR) — DSM `subnet` (omit when empty)
- `gateway` — string, optional (IP) — DSM `gateway` (omit when empty)
- `ipRange` — string, optional (CIDR) — DSM `iprange` (omit when empty)
- `containers` — `string[]` — DSM `containers` (container names)

**`DockerNetworkList.yaml`**: `{ items: DockerNetwork[] }`

### Images

**`DockerImage.yaml`** (list item):
- `id` — `{device}.{shortId}` where `shortId` = first 12 chars of sha256 digest (e.g. `nas-1.925ff61909ae`)
- `device` — backend identifier
- `repository` — full repo name incl. registry prefix — DSM `repository`
- `tags` — `string[]` — DSM `tags`
- `size` — `allOf Bytes.yaml` — DSM `size`

**`DockerImageDetail.yaml`** (`allOf DockerImage` + extras):
- `created` — `date-time` — DSM `created` (Unix timestamp → ISO 8601)
- `virtualSize` — `allOf Bytes.yaml` — DSM `virtual_size`
- `description` — string, optional — DSM `description` (omit when empty)

**`DockerImageList.yaml`**: `{ items: DockerImage[] }`

---

## Files Created

### Schemas
- `openapi/components/schemas/DockerNetwork.yaml`
- `openapi/components/schemas/DockerNetworkDetail.yaml`
- `openapi/components/schemas/DockerNetworkList.yaml`
- `openapi/components/schemas/DockerImage.yaml`
- `openapi/components/schemas/DockerImageDetail.yaml`
- `openapi/components/schemas/DockerImageList.yaml`

### Paths
- `openapi/paths/docker-networks.yaml` — `GET /docker/networks` `listDockerNetworks`
- `openapi/paths/docker-networks-id.yaml` — `GET /docker/networks/{networkId}` `getDockerNetwork`
- `openapi/paths/docker-images.yaml` — `GET /docker/images` `listDockerImages`
- `openapi/paths/docker-images-id.yaml` — `GET /docker/images/{imageId}` `getDockerImage`

### Updated
- `openapi/openapi.yaml` — docker tag description + 4 new path refs
