# Fresh environment — no adopted state, so it just uses the module's
# default naming convention (name_prefix-derived) instead of pinning
# literal names like prod does.
module "app" {
  source = "../../modules/app-infra"

  name_prefix          = "staging"
  vpc_cidr             = "10.10.0.0/16"
  azs                  = ["ap-south-1a", "ap-south-1b"]
  public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnet_cidrs = ["10.10.101.0/24", "10.10.102.0/24"]
  instance_type        = "t3.micro"

  enable_deletion_protection = false
}

output "alb_dns_name" {
  value = module.app.alb_dns_name
}

output "vpc_id" {
  value = module.app.vpc_id
}

output "instance_ids" {
  value = module.app.instance_ids
}
