# manifests/platform/cert-manager/install-notes.md

Install cert-manager via the official upstream manifest, pinned to a
specific version for reproducibility.

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.2/cert-manager.yaml

kubectl rollout status -n cert-manager deploy/cert-manager
kubectl rollout status -n cert-manager deploy/cert-manager-webhook
kubectl rollout status -n cert-manager deploy/cert-manager-cainjector
kubectl get pods -n cert-manager
```

Then apply the ClusterIssuer (this folder):

```bash
kubectl apply -f manifests/platform/cert-manager/cluster-issuer.yaml
kubectl describe clusterissuer letsencrypt-prod   # should show READY: True
```

## Why no `ingressClassName` debugging needed

Traefik (k3s's bundled, kept-enabled ingress controller — see
`PROJECT_VALUES.md`) is set as the default `IngressClass` in k3s. The
`ClusterIssuer`'s HTTP-01 solver explicitly sets
`ingress.ingressClassName: traefik` so cert-manager's temporary challenge
Ingress is unambiguous about which controller should serve it, even
though Traefik would pick it up by default regardless.

## Common failure mode (documented for the RUNBOOK)

If `kubectl describe certificate <name>` shows the challenge stuck in
`pending`, check:

1. DNS actually resolves `taskapp.pilgrim.name.ng` to the control-plane's
   public IP (`dig +short taskapp.pilgrim.name.ng`).
2. Port 80 is reachable from the public internet (the security group
   opens it — see `infra/terraform/modules/security_group`), since
   HTTP-01 validation happens over plain HTTP before any cert exists.
3. The Ingress for the app actually has the
   `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation
   (see `manifests/app/ingress.yaml`).
