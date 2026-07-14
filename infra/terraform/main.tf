module "network" {
  source = "./modules/network"

  name_prefix        = var.name_prefix
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  availability_zone  = var.availability_zone
}

module "security_group" {
  source = "./modules/security_group"

  name_prefix = var.name_prefix
  vpc_id      = module.network.vpc_id
  admin_cidr  = var.admin_cidr
}

module "compute" {
  source = "./modules/compute"

  name_prefix       = var.name_prefix
  subnet_id         = module.network.public_subnet_id
  security_group_id = module.security_group.security_group_id
  instance_type     = var.instance_type
  worker_count      = var.worker_count
  ssh_key_name      = var.ssh_key_name
}
