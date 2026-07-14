# gitops/app/

The Argo CD `Application` that makes the TaskApp itself GitOps-managed.

- `application.yaml` — points at `manifests/app/`, automated sync
  (prune + selfHeal), `CreateNamespace=true`.

Apply AFTER Argo CD is running (see
`manifests/platform/argocd/install-notes.md`) and after you've created
the out-of-band Secret with the `Prune=false` annotation (see
`manifests/app/02-secret.example.yaml` — **do this before the first
sync**, or read the comments in `application.yaml` carefully if you
apply in a different order, since sync order matters here).

```bash
kubectl apply -f gitops/app/application.yaml
argocd app get taskapp
```

The migration Job (`manifests/app/04-migration-job.yaml`) runs as an
Argo CD `PreSync` hook, so it executes and completes before the
backend/frontend Deployments are synced — this is what makes "GitOps
owns the cluster" compatible with "migrations must run before the app
starts," without you ever running `kubectl apply` by hand.
