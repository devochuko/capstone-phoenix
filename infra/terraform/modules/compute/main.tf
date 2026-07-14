# Control-plane (1) + workers (2+), all in the same subnet/SG.
# Single k3s server is intentional — the brief explicitly says control-plane
# HA is not required. The control-plane node is also a worker (k3s server
# runs the agent too), so we don't need a separate worker node for it.


data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name        = "${var.name_prefix}-control-plane"
    Role        = "k3s-server"
    Project     = "Capstone-Phoenix"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Owner       = "Ogheneochuko Edaferioka"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail
              hostnamectl set-hostname control-plane
              apt-get update -y
              apt-get install -y python3
              EOF

  user_data_replace_on_change = true
}

resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name        = "${var.name_prefix}-worker-${count.index + 1}"
    Role        = "k3s-agent"
    Project     = "Capstone-Phoenix"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail
              hostnamectl set-hostname worker-${count.index + 1}
              apt-get update -y
              apt-get install -y python3
              EOF

  user_data_replace_on_change = true
}
