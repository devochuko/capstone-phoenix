variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "admin_cidr" {
  description = "Your IP in CIDR form (e.g. 1.2.3.4/32) — the ONLY source allowed to reach port 22."
  type        = string
}
