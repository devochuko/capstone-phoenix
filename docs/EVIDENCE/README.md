# docs/EVIDENCE/

Drop screenshots/logs here, named so a grader knows what each proves.
This folder is currently empty — it can only be filled in once the
cluster is actually running, since these are proofs of a live system,
not something that can be generated in advance.

| Filename | Command to produce it |
|---|---|
| `nodes-ready.png` | `kubectl get nodes -o wide` — all Ready |
| `pods-spread.png` | `kubectl get pods -n taskapp -o wide` — backend/frontend replicas on different `NODE` columns |
| `tls-valid.png` | `curl -vI https://taskapp.pilgrim.name.ng` (look for `SSL certificate verify ok`) or an SSL Labs report |
| `pvc-persist.log` | Output of the "Postgres Pod is rescheduled" sequence in `docs/RUNBOOK.md` — delete the Pod, watch it come back, query the data |
| `zero-downtime.log` | A `while curl -s -o /dev/null -w "%{http_code}\n" https://taskapp.pilgrim.name.ng; do sleep 0.5; done` loop running in one terminal while you push a deploy in another — save the output, confirm no non-200 lines during the rollout |
| `hpa-scale.png` | `kubectl get hpa -n taskapp -w` during a load test (e.g. `hey -z 2m -c 50 https://taskapp.pilgrim.name.ng/api/health`) — show REPLICAS climbing |
| `argocd-synced.png` | `argocd app get taskapp` showing `Synced` + `Healthy`, or the Argo CD UI |
| `failover.png` | `kubectl get pods -n taskapp -o wide` immediately after `kubectl drain <node>`, showing the app still up and Pods rescheduled |

Capture these as you complete each milestone in `docs/RUNBOOK.md` rather
than all at the end — it's much easier to get clean evidence right
after you've confirmed something works than to try to reconstruct it
later.
