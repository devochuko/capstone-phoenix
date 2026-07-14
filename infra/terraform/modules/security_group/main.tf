# Least-privilege firewall (capstone requirement):
#   - 22   open ONLY to admin_cidr (your IP), not 0.0.0.0/0
#   - 6443 (k8s API) open ONLY to admin_cidr (your IP) for local kubectl access
#   - 80   open to the world (HTTP) - redirected to HTTPS by Traefik
#   - 443  open to the world (HTTPS / TLS termination)
#   - All other node-to-node ports (kubelet, flannel, etc.) are INTERNAL ONLY.
#
# A single SG, self-referencing for internal traffic, keeps this simple for
# a 3-node cluster while satisfying security constraints.

resource "aws_security_group" "nodes" {
  name        = "${var.name_prefix}-nodes-sg"
  description = "k3s cluster nodes least-privilege ingress and self-referencing internal rule"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.name_prefix}-nodes-sg"
    Project     = "Capstone-Phoenix"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# --- Inbound: world ---

resource "aws_vpc_security_group_ingress_rule" "ssh_admin" {
  security_group_id = aws_security_group.nodes.id
  description       = "SSH from admin IP only"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "k8s_api_admin" {
  security_group_id = aws_security_group.nodes.id
  description       = "Kubernetes API 6443 from admin IP only for secure laptop access"
  cidr_ipv4         = var.admin_cidr
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "http_world" {
  security_group_id = aws_security_group.nodes.id
  description       = "HTTP Traefik ingress open to world for web traffic and ACME challenges"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https_world" {
  security_group_id = aws_security_group.nodes.id
  description       = "HTTPS Traefik ingress open to world for secure TLS traffic"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# --- Inbound: internal cluster traffic only (self-referencing SG) ---

resource "aws_vpc_security_group_ingress_rule" "internal_tcp" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "All TCP traffic between cluster nodes internal only"
  referenced_security_group_id = aws_security_group.nodes.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "internal_udp" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "All UDP traffic between cluster nodes internal only"
  referenced_security_group_id = aws_security_group.nodes.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "udp"
}

# --- Outbound: allow all ---

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.nodes.id
  description       = "Unrestricted outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

