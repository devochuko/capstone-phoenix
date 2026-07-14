# Project values (single source of truth)

Keep this file in sync with whatever you actually use — every manifest,
Ingress host, and doc below should match these exactly.

| Key                  | Value                              |
|----------------------|-------------------------------------|
| Domain               | `pilgrim.name.ng`                  |
| App hostname         | `taskapp.pilgrim.name.ng`          |
| API path             | same-origin `/api` on the app host (no separate api. subdomain) |
| Cloud                | AWS                                |
| Region               | `eu-north-1`                       |
| Instance type        | `t3.small`                         |
| Node count           | 1 control-plane + 2 workers        |
| Ingress controller   | k3s's bundled Traefik (kept, NOT disabled — community ingress-nginx is retired/archived as of March 2026, unmaintained) |
| GitOps controller    | Argo CD                            |
| TLS issuer           | cert-manager + Let's Encrypt (HTTP-01 via Traefik) |
| Namespace            | `taskapp`                          |
| Frontend image       | `ghcr.io/ts-a-devops/taskapp-frontend:v1.0.0` |
| Backend image        | `ghcr.io/ts-a-devops/taskapp-backend:v1.0.0`  |
| Advanced trio        | HPA, NetworkPolicy, PDB + graceful shutdown |

DNS you need to create (at your domain registrar / DNS provider for
`pilgrim.name.ng`), once the control-plane's public IP is known from
`terraform output control_plane_public_ip`:

```
A    taskapp.pilgrim.name.ng    ->   <control-plane public IP>
```

(Traefik ships as a k3s-managed `DaemonSet` using `hostNetwork`-style
`ServiceLB` by default, reachable on the control-plane's public IP on
80/443 — exact wiring documented in `docs/ARCHITECTURE.md` once the
platform layer is in place.)
