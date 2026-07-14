# Repo structure

```
capstone-phoenix/
├── README.md               # the brief summary
├── STRUCTURE.md             # this file
├── .gitignore               # covers state, kubeconfig, .env, secrets
│
├── infra/
│   ├── terraform/            # 3+ nodes, network, firewall, REMOTE state
│   │   ├── modules/
│   │   │   ├── network/        # VPC, subnets, IGW, route tables
│   │   │   ├── security_group/ # least-privilege firewall rules
│   │   │   └── compute/        # control-plane + worker EC2 instances
│   │   ├── backend.tf          # S3 + DynamoDB remote state
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf          # node IPs for Ansible
│   │   └── terraform.tfvars.example
│   │
│   └── ansible/             # roles: hardening, k3s-server, k3s-agent
│       ├── roles/
│       │   ├── hardening/
│       │   ├── k3s-server/
│       │   └── k3s-agent/
│       ├── inventory/
│       │   └── hosts.ini.example
│       └── site.yml
│
├── manifests/               # TaskApp + platform (raw YAML; see ARCHITECTURE.md
│   │                          for why raw YAML vs Helm/kustomize)
│   ├── platform/              # ingress-nginx, cert-manager, metrics-server
│   └── app/                   # namespace, ConfigMap/Secret, Postgres StatefulSet,
│                                 migration Job, Deployments, Ingress, HPA,
│                                 NetworkPolicy, PDB
│
├── gitops/                  # Argo CD Applications pointing at manifests/
│   ├── platform/              # platform Application (app-of-apps child)
│   └── app/                   # TaskApp Application (app-of-apps child)
│
└── docs/
    ├── ARCHITECTURE.md        # diagram + "which single-server assumption each fix solves"
    ├── RUNBOOK.md             # zero -> running, scale, roll back, recover
    ├── COST.md                # itemized monthly cost + how to halve it
    └── EVIDENCE/              # screenshots/logs proving each claim
```

## Definition of done

A teammate clones this repo, follows `docs/RUNBOOK.md`, and ends up with the same
live, HTTPS, multi-node, GitOps-managed TaskApp — without asking anything.
