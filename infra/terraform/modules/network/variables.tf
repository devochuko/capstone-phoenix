variable "name_prefix" {
  description = "Prefix applied to all resource names/tags in this module."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet (all 3 nodes live here for simplicity — see ARCHITECTURE.md)."
  type        = string
}

variable "availability_zone" {
  description = "AZ for the public subnet."
  type        = string
}
