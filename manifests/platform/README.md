# manifests/platform/

Cluster-wide platform components, installed BEFORE the app (manifests/app/)
because the app depends on them (Ingress needs a working TLS issuer, HPA
needs metrics-server, GitOps needs Argo CD already running to manage
everything after this point).

Install order (documented fully in docs/RUNBOOK.md):

1. **metrics-server** — already bundled with k3s by default (NOT disabled
   in our k3s-server role). Nothing to install here; just verify with
   `kubectl top nodes`.
2. **cert-manager** — installed via the official upstream manifest
   (`cert-manager/install.yaml`), then our `ClusterIssuer` (this folder)
   is applied on top.
3. **Argo CD** (`argocd/`) — installed via the official upstream manifest.
   From this point on, GitOps owns the app — see gitops/.

Why Traefik isn't listed here: it's k3s's bundled ingress controller and
is already running by the time Ansible finishes (kept enabled — see
PROJECT_VALUES.md for why we didn't use community ingress-nginx, which is
retired/archived as of March 2026).

## cert-manager/

- `cluster-issuer.yaml` — Let's Encrypt **production** ClusterIssuer using
  the HTTP-01 challenge. No `ingress.class` needed: Traefik watches all
  Ingress objects by default, so cert-manager's self-provisioned challenge
  Ingress gets picked up automatically.

A staging issuer is intentionally NOT included by default — switch the
`server:` field to the staging ACME URL temporarily if you're debugging
and want to avoid Let's Encrypt's production rate limits, then switch
back before the final graded state.

## argocd/

- `install-notes.md` — exact install command (Helm/manifest) referenced
  from docs/RUNBOOK.md.
