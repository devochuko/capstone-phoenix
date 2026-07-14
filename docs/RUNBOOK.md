# Runbook

This is the exact path from zero to a live, HTTPS, multi-node,
GitOps-managed TaskApp. Follow it in order — each step depends on the
one before it.

## Pre-flight checklist (do this first)

Before touching Terraform, confirm these — getting them wrong is the
most common reason this runbook stalls partway through:

- [ ] AWS credentials configured (`aws sts get-caller-identity` succeeds)
- [ ] An EC2 key pair exists in `eu-north-1` (create one — see
      `infra/terraform/terraform.tfvars.example` for the exact command)
- [ ] Your public IP, in CIDR form: `curl -s https://checkip.amazonaws.com`
- [ ] You control DNS for `pilgrim.name.ng` and can add an A record
- [ ] **You know the real container port and health-check path for
      `taskapp-backend` and `taskapp-frontend`.** This repo currently
      assumes backend port **5000** (confirmed) and frontend port
      **8080** (placeholder, NOT yet confirmed against the real image —
      check before deploying) with health endpoints `/api/health` and
      `/healthz` respectively (also placeholders). Check the images
      directly:
      ```bash
      docker pull ghcr.io/ts-a-devops/taskapp-backend:<tag>
      docker inspect ghcr.io/ts-a-devops/taskapp-backend:<tag> --format '{{.Config.ExposedPorts}}'
      docker pull ghcr.io/ts-a-devops/taskapp-frontend:<tag>
      docker inspect ghcr.io/ts-a-devops/taskapp-frontend:<tag> --format '{{.Config.ExposedPorts}}'
      ```
      If the real values differ, fix them in `manifests/app/05-backend-deployment.yaml`,
      `05-backend-service.yaml`, `07-ingress.yaml`, `09-networkpolicy.yaml`
      (backend port) and `06-frontend-deployment.yaml`,
      `06-frontend-service.yaml` (frontend port) before proceeding.
- [ ] You have a pinned image tag (commit SHA or semver) for both
      images — replace every `REPLACE_WITH_PINNED_SHA` in
      `manifests/app/`. `:latest` anywhere is an automatic fail.

## 1. Bootstrap remote state (ONE TIME ONLY)

```bash
cd infra/terraform
chmod +x bootstrap-backend.sh
./bootstrap-backend.sh phoenix-tfstate-<your-unique-suffix> eu-north-1
```

Then edit `backend.tf` and replace `phoenix-tfstate-CHANGEME` with the
bucket name you just created.

## 2. Infrastructure (Terraform)

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set admin_cidr (your IP) and ssh_key_name

terraform init
terraform plan    # review: 1 control-plane + 2 workers, VPC, SG
terraform apply
```

Confirm SSH works to every node before moving on:

```bash
terraform output  # note control_plane_public_ip, worker_public_ips
ssh -i ~/.ssh/capstone-key.pem ubuntu@<control-plane-public-ip>
```

**Add the DNS record now**, using the control-plane's public IP:

```
A    taskapp.pilgrim.name.ng    ->   <control_plane_public_ip>
```

DNS propagation can take a few minutes — verify with
`dig +short taskapp.pilgrim.name.ng` before the cert-manager step later,
since HTTP-01 validation will fail until this resolves correctly.

## 3. Cluster bring-up (Ansible)

```bash
cd ../ansible
ansible-galaxy collection install -r requirements.yml

cp inventory/hosts.ini.example inventory/hosts.ini
# edit hosts.ini: paste the output of, from infra/terraform:
#   terraform output ansible_inventory_hint

