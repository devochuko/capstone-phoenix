variable "name_prefix" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "instance_type" {
  description = "EC2 instance type for all nodes."
  type        = string
}

variable "worker_count" {
  description = "Number of k3s agent (worker) nodes. Must be >= 2 per capstone requirements."
  type        = number

  validation {
    condition     = var.worker_count >= 2
    error_message = "Capstone requires 3 nodes minimum: 1 control-plane + 2+ workers."
  }
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair (public key) for SSH access."
  type        = string
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 20
}
