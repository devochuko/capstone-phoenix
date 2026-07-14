# manifests/app/

Apply order matters (the numeric prefixes enforce it for manual
`kubectl apply -f manifests/app/` during development; Argo CD's sync
waves + the migration Job's PreSync hook enforce the same order under
GitOps — see gitops/app/application.yaml).

| File | Object(s) | Core/Advanced requirement satisfied |
|---|---|---|
| `00-namespace.yaml` | Namespace | dedicated namespace |
| `01-configmap.yaml` | ConfigMap | non-secret config, split from Secret |
| `02-secret.example.yaml` | Secret (template only — see file header) | secret config, NOT committed for real |
| `02-postgres-service.yaml` | Service (headless) | stable DNS for the StatefulSet |
| `03-postgres-statefulset.yaml` | StatefulSet + PVC | persistent storage, probes, resources, securityContext |
| `04-migration-job.yaml` | Job | migrations as a Job, not in the entrypoint — fixes the 2+ replica race |
| `05-backend-deployment.yaml` | Deployment | 2 replicas, anti-affinity, probes, resources, securityContext, RollingUpdate maxUnavailable:0, graceful shutdown |
| `05-backend-service.yaml` | Service | stable backend endpoint |
| `06-frontend-deployment.yaml` | Deployment | same as backend, for the frontend tier |
| `06-frontend-service.yaml` | Service | stable frontend endpoint |
| `07-ingress.yaml` | Ingress | TLS via cert-manager, same-origin /api routing |
| `08-hpa.yaml` | HorizontalPodAutoscaler | **Advanced**: HPA on backend |
| `09-networkpolicy.yaml` | NetworkPolicy ×4 | **Advanced**: default-deny + selective allow |
| `10-pdb.yaml` | PodDisruptionBudget ×2 | **Advanced**: PDB + graceful shutdown |

## Before applying for real

Every `image:` field has a `REPLACE_WITH_PINNED_SHA` placeholder —
substitute the actual GHCR tag (commit SHA or semver) before
`kubectl apply` or committing to the GitOps repo. `:latest` anywhere is
an automatic fail per the capstone's hard constraints (§5).

## Manual apply (for local testing, NOT the final graded state)

```bash
kubectl apply -f manifests/app/00-namespace.yaml
kubectl apply -f manifests/app/01-configmap.yaml
# create the REAL secret out-of-band here — see 02-secret.example.yaml
kubectl apply -f manifests/app/02-postgres-service.yaml
kubectl apply -f manifests/app/03-postgres-statefulset.yaml
kubectl wait --for=condition=ready pod -l app=postgres -n taskapp --timeout=180s
kubectl apply -f manifests/app/04-migration-job.yaml
kubectl wait --for=condition=complete job/taskapp-migrate -n taskapp --timeout=120s
kubectl apply -f manifests/app/05-backend-deployment.yaml
kubectl apply -f manifests/app/05-backend-service.yaml
kubectl apply -f manifests/app/06-frontend-deployment.yaml
kubectl apply -f manifests/app/06-frontend-service.yaml
kubectl apply -f manifests/app/07-ingress.yaml
kubectl apply -f manifests/app/08-hpa.yaml
kubectl apply -f manifests/app/09-networkpolicy.yaml
kubectl apply -f manifests/app/10-pdb.yaml
```

The FINAL, GRADED state must be reconciled by Argo CD instead — see
`gitops/app/` and `docs/RUNBOOK.md` step 5. This manual sequence exists
only to test the manifests work in isolation before handing them to
GitOps.