ansible-playbook site.yml
```

Run it a second time to confirm idempotency (acceptance criteria):

```bash
ansible-playbook site.yml   # should report changed=0 on every task
```

Fetch and verify the kubeconfig:

```bash
export KUBECONFIG=$(pwd)/kubeconfig   # role fetches it here, gitignored
kubectl get nodes -o wide             # control-plane + both workers = Ready
```

## 4. Platform (ingress is already running — Traefik; install the rest)

Traefik is already running (k3s default, kept enabled — see
`PROJECT_VALUES.md`). Confirm metrics-server is up (also bundled by
default):

```bash
kubectl top nodes   # should return numbers, not an error
```

Install cert-manager:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.2/cert-manager.yaml
kubectl rollout status -n cert-manager deploy/cert-manager
kubectl rollout status -n cert-manager deploy/cert-manager-webhook
kubectl rollout status -n cert-manager deploy/cert-manager-cainjector

kubectl apply -f manifests/platform/cert-manager/cluster-issuer.yaml
kubectl describe clusterissuer letsencrypt-prod   # READY: True
```

Install Argo CD:

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.4/manifests/install.yaml
kubectl rollout status -n argocd deploy/argocd-server

kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
# save this password, then:
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd login localhost:8080 --username admin   # paste password
argocd account update-password
```

Full detail/troubleshooting: `manifests/platform/cert-manager/install-notes.md`,
`manifests/platform/argocd/install-notes.md`.

## 5. GitOps takes over

**Before this step**, create the real Secret out-of-band (never as a
committed file):

```bash
kubectl create namespace taskapp
kubectl create secret generic taskapp-secret \
  --namespace taskapp \
  --from-literal=POSTGRES_USER='taskapp' \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=SECRET_KEY="$(openssl rand -base64 32)"

kubectl annotate secret taskapp-secret -n taskapp \
  argocd.argoproj.io/sync-options=Prune=false
```

Fork this repo (per README.md — Type: individual, fork
`ts-a-devops/capstone-phoenix`), then edit `repoURL` in
`gitops/platform/application.yaml` and `gitops/app/application.yaml` to
point at your fork. Commit and push, then:

```bash
kubectl apply -f gitops/platform/application.yaml
kubectl apply -f gitops/app/application.yaml

argocd app get platform
argocd app get taskapp   # wait for Synced + Healthy
```

From this point forward, **the cluster's app state is owned by Argo
CD**. Do not run `kubectl apply` against `manifests/app/` manually again
— push a commit instead, and let Argo sync it.

## 6. Verify everything

```bash
curl -vI https://taskapp.pilgrim.name.ng/          # valid cert, 200
curl -vI https://taskapp.pilgrim.name.ng/api/health # backend reachable
kubectl get pods -n taskapp -o wide                 # spread across nodes
kubectl get hpa -n taskapp
kubectl get networkpolicy -n taskapp
kubectl get pdb -n taskapp
```

---

## Day-2 operations

### Scale a tier

Prefer a git commit so Argo stays the source of truth (don't
`kubectl scale` directly — `selfHeal: true` will just revert it):

```bash
# edit manifests/app/05-backend-deployment.yaml: replicas: 2 -> 3
git commit -am "scale backend to 3 replicas"
git push
argocd app sync taskapp   # or wait for the next auto-poll
```

### Roll back a bad deploy

```bash
git revert <bad-commit-sha>
git push
# Argo auto-syncs back to the previous manifest state.
```

Or, for an immediate rollback without waiting on git:

```bash
argocd app history taskapp
argocd app rollback taskapp <revision-id>
```

(Note: a `rollback` via argocd CLI is a deviation from "git owns it" —
treat it as a break-glass emergency action, then immediately follow up
with a git revert so the repo and cluster state agree again.)

### Run a new migration safely

The migration Job (`manifests/app/04-migration-job.yaml`) runs
automatically as an Argo CD `PreSync` hook on every sync — you don't
trigger it separately. To force a re-run without changing anything
else, bump the image tag (even a no-op rebuild) and push; Argo will
delete-and-recreate the hook Job (`BeforeHookCreation` policy) and run
it again before touching the Deployments.

### Rotate a secret

```bash
kubectl delete secret taskapp-secret -n taskapp
kubectl create secret generic taskapp-secret \
  --namespace taskapp \
  --from-literal=POSTGRES_USER='taskapp' \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=SECRET_KEY="$(openssl rand -base64 32)"
