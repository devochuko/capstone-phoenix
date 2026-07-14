# gitops/platform/

The Argo CD `Application` for the part of the platform layer that's a
plain Kubernetes object: the cert-manager `ClusterIssuer`.

cert-manager and Argo CD themselves are installed via their official
upstream manifests, OUTSIDE of GitOps (see
`manifests/platform/cert-manager/install-notes.md` and
`manifests/platform/argocd/install-notes.md`) — a controller can't
manage the installation of itself, so this layer is intentionally
"day-0 bootstrap, then GitOps takes over for everything downstream of
that."

```bash
kubectl apply -f gitops/platform/application.yaml
argocd app get platform
```
