# Cost

**Status: template — fill in real numbers after `terraform apply` and a
few days of AWS Cost Explorer data.** Placeholder cells are marked
`TBD`. Don't submit this doc with `TBD`s still in it — replace them
before the deadline.

## How to get the real numbers

```bash
# Actual on-demand rate: AWS Pricing Calculator, region = Europe (Stockholm)
# https://calculator.aws/

# After a few days running, pull real spend from Cost Explorer:
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '7 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Itemized monthly cost

| Item | Quantity | Unit cost | Monthly cost |
|---|---|---|---|
| EC2 `t3.small` (control-plane) | 1 | TBD /hr × 730 hr | TBD |
| EC2 `t3.small` (workers) | 2 | TBD /hr × 730 hr | TBD |
| EBS gp3 root volume, 20GB, encrypted | 3 | $0.08/GB-month (gp3 list price) | ~$4.80 |
| EBS (Postgres PVC, `local-path` backing disk — shares the node's root volume, not a separate EBS volume) | 0 (included above) | — | $0 |
| Data transfer out to internet | variable | first 100GB/mo free, then ~$0.09/GB | TBD (likely $0 for a demo/grading workload) |
| S3 (Terraform state bucket) | 1 bucket, <1MB | negligible | <$0.01 |
| Elastic IP | 0 (using dynamic public IPs, not EIPs) | - | $0 |
| Route 53 / DNS | 0 (using existing `pilgrim.name.ng` registrar's DNS, not Route 53) | - | $0 |
| Let's Encrypt certificates | - | free | $0 |
| **Total** | | | **TBD** |

For reference, AWS list pricing for `t3.small` in `us-east-1` is
roughly **$0.0208/hr (~$15.18/mo)** as of mid-2026 — `eu-north-1`
(Stockholm) pricing is typically close to but not identical to
`us-east-1`; confirm the exact regional rate via the AWS Pricing
Calculator before filling in the table above, rather than assuming the
`us-east-1` figure applies unchanged.

## How you'd cut it in half

The single biggest lever here is instance count and uptime, not storage
or networking — compute is overwhelmingly the dominant line item for a
cluster this small, and storage/data-transfer costs are already
near-zero for a demo workload.

1. **Don't run the cluster 24/7 between work sessions.** This capstone
   requires 3 nodes minimum *for the graded submission*, but nothing
   requires the cluster to stay up continuously while you're not
   actively working on it. `terraform destroy` / `terraform apply` on
   demand around actual work sessions cuts the bill roughly in
   proportion to hours actually running — for a project graded over a
   fixed window, this is probably the single biggest realistic saving
   available without touching the architecture at all.
2. **Use a 1-year Savings Plan or Reserved Instance pricing** if this
   ran long-term in production rather than for a 3-week capstone — list
   pricing shows roughly 35-40% savings for a 1-year commitment on
   `t3`-class instances, though this only pays off if the cluster runs
   continuously for that long, which doesn't apply here.
3. **Move to a cheaper-per-vCPU provider for the same workload.**
   Hetzner or DigitalOcean typically price comparable burstable
   instances notably below AWS on-demand rates; the brief explicitly
   says cloud choice is open and to "pick the cheapest that gives you 3
   small VMs." AWS was chosen deliberately for IAM/Terraform provider
   familiarity carried over from earlier lessons, not because it's the
   cheapest option — that's the honest trade-off being made here.
