# Architecture

## 1. Topology diagram

```
                              Internet
                                 │
                          DNS: A record
                taskapp.pilgrim.name.ng → control-plane public IP
                                 │
                                 ▼
                 ┌───────────────────────────────┐
                 │   control-plane (k3s server)    │
                 │   Traefik (DaemonSet/Service,   │
                 │   ports 80/443 on every node)   │
                 └───────────────┬─────────────────┘
                                 │ TLS terminated here
                                 │ (cert issued by cert-manager +
                                 │  Let's Encrypt, HTTP-01 challenge)
                 ┌───────────────┼─────────────────┐
                 │               │                 │
                 ▼               ▼                 ▼
         frontend Service   backend Service   (Traefik routes by
         (ClusterIP)        (ClusterIP)        path: / vs /api)
                 │               │
        ┌────────┴────────┐      │        ┌──────────────────┐
        ▼                 ▼      │        │                  │
   frontend Pod      frontend Pod│   ┌─────▼──────┐    ┌──────▼─────┐
   (worker-1)         (worker-2) │   │ backend Pod │    │ backend Pod │
                                 │   │ (worker-1)  │    │ (worker-2)  │
                                 │   └──────┬──────┘    └──────┬─────┘
                                 │          │                  │
                                 │          └────────┬─────────┘
                                 │                   ▼
                                 │          postgres Service (headless)
                                 │                   │
                                 │                   ▼
                                 │           postgres-0 Pod
                                 │           (StatefulSet, 1 replica)
                                 │           PVC on local-path storage
                                 │           (pinned to whichever node
                                 │            it's scheduled on)
                                 │
                          (control-plane also runs
                           Argo CD + cert-manager,
                           not shown above for clarity)

Nodes:
  control-plane  — k3s server, eu-north-1a, t3.small
  worker-1       — k3s agent,  eu-north-1a, t3.small
  worker-2       — k3s agent,  eu-north-1a, t3.small
```

`topologySpreadConstraints` (maxSkew: 1, `whenUnsatisfiable: DoNotSchedule`)
on both the backend and frontend Deployments is what guarantees the two
replicas of each tier land on different nodes — see
`manifests/app/05-backend-deployment.yaml` and
`manifests/app/06-frontend-deployment.yaml`.

## 2. Node & network

**Nodes** (all `t3.small`, 2 vCPU / 2 GiB RAM, Ubuntu 24.04 LTS,
`eu-north-1a`):

| Node | Role | Notes |
|---|---|---|
| control-plane | k3s server | Single server — no etcd HA. The capstone explicitly says control-plane HA/quorum is not the difficulty target here; one k3s server is sufficient. |
| worker-1 | k3s agent | |
| worker-2 | k3s agent | |

**CIDR / subnet choices**

- VPC: `10.42.0.0/16` — large enough to grow the node count without
  re-planning, small enough not to collide with common home/office LAN
  ranges if you ever peer or VPN into it.
- Single public subnet: `10.42.1.0/24`, single AZ (`eu-north-1a`).
  All 3 nodes live in the same subnet/AZ — see `infra/terraform/modules/network`.
  This is a deliberate scope decision: the brief explicitly excludes
  control-plane HA / etcd quorum from the difficulty target, so
  multi-AZ networking (which exists to protect against AZ-level
  failure of the control plane) wasn't worth the added complexity for
  a 3-week solo capstone. The failover demo (§6 deliverable) targets
  *worker* node failure, which multi-AZ wouldn't change the outcome of
  anyway, since Pods reschedule onto the remaining worker regardless of
  AZ layout.

**Firewall** (`infra/terraform/modules/security_group`):

| Port | Source | Why |
|---|---|---|
| 22 | your IP only (`admin_cidr` var) | SSH — never `0.0.0.0/0` |
| 80 | `0.0.0.0/0` | HTTP — Traefik redirects to HTTPS; also needed for cert-manager's HTTP-01 ACME challenge |
| 443 | `0.0.0.0/0` | HTTPS — TLS terminated by Traefik using the cert-manager-issued certificate |
| 6443 (k8s API) | internal only (self-referencing SG rule) | **Never exposed to the internet.** kubectl from your laptop works because the Ansible role rewrites the fetched kubeconfig's `server:` field to the control-plane's public IP — but that traffic still only reaches 6443 because... |