kubectl annotate secret taskapp-secret -n taskapp \
  argocd.argoproj.io/sync-options=Prune=false

kubectl rollout restart deployment/backend -n taskapp
kubectl rollout restart statefulset/postgres -n taskapp
```

(If you rotate `POSTGRES_PASSWORD`, Postgres itself needs the password
changed inside the database too — `ALTER USER` — not just the Secret
swapped, or the backend won't be able to authenticate. The Secret swap
alone updates what the *backend* will try next; it doesn't change what
Postgres *expects*.)

---

## Failure recovery (you'll demo one of these live)

### A worker node dies / is drained

This is the live-demo command:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

**What happens:** the PDBs (`manifests/app/10-pdb.yaml`, `minAvailable:
1` on both backend and frontend) prevent the drain from evicting *all*
replicas of a tier at once — eviction blocks until at least one replica
survives elsewhere. Pods on the drained node receive SIGTERM (after the
5s `preStop` sleep), and the endpoint controller removes them from
Service load-balancing as soon as they stop being Ready — combined with
`maxUnavailable: 0` on the Deployment's rolling update strategy and
`topologySpreadConstraints` having already spread replicas across
nodes, the *other* node's replica keeps serving traffic the entire
time. The Deployment controller then schedules replacement Pods onto
the remaining healthy worker.

**Expected recovery time:** new Pods reach `Ready` within roughly
30–60s (limited mostly by `startupProbe.failureThreshold` ×
`periodSeconds` on the backend/frontend, plus image pull time if not
already cached on that node).

**What you do:** nothing, if the system is working correctly — that's
the point of the demo. To bring the node back:
`kubectl uncordon <node>`.

### A backend Pod crashloops

```bash
kubectl get pods -n taskapp                          # spot the CrashLoopBackOff
kubectl logs <pod> -n taskapp --previous              # logs from the crashed instance
kubectl describe pod <pod> -n taskapp                  # events, exit code, probe failures
kubectl get events -n taskapp --sort-by=.lastTimestamp # cluster-wide recent events
```

Common causes for this app specifically: `taskapp-secret` missing or
has wrong keys (check `kubectl get secret taskapp-secret -n taskapp -o
jsonpath='{.data}'` — keys should be `POSTGRES_USER`,
`POSTGRES_PASSWORD`, `SECRET_KEY`), or the migration Job never
completed (check `kubectl get job taskapp-migrate -n taskapp`) so the
schema doesn't match what the backend expects.

### A bad migration

```bash
kubectl logs job/taskapp-migrate -n taskapp   # see what alembic actually did
```

If the migration partially applied and broke the schema: connect
directly and use `alembic downgrade -1` (or the specific revision) from
a one-off debug Pod using the same backend image, pointed at the same
`taskapp-secret`/`taskapp-config`, then fix the migration file and let
the next sync's `PreSync` hook re-run `alembic upgrade head` correctly.
For anything destructive, restore from your most recent Postgres backup
if you've implemented the CronJob backup Stretch goal (not implemented
in this repo — see `docs/ARCHITECTURE.md`).

### Postgres Pod is rescheduled

Proves the PVC re-attaches and data is intact:

```bash
kubectl delete pod postgres-0 -n taskapp
kubectl get pod postgres-0 -n taskapp -w   # watch it come back Ready
kubectl exec -it postgres-0 -n taskapp -- psql -U taskapp -d taskapp -c '\dt'
# confirm your tables and data are still there
```

This works because the StatefulSet's PVC is bound to the same
`local-path` volume regardless of Pod restarts, **as long as it's
rescheduled onto the same node it was already on** — see
`docs/ARCHITECTURE.md` "Choices & trade-offs" for the honest caveat
about `local-path` not being true networked storage.
