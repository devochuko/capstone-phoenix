# Capstone — Phoenix: TaskApp on Real Kubernetes

<img width="1517" height="850" alt="image" src="https://github.com/user-attachments/assets/b1d3541d-fc67-4b1d-8e33-a0c1643d94a6" />

Take the TaskApp (React/nginx frontend, Flask/Postgres backend) that was previously
containerized and shipped to a single server with Portainer, and run it on a
self-provisioned, multi-node Kubernetes (k3s) cluster — highly available,
autoscaling, zero-downtime, behind HTTPS on a real domain, with GitOps (Argo CD)
as the sole owner of the cluster's final state.

## App under test
- Frontend: `ghcr.io/ts-a-devops/taskapp-frontend` (React/nginx)
- Backend: `ghcr.io/ts-a-devops/taskapp-backend` (Flask/Postgres)

## What this repo builds
1. **Infrastructure** (`infra/terraform/`) — 1 control-plane + 2 worker VMs on AWS,
   modular (network / security_group / compute), remote state in S3 + DynamoDB lock.
2. **Cluster** (`infra/ansible/`) — k3s bring-up via Ansible roles
   (`hardening`, `k3s-server`, `k3s-agent`), idempotent.
3. **Platform** (`manifests/platform/`) — ingress-nginx, cert-manager, metrics-server,
   Argo CD.
4. **App** (`manifests/app/`) — TaskApp hardened for multi-replica, multi-node HA:
   StatefulSet+PVC Postgres, migration Job, Deployments with anti-affinity/probes/
   resources, Ingress+TLS, HPA, NetworkPolicy, PodDisruptionBudget.
5. **GitOps** (`gitops/`) — Argo CD Applications; the cluster's desired state lives
   in this git repo and is reconciled automatically. No manual `kubectl apply` in
   the final, graded state.
6. **Docs** (`docs/`) — architecture, runbook, cost breakdown, and evidence that
   each requirement actually works.

## Repo layout
See [STRUCTURE.md](./STRUCTURE.md).

## Status
🚧 In progress — see milestones in `docs/RUNBOOK.md` as they're filled in.

## Quickstart
Full zero-to-running instructions live in [docs/RUNBOOK.md](./docs/RUNBOOK.md).