Wait — actually 6443 *is* reachable from your laptop via the public IP,
since `kubectl get nodes` from outside the cluster is an explicit
acceptance criterion in the brief (§3). Here's the actual rule: 6443 is
allowed from `admin_cidr` (your IP) **only**, same as SSH — not from
`0.0.0.0/0`. It is genuinely closed to the rest of the internet, just
not to you. All other internal traffic (kubelet 10250, flannel VXLAN
8472/udp, NodePorts) is restricted to the security group's own members
only (node-to-node), never reachable from outside the VPC at all,
including from your own IP.

*(If you want kubectl-from-laptop access without opening 6443 to your
IP either, the alternative is SSH tunneling: `ssh -L 6443:localhost:6443
ubuntu@<control-plane-ip>` and pointing kubeconfig at `localhost:6443`
— not implemented here, but worth knowing as a stricter option.)*

## 3. Request flow

A browser requests `https://taskapp.pilgrim.name.ng/`. DNS resolves
that A record to the control-plane node's public IP. The packet hits
port 443, which the security group allows from anywhere, and Traefik
(k3s's bundled ingress controller, listening on every node) accepts the
TLS handshake using the certificate cert-manager obtained from Let's
Encrypt for that hostname (stored in the `taskapp-tls` Secret,
referenced by `manifests/app/07-ingress.yaml`). Traefik then looks at
the request path: anything under `/api` is routed to the `backend`
ClusterIP Service on port 5000, which load-balances across the 2
backend Pods (Flask) spread across `worker-1` and `worker-2`; everything
else (`/`) goes to the `frontend` ClusterIP Service on port 8080,
load-balanced across the 2 frontend Pods (nginx serving the built React
app) on the same two workers. When the backend needs the database, it
resolves `postgres.taskapp.svc.cluster.local` (the headless Service)
and connects directly to the single `postgres-0` Pod on port 5432,
wherever the StatefulSet's Pod is currently scheduled.

## 4. The single-server assumptions you fixed

| Single-server assumption | Why it breaks at scale | How you fixed it |
|---|---|---|
| migrate-on-boot in the entrypoint | 2+ replicas race on `alembic upgrade head` simultaneously on first rollout — last writer wins, or the migration tool errors on a concurrent lock | Migrations extracted into a separate `Job` (`manifests/app/04-migration-job.yaml`) that runs exactly once, as an Argo CD `PreSync` hook, before the backend Deployment is synced. Backend Pods' entrypoint no longer runs migrations at all. |
| named volume on the host | A named Docker volume lives on one specific host's disk; Kubernetes Pods can be rescheduled to *any* node, and a plain volume wouldn't follow them | Postgres runs as a `StatefulSet` with a `PersistentVolumeClaim` (`manifests/app/03-postgres-statefulset.yaml`) on k3s's `local-path` storage class — Kubernetes tracks which node holds the PV and reschedules the StatefulSet's Pod back to that same node, so the data follows. (Caveat: `local-path` is node-pinned, not networked storage — see "Choices & trade-offs" below.) |
| `ports:` published on the host | With many Pods across many nodes, "publish a port on the host" doesn't even make sense as a concept anymore — which host? | A single `Ingress` (`manifests/app/07-ingress.yaml`) fronts everything; Traefik is the one front door regardless of which node serves the request, and Services give every tier a stable ClusterIP/DNS name independent of Pod scheduling. |
| self-healing (a crashed container on one box just... stays down until someone notices) | At 3 nodes, "someone notices and restarts it" doesn't scale, and a dead node takes everything on it down with no automatic recovery | Kubernetes' controllers (Deployment, StatefulSet) continuously reconcile actual state to desired state — a crashed Pod is restarted automatically (`livenessProbe`), and a Pod on a dead node is rescheduled elsewhere (proven live in the failover demo: `kubectl drain <node>`). |
| zero-downtime deploys (single container: stop old, start new, brief outage in between) | At 1 replica this is an acceptable few-second blip; the brief requires *zero* dropped requests during a deploy | `RollingUpdate` with `maxUnavailable: 0, maxSurge: 1` on both Deployments, combined with `readinessProbe` (so a new Pod isn't sent traffic until it's actually ready) and a `preStop` hook with a 5s sleep (so an old Pod keeps serving in-flight requests for a moment after being marked for termination, giving the endpoint controller time to remove it from load-balancing before SIGTERM). |
| secrets in a `.env` file on the host / Portainer env vars | A `.env` file is host-local and not something multiple nodes share; Portainer's env var UI doesn't exist on a multi-node cluster | Split exactly as before: non-secret config in a `ConfigMap` (`manifests/app/01-configmap.yaml`), secret config in a `Secret` created out-of-band against the cluster (never committed — see `manifests/app/02-secret.example.yaml`), with an explicit `Prune=false` annotation so Argo CD's automated pruning doesn't delete it (see `gitops/app/application.yaml` for why `ignoreDifferences` alone is *not* sufficient for a resource that isn't in git at all). |

## 5. Choices & trade-offs

**Raw YAML vs Helm vs Kustomize — why raw YAML.** For a single
environment (no staging/prod split, no per-environment overrides) and a
3-week solo capstone, Helm's templating and Kustomize's overlay
mechanism both solve a problem we don't have yet. Raw YAML is the most
direct, most auditable option for a grader reading `git log -p`, and
it's what the numbered file ordering in `manifests/app/` directly
documents (apply order = file order = dependency order). If this app
ever needed staging vs. production, Kustomize would be the natural next
step — its base+overlay model maps cleanly onto "same manifests,
different replica counts/resource limits per environment."

**Traefik vs ingress-nginx — why Traefik.** The community
`ingress-nginx` project (`kubernetes/ingress-nginx`) is retired/archived
as of March 2026 — no further security patches, repository in
read-only/maintenance mode. Shipping a retired, unpatched component as
the public-facing TLS termination point of a graded "production-style"
capstone is the wrong trade-off, so we deliberately kept k3s's bundled
Traefik (actively maintained, first-class cert-manager support via the
standard `Ingress` resource, zero extra install step) instead of
following the originally-planned ingress-nginx route. This also
slightly simplifies the platform layer: no separate ingress controller
installation, one less thing to wire into GitOps.

**CNI / NetworkPolicy enforcement — what and why.** k3s ships flannel
(the actual CNI / pod network data plane) *together with* kube-router's
network policy controller, running in firewall-only mode specifically
to enforce standard Kubernetes `NetworkPolicy` objects via iptables.
This is a common point of confusion: "flannel doesn't enforce
NetworkPolicy" is true in isolation, but k3s doesn't rely on flannel
alone for that — the bundled kube-router controller closes that gap by
default. No extra CNI install or `--flannel-backend` change was needed;
our `k3s-server` Ansible role doesn't disable the network policy
controller. See `manifests/app/09-networkpolicy.yaml` for the
default-deny + selective-allow policies this enables.

**Secrets approach — out-of-band, not Sealed/External Secrets.** Sealed
Secrets and External Secrets Operator are both explicitly listed as
*Stretch* goals in the brief, not Core requirements. Implementing one of
them would mean either committing an extra controller + encrypting a
keypair (Sealed Secrets) or wiring up an external secret store like AWS
Secrets Manager (External Secrets) — both reasonable for a real
production system, but more moving parts than this capstone's scope
needs, given we already hit the Advanced ≥3 requirement elsewhere (HPA,
NetworkPolicy, PDB). Instead, `taskapp-secret` is created directly
against the cluster with `kubectl create secret` (never written to a
file), and protected from Argo CD's automated pruning with a
`Prune=false` sync-option annotation applied to the live object — see
`manifests/app/02-secret.example.yaml` for the exact command and
`gitops/app/application.yaml` for why `ignoreDifferences` alone doesn't
work for a resource with zero presence in git.

**Remote state locking — S3 native lockfile, not DynamoDB.** Terraform
1.11+ (GA) supports `use_lockfile = true` directly on the S3 backend,
which the upstream Terraform project now recommends over the
older S3+DynamoDB pattern; `dynamodb_table` is deprecated and scheduled
for removal from the S3 backend. This satisfies the brief's "S3 +
DynamoDB lock, **or equivalent**" wording with one fewer AWS resource
and no extra IAM surface to manage — see
`infra/terraform/backend.tf`.

**Postgres storage — `local-path`, not networked storage, single
replica.** k3s's default `local-path-provisioner` storage class is
node-local: a PV created on `worker-1` only exists on `worker-1`'s disk.
This is sufficient to prove the Core requirement ("data survives a Pod
delete" — Kubernetes reschedules the StatefulSet's Pod back to the same
node, and the PVC reattaches), but it does **not** survive that specific
node being terminated/replaced. True node-agnostic durability would
need networked block storage (e.g. the AWS EBS CSI driver) or a
multi-replica Postgres with streaming replication — both explicitly
*Stretch* goals in the brief ("Multi-replica HA Postgres or a managed
DB, with a written trade-off analysis"), not implemented here. This is
a deliberate, documented scope boundary, not an oversight: for a 3-week
solo capstone where the grading weight is concentrated in §4 Core (30
pts) and the Advanced trio (15 pts), implementing full storage HA would
have traded breadth (the required Advanced picks) for depth in an area
explicitly marked optional.
