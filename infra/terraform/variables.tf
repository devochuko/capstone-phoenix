variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-north-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names/tags."
  type        = string
  default     = "edaferioka-phoenix"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.42.1.0/24"
}

variable "availability_zone" {
  description = "AZ for the public subnet (must exist in aws_region)."
  type        = string
  default     = "eu-north-1a"
}

variable "admin_cidr" {
  description = "My IP in CIDR form, e.g. 203.0.113.4/32 — the ONLY source allowed to SSH (port 22)."
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "worker_count" {
  description = "Number of k3s agent (worker) nodes. Capstone requires 2+."
  type        = number
  default     = 2
}

variable "ssh_key_name" {
  description = "Name of an EXISTING EC2 key pair in this region (create with `aws ec2 create-key-pair` or via console first)."
  type        = string
}
